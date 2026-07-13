---
description: Onboarding, morning briefing, or end-of-day wrap-up of Jira ticket progress
argument-hint: setup | morning | wrap
allowed-tools: Bash(python3:*), Bash(acli:*), Bash(gh:*), Bash(git:*), Read, Edit, Write
---

You are running the **daily digest** pipeline in **`$1`** mode. The heavy lifting
(gathering notes + git + PRs + Jira, deduping, linking tickets) is done by a script.
Your job is the reasoning the script can't do, and writing results into the Obsidian
daily note.

## If `$1` == `setup` — ONBOARD (first-time config for a new person/machine)

Goal: produce a working `config.toml`, generate the launchd jobs, and report what's
left to do. This is the only mode that does NOT run the gather step below.

1. Run `python3 daily_digest.py --detect` and read the JSON: `detected` (raw
   auto-detection) and `effective` (what config currently resolves to).
2. **Reason over `detected` — don't trust it blindly:**
   - `ticket_prefix`: the most common prefix in branch/folder names. Confirm it looks
     like a real project key, not a coincidence.
   - `pr_owners`: detection lists EVERY org across all repos. Narrow it to the org(s)
     that actually own the repos on `ticket_prefix` branches (usually one). Drop
     personal/unrelated orgs.
   - `author_hints`: reduce to the shortest unique substring of the user's identity
     (e.g. a surname) rather than the full noreply email.
   - `repo_roots`, `vault_path`, `daily_note_format`, `jira_site`: sanity-check.
   - If any value is missing or ambiguous, ask the user with ONE `AskUserQuestion`
     (batch the questions). Otherwise proceed.
3. Write `config.toml` (in the repo dir) with the cleaned values. Use `--init` as a
   starting point if helpful, then edit it to the reasoned values.
4. Run `python3 daily_digest.py --gen-launchd` to generate the plists from config, and
   `python3 daily_digest.py --gen-settings` to write `.claude/settings.local.json` with
   Edit/Write scoped to THIS machine's vault + repo (the committed `settings.json` only
   holds path-independent allows; the two merge).
5. **Preflight** — check and report, with the exact fix command for anything not ready:
   - `acli jira auth status` (authed? which site?)
   - `gh auth status` + a probe like `gh api repos/<owner>/<a-repo> --jq .full_name`
     (SSO/VPN reachable?)
   - whether the workspace is trusted (needed for headless runs)
6. Tell the user the remaining manual steps: load the jobs
   (`cp launchd/*.plist ~/Library/LaunchAgents/ && launchctl load -w ...`), and offer to
   run `/daily-digest morning` now as a first live test. Do NOT load launchd yourself.

## Step 1 — gather (morning + wrap only)

Run the gatherer and read its JSON:

```
python3 daily_digest.py --json --ensure-note --days 3
```

This returns: `date`, `open_tickets` (each with `key`, `summary`, `status`,
`description` = the ticket's real requirements), `per_ticket` (each with `status`, `branches`,
`commits`, `prs`, `dirty`, `flags`), `unlinked_commits`, `proposals`, and `notes`
(today + yesterday text). It also returns `config` (effective ticket prefix, repo roots,
vault/note settings, config source) and `note_paths` (today/yesterday absolute paths).
`dirty` = **uncommitted local work** (changed/untracked/stashed counts) tied to that
ticket. Today's note is created from the template if missing.

Use `note_paths.today` as the daily note path. Use `config.ticket_prefix` for all ticket
examples and output; do not assume a specific project key.

## If `$1` == `morning` — LAUNCH THE DAY (read-only on Jira)

Produce a focused plan, don't just dump data.

1. From `per_ticket`, identify what actually needs attention **today**: tickets in
   "In Progress" / "In Review" / "Internal Code Review", anything with a merged PR
   not yet Done, tickets with `dirty` (uncommitted work left hanging), and yesterday's
   unchecked `Plan` items + `Carryover`.
2. Write into today's note:
   - Fill the top **`**Plan:**`** list with 3–5 concrete, prioritized checkboxes
     (e.g. `- [ ] PROJ-341: QA merged change, then move to Done`; replace `PROJ`
     with `config.ticket_prefix`).
   - Append a `## Digest (generated <date>)` section. Use the nested-bullet layout
     (like the `Plan` / `What Claude can pick up` sections), NOT one crammed line:
     a header line per active ticket, then tab-indented sub-bullets. Format:
     ```
     - [PROJ-411](<jira_base>PROJ-411) *short title* — In Progress
         - new model .sql/.yml untracked, 6 files modified
         - Next: finish + commit -> PR
     ```
     Header = linked key + title + status. One fact per sub-bullet (latest signal:
     branch/commit/PR/dirty state), and a final `- Next:` sub-bullet with the action.
     Each sub-bullet still terse (≤ 12 words); split rather than cram.
   - Note any 🔸 flags as things to reconcile.
3. Append a **`## What Claude can pick up (<date>)`** section — an honest self-assessment
   of the planned work (the tickets in your Plan + any active ticket). For each, use its
   `description` from `open_tickets` (the real requirements) AND read the relevant files
   in the local repos under `config.repo_roots`. Prefer repos whose branch name, folder
   name, commits, or PR title mention the ticket key. Then bucket each ticket:

   - **🟢 Ready — I can draft this now**: self-contained, requirements are clear, and the
     code/context needed is in the repo. State concretely *what* you'd produce (e.g.
     "generate the 234 missing doc blocks from the model SQL", "write the incremental
     watermark CTE"). One line each.
   - **🟡 Partial — I can start, but need input**: name the *specific* missing piece that
     blocks finishing (a decision, an example of expected output, which upstream source,
     acceptance-criteria clarification).
   - **🔴 Needs you / blocked**: requires warehouse validation, a human decision, access
     you don't have, or an upstream dependency. Say what.

   Then a short **"What would unlock more"** list: the highest-leverage context/info/access
   that would move 🟡/🔴 items toward 🟢 (e.g. "read access to run dbt against the warehouse
   to validate output", "the Figma/spec for X", "confirm the grain on Y"). Be specific and
   honest — do not claim you can do work you can't verify.
4. Do **not** modify Jira. End with a 3-line summary of the day's priorities.

## If `$1` == `wrap` — WRAP UP & UPDATE TICKETS (propose, don't apply)

1. For each ticket with activity today, fill its section in the daily note:
   `Repo/branch`, `Log` (today's commits, terse), `Recap` (1 line of what changed),
   `Next` (concrete next step). Preserve anything already hand-written.
   - If a ticket has `dirty` (uncommitted work), call it out in `Next` with 🔧, e.g.
     `Next: 🔧 commit 6 untracked in <repo>`. Uncommitted work at wrap-up is a
     loose end — surfacing it is a main point of the EOD run.
2. **Proposed ticket updates.** For each ticket with activity today, draft a concise
   progress note meant to be posted as a Jira comment. Keep it scannable — bullets, not
   prose — using exactly two labeled sections:
   - `Progress:` — 1–4 bullets on what moved today (commits/PRs/reviews/decisions).
   - `Next steps:` — 1–3 bullets on the concrete next actions.
   Each bullet ≤ 12 words, imperative/factual fragments, symbols over words (`->`, `#6206`,
   `merged`). Reference PRs by number. Skip a section only if genuinely empty. Example:
   ```
   Progress:
   - #6206 merged -> deployed to staging
   - Backfill CTE reviewed, 2 nits fixed
   Next steps:
   - QA staging output vs prod
   - Close ticket once verified
   ```
   Write these into the note's `## EOD reconcile` section (below) AND use them as the
   `--body` for the comment in `apply-jira.sh`.
3. Reconcile Jira. For each `proposals` entry and any status mismatch, decide the
   right change (transition, and/or the progress comment from step 2, and/or worklog).
   Exact `acli` syntax (verified — get it right so the generated script actually runs):
   - transition: `acli jira workitem transition --key "<KEY>" --status "Done" --yes`
   - comment: `acli jira workitem comment create --key "<KEY>" --body "..."` (note the
     `create` subcommand — `acli jira workitem comment --key ...` alone is INVALID)
4. **Do not run transitions/comments directly.** Instead write a reviewable
   `apply-jira.sh` in this repo dir containing the exact commands, each preceded by a
   comment explaining why, e.g.:
   ```bash
   # PROJ-341: PR #6149 merged 2026-07-02 -> close out
   acli jira workitem transition --key "PROJ-341" --status "Done" --yes
   acli jira workitem comment create --key "PROJ-341" --body "Progress:
   - #6149 merged -> deployed
   Next steps:
   - QA + close"
   ```
   Also append a `## EOD reconcile (<date>)` checklist to the note listing each
   proposed change so it's visible in Obsidian. Under each ticket's entry there, include
   its `Progress:` / `Next steps:` bullets from step 2.
5. End by telling the user: review `apply-jira.sh`, then run `bash apply-jira.sh` to
   apply. (If they've set `AUTO_APPLY=1` in the environment, run it yourself.)

## Style — write SUPER concise note lines (hard requirement)

The note is scanned, not read. Every line you write into the note must be terse:

- **Prefer nested bullets over crammed lines.** A ticket = a header line (linked key +
  title + status) followed by tab-indented sub-bullets, one fact/action each — rather
  than stuffing status, git state, and next action into one line joined by `;` and `.`.
- **Each bullet ≤ 12 words** (excluding the title). No sub-clauses — if a bullet needs
  a `;` or a second sentence, split it into two sub-bullets.
- **Always link the ticket key and include a short title** so numbers are never bare:
  write `[PROJ-338](<jira_base>PROJ-338) *short title*` — use the configured ticket key,
  `jira_base` + `summary` from the JSON (shorten long summaries to ~4 words). Link PRs too:
  `[#6206](<pr url>)` using the PR `url`.
- Lead with the linked key + title, then a bare action/fact. Drop filler.
- Plan checkboxes = imperative fragments: `- [ ] [PROJ-338](...) *short title*: merge [#6206](...)`,
  `- [ ] [PROJ-341/342](...) *short title*: QA -> Done`.
- Per-ticket `Log`/`Recap`/`Next` = fragments, not sentences: `Next: QA + close`.
- Prefer symbols over words: `->`, `#6206`, `merged`, `open`. No preamble like
  "Today's priorities are…".
- Do NOT restate the same fact in two sections. If it's in Plan, don't re-explain in Digest.

Good: `- [ ] PROJ-341/342: QA merged work -> Done`
Bad:  `- [ ] PROJ-341/342: QA the merged implementation (#6149), then move both to Done`

Your closing chat summary (not written to the note) can be normal prose — keep the
terseness rule for note content only.

## Notes
- If `jira_error` is set, report it and continue with git/notes only.
- If PR data is empty, the gh auth/SSO/VPN state may be stale; local git still works.
