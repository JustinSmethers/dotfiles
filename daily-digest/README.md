# daily-digest

Automated daily digest of your Jira ticket progress, reconciled from three sources:

1. **Obsidian daily note** — plan, per-ticket log/recap/next, carryover
2. **Local git + GitHub PRs** — commits (incl. unpushed), branch names, PR state, and
   uncommitted/stashed work
3. **Jira** — open assigned tickets, status, and descriptions (requirements)

It runs as one Claude command with three modes, scheduled Mon–Fri via `launchd`:

- **`setup`** — one-time onboarding: auto-detects your config, generates the jobs, preflights.
- **`morning`** (6:00am) — creates today's note; writes a prioritized plan, a linked digest,
  and a **"What Claude can pick up"** feasibility assessment. Read-only on Jira.
- **`wrap`** (4:07pm) — fills each ticket's note section from the day's work, flags 🔧
  uncommitted loose ends, and **proposes** Jira updates as a reviewable `apply-jira.sh`
  (nothing applied automatically).

## Architecture

```
launchd → run.sh <mode> → claude -p "/daily-digest <mode>"
                              └─ runs daily_digest.py (deterministic gather/dedup/link)
                              └─ Claude reasons over it + writes the note
```

The **script is the reliable data engine**; the **Claude command is the reasoning + writing**.
Everything is config-driven, so it drops into a dotfiles repo and works for any person/job.

## Quick start (new machine)

```sh
git clone <this repo> ~/GitHub/daily-digest && cd ~/GitHub/daily-digest
claude "/daily-digest setup"
```

`setup` auto-detects ticket prefix, repo roots, Obsidian vault + note format, Jira site,
your git/gh identity, and PR org from what's on the machine; confirms anything ambiguous;
writes `config.toml`; generates the launchd plists; and reports what still needs doing.

## Configuration

`config.toml` is local-only and ignored by git. It is resolved from
`$DAILY_DIGEST_CONFIG`, else `~/.config/daily-digest/config.toml`, else `./config.toml`.
Every key is optional — omitted values are auto-detected, then defaulted. Start from
`config.toml.example` if you want an explicit file.

```toml
ticket_prefix = "PROJ"
repo_roots    = ["~/GitHub"]
# auto-detected if omitted: vault_path, daily_folder, daily_note_format, template_path,
# author_hints, jira_site, pr_owners, jql, schedule_morning, schedule_wrap
```

- `python3 daily_digest.py --detect` — show what auto-detection finds vs. what resolves.
- `python3 daily_digest.py --init` — write a starter `config.toml` from detection.
- `python3 daily_digest.py --gen-launchd` — (re)generate the plists from config.

Repo-root detection scans common source folders such as `~/GitHub`, `~/Code`, `~/src`,
and one grouping level below them. Set `DAILY_DIGEST_REPO_ROOTS` to an `:`-separated
list to override detection.

## Prerequisites

### Required
- **`python3` 3.11+** — the engine. 3.11+ matters: `config.toml` is read via stdlib
  `tomllib`; on older Python the file is silently ignored (detection + defaults only).
- **`git`** — reads commits, branches, and stashes across your repos.
- **`claude` CLI** on PATH — runs the `/daily-digest` command headless.
- **`acli`** (Atlassian CLI) — reads Jira. Auth once; for unattended/cron use prefer an
  **API token** over OAuth: `acli jira auth login --site <you>.atlassian.net --email <you> --token`.
- **A daily-notes folder** — just a directory of markdown files. Obsidian is the intended
  editor, but the pipeline only needs the folder; it creates each day's note itself.

### Optional (everything degrades gracefully)
- **`gh` CLI** — adds GitHub PR state. Without it, PR info is simply empty; git + Jira
  still work. SAML orgs need `gh auth refresh -h github.com` (approve the org once);
  IP-allowlisted orgs need VPN.
- **Obsidian Daily Notes core plugin** — used *only* by auto-detection to discover your
  note folder/format/template from `.obsidian/daily-notes.json`. Not needed at runtime —
  set `daily_folder`, `daily_note_format`, `template_path` in `config.toml` instead.
- **A daily-note template** (`Templates/Daily Note.md`) — gives the note its
  `Plan / per-ticket / Carryover` structure that the command fills. Missing → the script
  creates a minimal dated note and still writes the Plan + Digest, just with less scaffolding.
- **Obsidian itself** — the intended viewer, but the pipeline reads/writes plain markdown,
  so any folder works.

## Manual setup steps `setup` can't do for you

1. **Permissions** — headless `claude -p` needs to run the pipeline's tools without
   prompting. This splits into two files that Claude merges:
   - **`.claude/settings.json`** (committed, portable — no machine paths). Path-independent
     allows only. Note the script shells out to git/acli/gh itself, so `python3
     daily_digest.py` already covers those — no per-command git/gh entries needed. Jira
     *write* commands (transition/comment) are intentionally **absent** so an automated run
     can never mutate Jira without a prompt (wrap only writes `apply-jira.sh`):
     ```json
     { "permissions": { "allow": [
       "Bash(python3 daily_digest.py:*)", "Bash(acli jira auth status)",
       "Bash(gh auth status)", "Bash(gh api:*)", "Read"
     ] } }
     ```
   - **`.claude/settings.local.json`** (gitignored, machine-specific) — `Edit`/`Write`
     scoped to your vault + repo so writes can't escape those trees. Generate it with
     `python3 daily_digest.py --gen-settings` (the `setup` mode does this for you).

   (Or skip both and use `--dangerously-skip-permissions` in `run.sh` — simpler, broader,
   less safe.) Also run `claude` once in this dir and accept the trust dialog, or the
   allowlists are ignored.
2. **Load the jobs** (labels are `com.<username>.daily-digest-*`):
   ```sh
   cp launchd/*.plist ~/Library/LaunchAgents/
   launchctl load -w ~/Library/LaunchAgents/com.$(whoami).daily-digest-*.plist
   ```
   Test now: `launchctl start com.$(whoami).daily-digest-morning`.

> **Scheduling notes:**
> - Times (`schedule_morning`/`schedule_wrap`) are **local wall-clock time** — launchd
>   uses the Mac's current system timezone. They follow DST automatically, and if you
>   travel, the job fires at that time in the new local timezone (no timezone is pinned).
> - launchd runs missed jobs when the Mac wakes, so a digest still fires if you slept
>   through the scheduled time. It does **not** run while fully shut down.

## Manual use

```sh
python3 daily_digest.py --days 3                    # preview digest to stdout
python3 daily_digest.py --ensure-note --write-note  # create today's note + write digest
python3 daily_digest.py --json                      # structured output the command consumes
./run.sh morning                                    # full headless run, logged to logs/
```

## Applying Jira changes

`wrap` writes `apply-jira.sh` with the proposed transitions/comments, each commented with
why. Review it, then `bash apply-jira.sh`. Set `AUTO_APPLY=1` to let `wrap` apply them itself.

## Files

- `daily_digest.py` — gatherer/reconciler + `--detect`/`--init`/`--gen-launchd`
- `config.py` — config loader + auto-detection
- `config.toml.example` — portable starter config
- `config.toml` — your local settings, ignored by git
- `.claude/commands/daily-digest.md` — the `/daily-digest` command (setup | morning | wrap)
- `.claude/settings.json` — committed, portable permission allowlist
- `.claude/settings.local.json` — generated per machine (scoped Edit/Write), gitignored
- `run.sh` — launchd wrapper (sets PATH, logs)
- `launchd/*.plist` — generated schedules (gitignored)
- `logs/` — per-run output
