#!/usr/bin/env python3
"""
Config loader + auto-detection for daily-digest.

Resolution order for each setting:
  1. config.toml  (env DAILY_DIGEST_CONFIG, else ~/.config/daily-digest/config.toml,
     else ./config.toml next to this file)
  2. auto-detected value (git/gh/acli/Obsidian)
  3. built-in default

Run `python3 daily_digest.py --detect` to see what auto-detection finds, or
`--init` to write a starter config.toml (detected values + comments).
"""
import os
import re
import subprocess
from pathlib import Path

try:
    import tomllib  # py3.11+
except ModuleNotFoundError:  # pragma: no cover
    tomllib = None

HERE = Path(__file__).resolve().parent


def _run(cmd, cwd=None) -> str:
    try:
        r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=30)
        return r.stdout.strip()
    except Exception:
        return ""


# ---- moment.js (Obsidian) → strftime, for the daily-note path format --------
_MOMENT = [("YYYY", "%Y"), ("MMMM", "%B"), ("MMM", "%b"), ("MM", "%m"),
           ("DD", "%d"), ("dddd", "%A"), ("ddd", "%a")]


def moment_to_strftime(fmt: str) -> str:
    for a, b in _MOMENT:
        fmt = fmt.replace(a, b)
    return fmt


# ---- detection --------------------------------------------------------------
def _find_vault() -> dict:
    """Locate an Obsidian vault and read its daily-notes settings."""
    roots = [Path.home() / "Library/CloudStorage", Path.home()]
    for root in roots:
        if not root.is_dir():
            continue
        for cfg in root.glob("**/.obsidian/daily-notes.json"):
            vault = cfg.parent.parent
            try:
                import json
                dn = json.loads(cfg.read_text() or "{}")
            except Exception:
                dn = {}
            return {
                "vault_path": str(vault),
                "daily_folder": dn.get("folder", "Daily Notes"),
                "daily_note_format": moment_to_strftime(dn.get("format", "YYYY-MM-DD")),
                "template_path": (dn.get("template") or "Templates/Daily Note") + ".md",
            }
    return {}


def _scan_repos(candidate_roots) -> dict:
    """Scan candidate roots for repos; infer ticket prefix (from branch names) and
    PR owners (from remotes). Returns roots that actually contain git repos."""
    prefix_counts, owners, roots_with_repos = {}, set(), []
    key_re = re.compile(r"\b([A-Z][A-Z0-9]+)-\d+")
    for root in candidate_roots:
        root = Path(root)
        if not root.is_dir():
            continue
        found = False
        for child in sorted(root.iterdir()):
            if not (child / ".git").exists():
                continue
            found = True
            branch = _run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=child)
            for m in key_re.finditer(branch + " " + child.name):
                prefix_counts[m.group(1)] = prefix_counts.get(m.group(1), 0) + 1
            remote = _run(["git", "remote", "get-url", "origin"], cwd=child)
            mo = re.search(r"[:/]([^/]+)/[^/]+?(?:\.git)?$", remote)
            if mo and ("github.com" in remote or "@" in remote):
                owners.add(mo.group(1))
        if found:
            roots_with_repos.append(str(root))
    prefix = max(prefix_counts, key=prefix_counts.get) if prefix_counts else ""
    return {"repo_roots": roots_with_repos, "ticket_prefix": prefix,
            "pr_owners": sorted(o for o in owners if o and o != "github.com")}


def _candidate_repo_roots() -> list[Path]:
    env = os.environ.get("DAILY_DIGEST_REPO_ROOTS")
    if env:
        return [Path(p).expanduser() for p in env.split(os.pathsep) if p]

    bases = [Path.home() / name for name in ("GitHub", "Code", "src", "Projects")]
    roots: list[Path] = []
    for base in bases:
        if not base.is_dir():
            continue
        roots.append(base)
        try:
            for child in sorted(base.iterdir()):
                if child.is_dir():
                    roots.append(child)
        except OSError:
            pass
    return roots


def detect() -> dict:
    """Best-effort auto-detection of every configurable value."""
    d = {}
    # identity
    email = _run(["git", "config", "user.email"])
    login = _run(["gh", "api", "user", "--jq", ".login"])
    hints = sorted({p for p in [email.split("@")[0] if email else "", login] if p})
    if hints:
        d["author_hints"] = hints
    # jira site (acli prints "Site: <host>")
    status = _run(["acli", "jira", "auth", "status"])
    m = re.search(r"Site:\s*(\S+)", status)
    if m:
        d["jira_site"] = m.group(1)
    # obsidian vault + note format
    d.update(_find_vault())
    # repos + ticket prefix + owners
    d.update(_scan_repos(_candidate_repo_roots()))
    return d


# ---- load -------------------------------------------------------------------
DEFAULTS = {
    "ticket_prefix": "TICKET",
    "repo_roots": [str(Path.home() / "GitHub")],
    "vault_path": "",
    "daily_folder": "Daily Notes",
    "daily_note_format": "%Y/%m-%b/%Y-%m-%d",
    "template_path": "Templates/Daily Note.md",
    "author_hints": [],
    "jira_site": "",
    "pr_owners": [],
    "jql": "assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC",
    "repo_dir": str(HERE),
    "schedule_morning": "8:03",
    "schedule_wrap": "16:07",
}


def _config_path() -> Path:
    env = os.environ.get("DAILY_DIGEST_CONFIG")
    if env:
        return Path(env).expanduser()
    xdg = Path.home() / ".config/daily-digest/config.toml"
    if xdg.exists():
        return xdg
    return HERE / "config.toml"


def load() -> dict:
    """Merge file config over auto-detection over defaults; derive computed fields."""
    cfg = dict(DEFAULTS)
    cfg.update({k: v for k, v in detect().items() if v})
    path = _config_path()
    if path.exists() and tomllib:
        with open(path, "rb") as f:
            file_cfg = tomllib.load(f)
        cfg.update({k: v for k, v in file_cfg.items() if v not in ("", [], None)})
    # expand ~ in paths
    cfg["repo_roots"] = [str(Path(p).expanduser()) for p in cfg["repo_roots"]]
    cfg["vault_path"] = str(Path(cfg["vault_path"]).expanduser()) if cfg["vault_path"] else ""
    # computed
    cfg["jira_base"] = f"https://{cfg['jira_site']}/browse/" if cfg["jira_site"] else ""
    cfg["config_source"] = str(path) if path.exists() else "(auto-detected + defaults)"
    return cfg
