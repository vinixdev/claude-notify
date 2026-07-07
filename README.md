# claude-notify

> Native desktop notification (**+ sound**) when [Claude Code](https://docs.claude.com/en/docs/claude-code)
> finishes a task or needs your input.

No more staring at the terminal waiting for a long run to finish, or missing a
permission prompt. When Claude is **done** — or **waiting for you** — your OS
pops a notification.

Cross-platform: **Linux** · **macOS** · **Windows / WSL**.

---

## How it works

Claude Code fires [hooks](https://docs.claude.com/en/docs/claude-code/hooks) on
lifecycle events. This plugin binds two of them to one script:

| Hook | Fires when | Notification |
|------|------------|--------------|
| `Notification` | Claude is waiting for your input or permission | **needs you** |
| `Stop` | Claude finished responding (task done) | **task done** |

The script (`hooks/notify.sh`) reads the hook's JSON payload on stdin, picks a
title/body, and calls your OS's native notifier. Zero runtime deps beyond the
system notify tool.

---

## Install

### Option A — as a plugin (recommended)

From inside Claude Code, add this repo as a marketplace and install:

```
/plugin marketplace add vinixdev/claude-notify
/plugin install claude-notify@claude-notify-marketplace
```

Claude Code shows the new hook commands and asks you to approve them — accept.
Then restart the session (or run `/hooks`) so they load. Done.

To update later:

```
/plugin marketplace update claude-notify-marketplace
```

### Option B — manual (no plugin)

Clone the repo and wire the script into your **user** settings
(`~/.claude/settings.json`):

```bash
git clone https://github.com/vinixdev/claude-notify.git ~/.claude/claude-notify
chmod +x ~/.claude/claude-notify/hooks/notify.sh
```

```jsonc
// ~/.claude/settings.json
{
  "hooks": {
    "Notification": [
      { "hooks": [ { "type": "command",
        "command": "/home/YOU/.claude/claude-notify/hooks/notify.sh" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command",
        "command": "/home/YOU/.claude/claude-notify/hooks/notify.sh" } ] }
    ]
  }
}
```

Use an **absolute** path (hooks don't expand `~`). Restart Claude Code.

> **Don't run both options at once** — you'll get two notifications per event.

---

## Setup — OS dependencies

The script auto-detects your OS. Install the matching notifier:

| OS | Needs | Install |
|----|-------|---------|
| **Linux** | `notify-send` | `sudo apt install libnotify-bin` (Debian/Mint/Ubuntu) · `sudo dnf install libnotify` (Fedora) |
| **Linux sound** *(optional)* | `canberra-gtk-play` or `paplay` | usually preinstalled with the desktop |
| **macOS** | nothing | built-in `osascript` |
| **Windows** | nicer toasts via BurntToast | `Install-Module BurntToast` in PowerShell (else falls back to a message box) |
| **WSL** | — | bounces the toast to Windows automatically |

`jq` is used if present (cleaner JSON parse) but **not required** — falls back to
`grep`/`sed`.

### Verify

```bash
echo '{"hook_event_name":"Stop","message":"","cwd":"'"$PWD"'"}' \
  | ~/.claude/claude-notify/hooks/notify.sh
```

A desktop notification should appear. If it doesn't, see **Troubleshooting**.

---

## Configuration

### Which events notify

Edit `hooks/hooks.json` (plugin) or your `settings.json` (manual). Add or remove
event keys. Useful extras:

```jsonc
{
  "SubagentStop": [                       // ping when a subagent finishes too
    { "hooks": [ { "type": "command",
      "command": "${CLAUDE_PLUGIN_ROOT}/hooks/notify.sh" } ] }
  ]
}
```

Full event list: `Notification`, `Stop`, `SubagentStop`, `PreToolUse`,
`PostToolUse`, `UserPromptSubmit`, `SessionStart`, `SessionEnd`. The script
already handles `SubagentStop`; other events fall through to a generic title.

### Fullscreen / Do Not Disturb (Linux)

Many Linux desktops (Cinnamon, GNOME, …) **hide `normal` notifications while a
fullscreen window is focused** — watching a video in VLC, a game, etc. So by
default this plugin sends **`critical`** urgency, which pierces fullscreen and
Do-Not-Disturb. Tune it with env vars:

| Env var | Default | Effect |
|---------|---------|--------|
| `CLAUDE_NOTIFY_URGENCY` | `critical` | `normal` = quieter but hidden under fullscreen; `low` = subtle |
| `CLAUDE_NOTIFY_TIMEOUT` | `8000` | toast lifetime in ms (note: some daemons keep `critical` sticky until dismissed) |

Set them in your shell profile (`~/.bashrc`) so hooks inherit them:

```bash
export CLAUDE_NOTIFY_URGENCY=normal   # e.g. if sticky critical toasts annoy you
```

Still nothing over fullscreen? Check your desktop's notification settings — e.g.
Cinnamon → *Notifications* → allow during fullscreen / disable Do Not Disturb.

### Payload fields available to the script

`notify.sh` reads these from the stdin JSON:

| Field | Meaning |
|-------|---------|
| `hook_event_name` | which event fired |
| `message` | event message (e.g. the permission prompt text) |
| `cwd` | project directory (shown as `[project-name]`) |
| `session_id` | current session id |

---

## Customization

All in `hooks/notify.sh`:

- **Titles / bodies** — edit the `case "$event"` block:
  ```bash
  Stop|SubagentStop)
    title="✅ Claude done"
    body="${message:-Finished in $project}"
    ;;
  ```
- **Sound (Linux)** — swap the `.oga` path, or add your own:
  ```bash
  paplay ~/sounds/ding.oga
  ```
- **Sound (macOS)** — change `sound name "Glass"` to any of `Ping`, `Pop`,
  `Hero`, …
- **Phone / remote ping** — instead of a local toast, `curl` a push service.
  Drop one of these into the OS block:
  ```bash
  # ntfy.sh (free, no account)
  curl -s -d "$body" ntfy.sh/your-private-topic >/dev/null
  # Telegram bot
  curl -s "https://api.telegram.org/bot<TOKEN>/sendMessage" \
    --data-urlencode "chat_id=<CHAT_ID>" --data-urlencode "text=$title: $body" >/dev/null
  ```

After editing, no rebuild needed — the next hook run uses the new script.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| No notification at all | Run the **Verify** command above. If nothing pops, `notify-send` isn't installed or your desktop blocks it. |
| `Failed to play sound: Sound disabled` | System sound is muted — visual toast still works. Not a plugin bug. |
| Toast but no `[project]` name | `jq` missing **and** payload had unusual spacing; install `jq` for reliable parsing. |
| Hooks didn't load | Restart Claude Code, or `/hooks` → confirm `Stop` + `Notification` are listed and approved. |
| Two notifications per event | You have both the plugin **and** manual `settings.json` hooks — keep one. |

---

## Repo layout

```
claude-notify/
├── .claude-plugin/
│   ├── plugin.json        # plugin manifest → points to hooks/hooks.json
│   └── marketplace.json   # lets `/plugin marketplace add` find it
├── hooks/
│   ├── hooks.json         # binds Stop + Notification → notify.sh
│   └── notify.sh          # the cross-platform notifier
└── README.md
```

## License

MIT — do what you want.
