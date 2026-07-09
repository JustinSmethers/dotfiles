#!/usr/bin/env python3
"""
Daily digest pipeline (one-shot).

Gathers, for a given day:
  1. Your daily note (today + yesterday) from the configured notes vault
  2. Recent git commits across ~/GitHub repos + your GitHub PR activity (gh CLI)
  3. Your open Jira tickets (acli)
...then reconciles them into a per-ticket digest and PRINTS it.

By default it only previews. Flags:
  --write-note   Append a "## Digest (generated ...)" block into today's daily note.
  --days N       Look-back window for git/PR activity (default 2).

Jira is READ-ONLY here. Proposed Jira changes (status transitions, comments) are
printed as suggestions only — nothing is ever written to Jira by this script.

Requires: gh (authed), acli (run `acli jira auth login` once), git.
"""
import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys
from pathlib import Path

import config as _config

CFG = _config.load()
PREFIX = CFG["ticket_prefix"]
VAULT = Path(CFG["vault_path"]) if CFG["vault_path"] else Path.home()
DAILY_DIR = VAULT / CFG["daily_folder"]
# Directories whose immediate children may be git repos.
REPO_ROOTS = [Path(p) for p in CFG["repo_roots"]]
TICKET_RE = re.compile(rf"\b{re.escape(PREFIX)}-\d+\b")
# Compound refs like "PROJ-341-342" or "PROJ-341/342" mean BOTH tickets. Match the
# prefix plus any run of number groups joined by - or /, then expand each number.
COMPOUND_RE = re.compile(rf"\b{re.escape(PREFIX)}-(\d+(?:[-/]\d+)*)")


def extract_tickets(text: str) -> list[str]:
    keys = []
    for m in COMPOUND_RE.finditer(text or ""):
        for num in re.split(r"[-/]", m.group(1)):
            key = f"{PREFIX}-{num}"
            if key not in keys:
                keys.append(key)
    return keys
# Only surface commits whose author email/name matches one of these (substring match).
AUTHOR_HINTS = [h.lower() for h in CFG["author_hints"]]
# Restrict PR search to these GitHub owners (empty = all owners visible to active gh account).
PR_OWNERS: list[str] = CFG["pr_owners"]
DIGEST_MARKER = "## Digest (generated"
# Base URL for ticket links in the note (Obsidian renders markdown links).
JIRA_BASE = CFG["jira_base"]


def run(cmd: list[str], cwd: Path | None = None) -> str:
    try:
        r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=60)
        return r.stdout.strip()
    except Exception:
        return ""


def note_path(day: dt.date) -> Path:
    return DAILY_DIR / (day.strftime(CFG["daily_note_format"]) + ".md")


# ---- 1. Notes ---------------------------------------------------------------
def gather_notes(today: dt.date) -> dict:
    out = {}
    for label, day in [("today", today), ("yesterday", today - dt.timedelta(days=1))]:
        p = note_path(day)
        out[label] = {"path": p, "text": p.read_text() if p.exists() else ""}
    return out


# ---- 2. Git + PRs -----------------------------------------------------------
def discover_repos() -> list[Path]:
    """Immediate child dirs under REPO_ROOTS that are git repos (.git dir or file)."""
    seen, repos = set(), []
    for root in REPO_ROOTS:
        if not root.is_dir():
            continue
        for child in sorted(root.iterdir()):
            if not child.is_dir() or not (child / ".git").exists():
                continue
            key = child.resolve()  # dedupe case-insensitive / symlinked paths
            if key in seen:
                continue
            seen.add(key)
            repos.append(child)
    return repos


def gather_git(days: int) -> tuple[list[dict], list[dict], list[dict]]:
    """Returns (my recent commits, active branches, dirty working trees).
    All three carry configured ticket keys. `dirty` captures UNCOMMITTED local work —
    staged/unstaged/untracked changes and stashes — keyed off the branch name."""
    since = (dt.date.today() - dt.timedelta(days=days)).isoformat()
    # Sibling clones can share history, so dedupe
    # commits by SHA and branches by name across all repos.
    commits, seen_sha = [], set()
    branches, seen_branch = [], set()
    dirty = []
    for repo in discover_repos():
        branch = run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=repo)
        b_tickets = extract_tickets(branch)
        if b_tickets and branch not in seen_branch:
            seen_branch.add(branch)
            branches.append({"repo": repo.name, "branch": branch, "tickets": b_tickets})

        # Uncommitted work — a dirty tree isn't in any commit, so we must ask git status.
        # Only report it when the repo is tied to a ticket (branch name OR the per-ticket
        # clone folder name), so unrelated personal repos don't create noise.
        d_tickets = sorted(set(b_tickets) | set(extract_tickets(repo.name)))
        if d_tickets:
            status = run(["git", "status", "--porcelain"], cwd=repo).splitlines()
            untracked = sum(1 for l in status if l.startswith("??"))
            changed = len(status) - untracked
            stashes = len([l for l in run(["git", "stash", "list"], cwd=repo).splitlines() if l])
            if changed or untracked or stashes:
                dirty.append({"repo": repo.name, "branch": branch, "tickets": d_tickets,
                              "changed": changed, "untracked": untracked, "stashes": stashes})

        log = run([
            "git", "log", f"--since={since}", "--no-merges",
            "--pretty=format:%h\t%ae\t%D\t%s", "--all",
        ], cwd=repo)
        for line in filter(None, log.splitlines()):
            parts = line.split("\t", 3)
            if len(parts) != 4:
                continue
            sha, email, refs, subj = parts
            if not any(h in email.lower() for h in AUTHOR_HINTS) or sha in seen_sha:
                continue
            seen_sha.add(sha)
            # a commit's tickets come from its subject AND the refs/branches it sits on
            tickets = sorted(set(extract_tickets(subj)) | set(extract_tickets(refs)))
            commits.append({"repo": repo.name, "sha": sha, "subj": subj, "tickets": tickets})
    return commits, branches, dirty


def _pr_search(extra_args: list[str]) -> list[dict]:
    cmd = ["gh", "search", "prs", "--author=@me",
           "--json", "title,url,state,repository,updatedAt"] + extra_args
    for owner in PR_OWNERS:
        cmd += ["--owner", owner]
    raw = run(cmd)
    try:
        return json.loads(raw) if raw else []
    except json.JSONDecodeError:
        return []


def gather_prs(days: int, ticket_keys: list[str]) -> list[dict]:
    """PRs from two sources, deduped by URL:
    1. recent activity in the last `days` (catches unlinked / other PRs)
    2. per open-ticket key, WITHOUT a date limit — so a ticket still open but whose
       PR merged weeks ago still shows accurate state (the whole point of the digest).
    """
    since = (dt.date.today() - dt.timedelta(days=days)).isoformat()
    by_url: dict[str, dict] = {}
    for pr in _pr_search([f"--updated=>={since}", "--limit", "30"]):
        by_url[pr.get("url", pr.get("title", ""))] = pr
    for key in ticket_keys:
        for pr in _pr_search([key, "--limit", "10"]):
            # gh search is fuzzy — keep only PRs whose title actually names this key
            if key in extract_tickets(pr.get("title", "")):
                by_url.setdefault(pr.get("url", pr.get("title", "")), pr)
    prs = list(by_url.values())
    for pr in prs:
        pr["tickets"] = extract_tickets(pr.get("title", ""))
    return prs


# ---- 3. Jira ----------------------------------------------------------------
def adf_to_text(node) -> str:
    """Flatten Atlassian Document Format (rich-text JSON) into plain text."""
    if isinstance(node, list):
        return "".join(adf_to_text(n) for n in node)
    if isinstance(node, dict):
        if node.get("type") == "text":
            return node.get("text", "")
        inner = adf_to_text(node.get("content", []))
        # block-level nodes get a trailing newline so paragraphs/list items separate
        if node.get("type") in ("paragraph", "heading", "listItem", "codeBlock", "rule"):
            return inner + "\n"
        return inner
    return ""


def gather_tickets() -> tuple[list[dict], str]:
    raw = run(["acli", "jira", "workitem", "search",
               "--jql", CFG["jql"],
               "--fields", "key,summary,status,description", "--json", "--limit", "50"])
    if not raw:
        return [], "acli returned nothing — is it authed? Run: acli jira auth login"
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return [], f"could not parse acli output:\n{raw[:300]}"
    # acli json shape can vary; normalize to a list of dicts with key/summary/status.
    items = data if isinstance(data, list) else data.get("issues", data.get("workItems", []))
    tickets = []
    for it in items:
        f = it.get("fields", it)
        status = f.get("status")
        status = status.get("name") if isinstance(status, dict) else status
        desc = adf_to_text(f.get("description") or "").strip()
        tickets.append({
            "key": it.get("key", f.get("key", "?")),
            "summary": f.get("summary", ""),
            "status": status or "?",
            "description": desc[:2000],  # cap to bound token size
        })
    return tickets, ""


# ---- Reconcile --------------------------------------------------------------
def dirty_summary(d: dict) -> str:
    bits = []
    if d["changed"]:
        bits.append(f"{d['changed']} changed")
    if d["untracked"]:
        bits.append(f"{d['untracked']} untracked")
    if d["stashes"]:
        bits.append(f"{d['stashes']} stashed")
    return ", ".join(bits)


def reconcile(notes, commits, branches, prs, dirty, tickets):
    # keys seen anywhere
    keys = set()
    for t in tickets:
        keys.add(t["key"])
    for c in commits:
        keys.update(c["tickets"])
    for b in branches:
        keys.update(b["tickets"])
    for d in dirty:
        keys.update(d["tickets"])
    for n in notes.values():
        keys.update(extract_tickets(n["text"]))
    # PRs only ENRICH tickets already surfaced above — they don't spawn new digest
    # lines (a recent merged PR for a long-closed ticket isn't today's concern).

    by_status = {t["key"]: t["status"] for t in tickets}
    by_summary = {t["key"]: t["summary"] for t in tickets}
    per_ticket = []
    for key in sorted(keys):
        t_commits = [c for c in commits if key in c["tickets"]]
        t_branches = [b for b in branches if key in b["tickets"]]
        t_prs = [p for p in prs if key in p["tickets"]]
        t_dirty = [d for d in dirty if key in d["tickets"]]
        flags = []
        status = by_status.get(key)
        if status is None:
            flags.append("mentioned in work but NOT in your open assigned tickets (closed? unassigned?)")
        merged = [p for p in t_prs if p.get("state") == "merged"]
        if merged and status and status.lower() not in ("done", "closed"):
            flags.append(f"PR merged but Jira still '{status}' → propose transition to Done")
        if (t_commits or t_branches) and status and status.lower() in ("to do", "open", "backlog"):
            flags.append(f"active work (branch/commits) but Jira still '{status}' → propose transition to In Progress")
        per_ticket.append({"key": key, "status": status, "summary": by_summary.get(key, ""),
                           "commits": t_commits, "branches": t_branches, "prs": t_prs,
                           "dirty": t_dirty, "flags": flags})
    return per_ticket


# ---- Render -----------------------------------------------------------------
def render(today, per_ticket, commits, prs, dirty, jira_err):
    L = [f"{DIGEST_MARKER} {today.isoformat()})", ""]
    if jira_err:
        L += [f"> ⚠️ Jira: {jira_err}", ""]
    proposals = []
    L.append("### Per-ticket status")
    if not per_ticket:
        L.append("- _No tickets or activity found in the window._")
    for t in per_ticket:
        title = f" — {t['summary']}" if t.get("summary") else ""
        L.append(f"- **[{t['key']}]({JIRA_BASE}{t['key']})** — {t['status'] or 'not in open tickets'}{title}")
        for b in t["branches"]:
            L.append(f"    - 🌿 branch `{b['branch']}` ({b['repo']})")
        for c in t["commits"]:
            L.append(f"    - commit `{c['sha']}` ({c['repo']}): {c['subj']}")
        for p in t["prs"]:
            link = f"[{p['title']}]({p['url']})" if p.get("url") else p["title"]
            L.append(f"    - PR [{p['state']}]: {link}")
        for d in t["dirty"]:
            L.append(f"    - 🔧 uncommitted in {d['repo']}: {dirty_summary(d)}")
        for fl in t["flags"]:
            L.append(f"    - 🔸 {fl}")
            if "propose transition" in fl:
                proposals.append((t["key"], fl))
    unlinked = [c for c in commits if not c["tickets"]]
    if unlinked:
        L += ["", "### Other recent commits (no ticket ref)"]
        for c in unlinked[:15]:
            L.append(f"- `{c['sha']}` ({c['repo']}): {c['subj']}")
    L += ["", "### Proposed Jira changes (review — nothing applied)"]
    if proposals:
        for key, fl in proposals:
            target = fl.split("propose transition to ", 1)[-1] if "propose transition to " in fl else "?"
            L.append(f"- **[{key}]({JIRA_BASE}{key})**: {fl}")
            L.append(f"    - `acli jira workitem transition --key {key} --status \"{target}\"`  "
                     f"(run `acli jira workitem transition --key {key}` first to see exact status names)")
    else:
        L.append("- _None inferred._")
    L += ["", "### Suggested next steps"]
    L.append("- Review flags above and confirm any Jira transitions.")
    L.append("- Fill each ticket's `Next:` in the note based on the activity shown.")
    return "\n".join(L), proposals


TEMPLATE = VAULT / CFG["template_path"]


def ensure_note(today) -> Path:
    """Create today's note from the template (if missing) so --write-note has a target."""
    p = note_path(today)
    if p.exists():
        return p
    p.parent.mkdir(parents=True, exist_ok=True)
    tmpl = TEMPLATE.read_text() if TEMPLATE.exists() else "# Daily Notes `{{date}}`\n"
    p.write_text(tmpl.replace("{{date}}", today.isoformat()))
    print(f"🆕 Created today's note from template: {p}")
    return p


def _toml_val(v):
    if isinstance(v, list):
        return "[" + ", ".join(f'"{x}"' for x in v) + "]"
    return f'"{v}"'


def write_config_toml():
    """Write a starter config.toml from detected values (won't clobber an existing one)."""
    det = _config.detect()
    merged = {**{k: _config.DEFAULTS[k] for k in
                 ("ticket_prefix", "repo_roots", "vault_path", "daily_folder",
                  "daily_note_format", "template_path", "author_hints", "jira_site",
                  "pr_owners", "schedule_morning", "schedule_wrap")}, **det}
    lines = ["# daily-digest config — generated by --init. Edit freely; omitted keys are",
             "# auto-detected then defaulted. Re-run `--detect` to see detection.", ""]
    for k in ("ticket_prefix", "repo_roots", "vault_path", "daily_folder",
              "daily_note_format", "template_path", "author_hints", "jira_site",
              "pr_owners", "schedule_morning", "schedule_wrap"):
        lines.append(f"{k} = {_toml_val(merged.get(k, _config.DEFAULTS[k]))}")
    body = "\n".join(lines) + "\n"
    dest = _config._config_path()
    if dest.exists():
        print(f"⚠️  {dest} already exists — not overwriting. Proposed content:\n\n{body}")
    else:
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(body)
        print(f"✅ wrote {dest}")


def gen_launchd():
    """Generate the two launchd plists + a runnable path summary from config."""
    import getpass
    repo = Path(CFG["repo_dir"])
    user = getpass.getuser()
    outdir = repo / "launchd"
    outdir.mkdir(exist_ok=True)
    made = []
    for mode, when in (("morning", CFG["schedule_morning"]), ("wrap", CFG["schedule_wrap"])):
        hh, mm = (int(x) for x in when.split(":"))
        label = f"com.{user}.daily-digest-{mode}"
        cals = "\n".join(
            f"        <dict><key>Weekday</key><integer>{d}</integer>"
            f"<key>Hour</key><integer>{hh}</integer>"
            f"<key>Minute</key><integer>{mm}</integer></dict>" for d in range(1, 6))
        plist = f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>{label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>{repo}/run.sh</string>
        <string>{mode}</string>
    </array>
    <key>StartCalendarInterval</key>
    <array>
{cals}
    </array>
    <key>StandardOutPath</key>
    <string>{repo}/logs/launchd-{mode}.out</string>
    <key>StandardErrorPath</key>
    <string>{repo}/logs/launchd-{mode}.err</string>
</dict>
</plist>
'''
        dest = outdir / f"{label}.plist"
        dest.write_text(plist)
        made.append(str(dest))
    print("✅ generated:\n  " + "\n  ".join(made))
    print(f"Load with:\n  cp {outdir}/*.plist ~/Library/LaunchAgents/ && \\\n"
          f"  launchctl load -w ~/Library/LaunchAgents/com.{user}.daily-digest-*.plist")


def gen_settings():
    """Write .claude/settings.local.json with Edit/Write scoped to THIS machine's vault +
    repo. Kept out of git (paths are machine-specific); the committed settings.json holds
    only path-independent allows. Claude merges both allow-lists."""
    vault = CFG["vault_path"] or str(VAULT)
    repo = CFG["repo_dir"]
    data = {"permissions": {"allow": [
        f"Edit({vault}/**)", f"Write({vault}/**)",
        f"Edit({repo}/**)", f"Write({repo}/**)",
    ]}}
    dest = Path(repo) / ".claude" / "settings.local.json"
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(data, indent=2) + "\n")
    print(f"✅ wrote {dest}\n   (Edit/Write scoped to vault + repo; merges with committed settings.json)")


def write_note(today, block):
    p = note_path(today)
    if not p.exists():
        print(f"⚠️  Today's note does not exist yet: {p}\n    Skipping --write-note.")
        return
    text = p.read_text()
    # Replace an existing digest block (from marker to next '---' or EOF) if present.
    if DIGEST_MARKER in text:
        text = re.split(r"\n" + re.escape(DIGEST_MARKER), text)[0].rstrip()
    p.write_text(text.rstrip() + "\n\n" + block + "\n")
    print(f"✅ Digest written into {p}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write-note", action="store_true", help="append digest into today's note")
    ap.add_argument("--ensure-note", action="store_true", help="create today's note from template if missing")
    ap.add_argument("--json", action="store_true", help="emit structured data for a Claude command to reason over")
    ap.add_argument("--detect", action="store_true", help="print auto-detected config values as JSON and exit")
    ap.add_argument("--init", action="store_true", help="write a starter config.toml from detected values and exit")
    ap.add_argument("--gen-launchd", action="store_true", help="generate launchd plists from config and exit")
    ap.add_argument("--gen-settings", action="store_true", help="write machine-scoped .claude/settings.local.json and exit")
    ap.add_argument("--note-uri", action="store_true", help="print the obsidian:// URI for today's (or --date) note and exit")
    ap.add_argument("--notify-enabled", action="store_true", help="print 1 if desktop notifications are enabled in config, else 0, and exit")
    ap.add_argument("--days", type=int, default=2)
    ap.add_argument("--date", help="YYYY-MM-DD (default today)")
    args = ap.parse_args()

    if args.detect:
        json.dump({"detected": _config.detect(), "effective": CFG}, sys.stdout, indent=2)
        print()
        return
    if args.init:
        write_config_toml()
        return
    if args.gen_launchd:
        gen_launchd()
        return
    if args.gen_settings:
        gen_settings()
        return
    if args.notify_enabled:
        print("1" if CFG.get("notify", True) else "0")
        return

    today = dt.date.fromisoformat(args.date) if args.date else dt.date.today()
    if args.note_uri:
        # Absolute-path form works without knowing the vault name. Fast: no gathering.
        import urllib.parse
        print("obsidian://open?path=" + urllib.parse.quote(str(note_path(today).resolve()), safe=""))
        return
    if args.ensure_note:
        ensure_note(today)
    notes = gather_notes(today)
    commits, branches, dirty = gather_git(args.days)
    tickets, jira_err = gather_tickets()
    # PR lookup is keyed on open tickets (+ branch/commit refs) so merged PRs for
    # still-open tickets are found regardless of how long ago they merged.
    key_set = {t["key"] for t in tickets}
    for c in commits:
        key_set.update(c["tickets"])
    for b in branches:
        key_set.update(b["tickets"])
    prs = gather_prs(args.days, sorted(key_set))
    per_ticket = reconcile(notes, commits, branches, prs, dirty, tickets)
    block, proposals = render(today, per_ticket, commits, prs, dirty, jira_err)

    if args.json:
        note_paths = {k: str(v["path"]) for k, v in notes.items()}
        json.dump({
            "date": today.isoformat(),
            "config": {
                "ticket_prefix": PREFIX,
                "repo_roots": [str(p) for p in REPO_ROOTS],
                "vault_path": str(VAULT),
                "daily_folder": CFG["daily_folder"],
                "daily_note_format": CFG["daily_note_format"],
                "template_path": str(TEMPLATE),
                "config_source": CFG["config_source"],
            },
            "note_paths": note_paths,
            "jira_base": JIRA_BASE,
            "jira_error": jira_err,
            "open_tickets": tickets,
            "per_ticket": per_ticket,
            "unlinked_commits": [c for c in commits if not c["tickets"]],
            "proposals": [{"key": k, "reason": fl} for k, fl in proposals],
            "notes": {k: v["text"] for k, v in notes.items()},
        }, sys.stdout, indent=2)
        print()
    else:
        print(block)
        print(f"\n--- gathered: {len(commits)} commits, {len(branches)} active branches, "
              f"{len(prs)} PRs, {len(dirty)} dirty trees, {len(tickets)} open tickets ---", file=sys.stderr)
    if args.write_note:
        write_note(today, block)


if __name__ == "__main__":
    main()
