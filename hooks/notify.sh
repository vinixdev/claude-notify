#!/usr/bin/env bash
# claude-notify — desktop notification (+ sound) on Claude Code lifecycle events.
# Wired to the Stop + Notification hooks (see ../.claude-plugin/plugin.json ->
# hooks/hooks.json). Reads the hook JSON payload on stdin and pops a native
# desktop notification on Linux, macOS, or Windows (Git Bash / WSL).

set -euo pipefail

payload="$(cat)"

# --- parse the JSON payload (prefer jq, fall back to grep/sed) ------------
get() {
  local key="$1"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$payload" | jq -r --arg k "$key" '.[$k] // empty'
  else
    printf '%s' "$payload" \
      | grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
      | head -n1 | sed 's/.*:[[:space:]]*"\(.*\)"/\1/'
  fi
}

event="$(get hook_event_name)"
message="$(get message)"
cwd="$(get cwd)"
project="$(basename "${cwd:-$PWD}")"

# --- pick title / body per event -----------------------------------------
case "$event" in
  Notification)
    title="Claude Code — needs you"
    body="${message:-Waiting for your input}"
    ;;
  Stop|SubagentStop)
    title="Claude Code — task done"
    body="${message:-Finished in $project}"
    ;;
  *)
    title="Claude Code"
    body="${message:-$event}"
    ;;
esac
body="[$project] $body"

# Urgency: 'critical' pierces fullscreen + Do-Not-Disturb (many Linux desktops,
# e.g. Cinnamon/GNOME, hide 'normal' notifications while a fullscreen window —
# VLC, a game, a video — is focused). Override with CLAUDE_NOTIFY_URGENCY=normal
# if the sticky critical toast is too much during active use.
urgency="${CLAUDE_NOTIFY_URGENCY:-critical}"
timeout_ms="${CLAUDE_NOTIFY_TIMEOUT:-8000}"

# --- fire the notification per OS ----------------------------------------
os="$(uname -s 2>/dev/null || echo unknown)"

case "$os" in
  Linux*)
    # WSL? bounce a Windows toast instead of the (headless) Linux one.
    if grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; then
      powershell.exe -NoProfile -Command \
        "New-BurntToastNotification -Text '$title','$body'" 2>/dev/null \
        || powershell.exe -NoProfile -Command \
        "[void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms'); \
         [System.Windows.Forms.MessageBox]::Show('$body','$title')" 2>/dev/null || true
    else
      notify-send -a "Claude Code" -u "$urgency" -t "$timeout_ms" "$title" "$body" 2>/dev/null || true
      # sound (first tool that exists wins)
      { command -v canberra-gtk-play >/dev/null 2>&1 && canberra-gtk-play -i message; } \
        || { command -v paplay >/dev/null 2>&1 && \
             paplay /usr/share/sounds/freedesktop/stereo/complete.oga; } \
        || true
    fi
    ;;
  Darwin*)
    osascript -e "display notification \"$body\" with title \"$title\" sound name \"Glass\"" 2>/dev/null || true
    ;;
  MINGW*|MSYS*|CYGWIN*)
    powershell.exe -NoProfile -Command \
      "New-BurntToastNotification -Text '$title','$body'" 2>/dev/null \
      || powershell.exe -NoProfile -Command \
      "[void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms'); \
       [System.Windows.Forms.MessageBox]::Show('$body','$title')" 2>/dev/null || true
    ;;
esac

exit 0
