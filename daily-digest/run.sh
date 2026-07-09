#!/bin/zsh
# Wrapper invoked by launchd. Usage: run.sh morning | wrap
# Sets a login-like PATH (launchd's env is minimal) and runs the Claude command
# headlessly, logging output for later review.
set -u
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

MODE="${1:-morning}"
REPO="${0:A:h}"   # absolute dir of this script — works wherever the repo lives
LOGDIR="$REPO/logs"
mkdir -p "$LOGDIR"
LOG="$LOGDIR/$MODE-$(date +%Y-%m-%d).log"

cd "$REPO" || { echo "cannot cd to $REPO" >&2; exit 1; }

{
  echo "===== $MODE run @ $(date) ====="
  # Headless Claude. Permissions come from this repo's .claude/settings.json allowlist.
  # If you prefer not to maintain an allowlist, swap in --dangerously-skip-permissions.
  claude -p "/daily-digest $MODE" --permission-mode acceptEdits
  echo "===== done @ $(date) ====="
} >> "$LOG" 2>&1
