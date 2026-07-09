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

# Fire a macOS notification (clickable — taps open $3). Prefers terminal-notifier;
# falls back to the always-present osascript (not clickable). Uses default icons.
notify() {
  local title="$1" msg="$2" open_url="$3"
  if command -v terminal-notifier >/dev/null 2>&1; then
    terminal-notifier -title "$title" -message "$msg" -open "$open_url" \
      -group "daily-digest-$MODE" >/dev/null 2>&1
  else
    osascript -e "display notification \"${msg//\"/\\\"}\" with title \"${title//\"/\\\"}\"" >/dev/null 2>&1
  fi
}

{
  echo "===== $MODE run @ $(date) ====="
  # Headless Claude. Permissions come from this repo's .claude/settings.json allowlist.
  # If you prefer not to maintain an allowlist, swap in --dangerously-skip-permissions.
  claude -p "/daily-digest $MODE" --permission-mode acceptEdits
  echo "===== done @ $(date) ====="
} >> "$LOG" 2>&1
STATUS=$?

# Notify unless disabled in config (notify = false).
if [ "$(python3 daily_digest.py --notify-enabled 2>/dev/null)" = "1" ]; then
  case "$MODE" in
    wrap) MODE_LABEL="Afternoon" ;;
    *)    MODE_LABEL="Morning" ;;
  esac
  if [ "$STATUS" -eq 0 ]; then
    # Open the Obsidian daily note on success; fall back to the log if the URI lookup fails.
    NOTE_URI="$(python3 daily_digest.py --note-uri 2>/dev/null)"
    notify "$MODE_LABEL Daily Digest Done" "Click to View." "${NOTE_URI:-file://$LOG}"
  else
    notify "$MODE_LABEL Daily Digest Failed" "Exit $STATUS. Click to view log." "file://$LOG"
  fi
fi
