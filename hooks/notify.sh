#!/usr/bin/env bash
# claude-notify — desktop notification (+ sound) on Claude Code lifecycle events.
# Wired to the Stop + Notification hooks (see ../.claude-plugin/plugin.json ->
# hooks/hooks.json). Reads the hook JSON payload on stdin and pops a native
# desktop notification on Linux, macOS, or Windows (Git Bash / WSL).

set -euo pipefail

payload="$(cat)"

# --- GUI env: hooks may run without the desktop session vars, so notify-send
# can't reach the notification daemon. Restore sane defaults if missing. -----
uid="$(id -u)"
export DISPLAY="${DISPLAY:-:0}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$uid/bus}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$uid}"

# --- parse the JSON payload (prefer jq, fall back to grep/sed) ------------
# A MISSING key must yield an empty string, never a failure: `grep` exits 1 when
# it matches nothing, and under `set -euo pipefail` that aborted the whole script.
# A `Stop` payload has no `message` field, so `Stop` silently never notified —
# only `Notification` (which carries `message`) survived. Hence the trailing
# `|| true` on both branches.
get() {
  local key="$1"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$payload" | jq -r --arg k "$key" '.[$k] // empty' 2>/dev/null || true
  else
    printf '%s' "$payload" \
      | { grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" || true; } \
      | head -n1 | sed 's/.*:[[:space:]]*"\(.*\)"/\1/' || true
  fi
}

event="$(get hook_event_name)"
message="$(get message)"
cwd="$(get cwd)"
tool="$(get tool_name)"
project="$(basename "${cwd:-$PWD}")"

# --- pick title / body per event -----------------------------------------
case "$event" in
  Notification)
    title="Claude Code — needs you"
    body="${message:-Waiting for your input}"
    ;;
  # Claude asking YOU something. `Notification` only fires for permission
  # prompts / idle, so with permission_mode=auto (the default in the VS Code
  # extension) it never fires — the question arrives as a TOOL call instead.
  PreToolUse)
    title="Claude Code — needs your answer"
    case "$tool" in
      ExitPlanMode) body="Review the plan" ;;
      *)            body="Claude asked you a question" ;;
    esac
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
      # `critical` is STICKY by spec — daemons ignore the expire-timeout for it,
      # which is why the toast used to sit there forever. So keep critical (it's
      # what pierces fullscreen/DND) but close it ourselves: grab the id and
      # dismiss it after the timeout, detached so it outlives this hook process.
      nid="$(notify-send --print-id -a "Claude Code" -u "$urgency" -t "$timeout_ms" \
              "$title" "$body" 2>/dev/null || true)"
      if [ -n "${nid//[^0-9]/}" ] && command -v gdbus >/dev/null 2>&1; then
        setsid bash -c "sleep $(( timeout_ms / 1000 )); \
          gdbus call --session --dest org.freedesktop.Notifications \
            --object-path /org/freedesktop/Notifications \
            --method org.freedesktop.Notifications.CloseNotification ${nid//[^0-9]/}" \
          >/dev/null 2>&1 < /dev/null &
      fi
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
