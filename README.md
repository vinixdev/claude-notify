# claude-notify

Native desktop notification (+ sound) when **Claude Code** finishes a task or
needs your input. Cross-platform: **Linux**, **macOS**, **Windows / WSL**.

Two Claude Code hooks drive it:

| Hook | Fires when |
|------|------------|
| `Notification` | Claude is waiting for your input or permission |
| `Stop` | Claude finished responding (task done) |

A single script (`hooks/notify.sh`) reads the hook's JSON payload on stdin and
pops a native notification for your OS.

## Install (as a plugin)

From inside Claude Code:

```
/plugin marketplace add /home/xinix/Desktop/projects/claude-notify
/plugin install claude-notify@claude-notify-marketplace
```

Or, once pushed to GitHub:

```
/plugin marketplace add <your-user>/claude-notify
/plugin install claude-notify@claude-notify-marketplace
```

Claude Code asks you to approve the new hook commands the first time — accept.
Restart the session (or run `/hooks`) so they load.

## Install (manual, no plugin)

Copy the script and wire it into `~/.claude/settings.json`:

```jsonc
{
  "hooks": {
    "Notification": [
      { "hooks": [ { "type": "command", "command": "/ABS/PATH/notify.sh" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "/ABS/PATH/notify.sh" } ] }
    ]
  }
}
```

`chmod +x notify.sh` first.

## Dependencies per OS

- **Linux** — `notify-send` (`sudo apt install libnotify-bin`). Sound is
  optional (`canberra-gtk-play` or `paplay`, usually already present).
- **macOS** — nothing; uses built-in `osascript`.
- **Windows** — nicer toasts with `Install-Module BurntToast`; otherwise falls
  back to a message box. WSL bounces the toast to Windows automatically.

## Test it

```bash
echo '{"hook_event_name":"Stop","message":"","cwd":"'"$PWD"'"}' | ./hooks/notify.sh
```

A desktop notification should appear.

## Customize

Edit `hooks/notify.sh` — change titles/bodies in the `case "$event"` block, or
swap the sound. Want a phone ping (Telegram / ntfy / Pushover) instead of a
local toast? Add a `curl` call in the OS block.
