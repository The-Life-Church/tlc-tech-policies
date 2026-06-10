# Custom Status Line for Claude Code

The TLC status line for Claude Code — a color-coded one-liner showing your model, context usage, and how much of your daily/weekly rate limit you've burned, plus the project and git branch you're in.

Example:

```
Opus 4.8 42% | day: 31% | week: 12% | tlc-wall-boxes | main
```

## What It Shows

| Section | Color | Description |
|---------|-------|-------------|
| **Model** | Cyan | Shortened model name (e.g., "Opus 4.8" instead of "Claude Opus 4.8") |
| **Context %** | Yellow / Red | How full the context window is. Turns red (with a `!!` tag) above 80% or past 200k tokens |
| **day:** | Green / Yellow / Red | 5-hour rate-limit usage — your current session block. Green under 50%, yellow under 80%, red above |
| **week:** | Green / Yellow / Red | 7-day rate-limit usage — same color scale |
| **Project** | Magenta | Current working directory name |
| **Git Branch** | Green | Active git branch (omitted outside a repo) |

The `day:` and `week:` percentages are the headline feature — you can see a rate limit coming before you hit it instead of finding out mid-task.

---

## Installation

**Prerequisite:** Node.js (`node --version` to check). The status line *is* a node script, so Node must be on the machine — deploy `software/node/install.sh` first. If Terminal says node isn't found, ask IT.

### Fleet install (Mosyle) — the easy path

`install.sh` in this folder does both manual steps below, per-user, on a recurring schedule: it drops to the logged-in console user, places `statusline.js` in their `~/.claude/`, and **merges** the `statusLine` key into their `~/.claude/settings.json` without touching their other settings (it refuses rather than clobber a settings.json it can't parse). Scope it to the same machines that get the Node installer.

```bash
#!/bin/bash
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/claude/statusline/install.sh" | bash
```

The manual steps below are the same thing by hand, if you'd rather.

### Step 1: Copy the script

From this folder:

```bash
cp statusline.js ~/.claude/statusline.js
```

### Step 2: Update Claude Code settings

Open (or create) `~/.claude/settings.json` and add the `statusLine` entry:

```json
{
  "statusLine": {
    "type": "command",
    "command": "node ~/.claude/statusline.js"
  }
}
```

> **Note:** If you already have a `settings.json`, merge the `statusLine` key into your existing config — don't overwrite the whole file. (`settings-example.json` in this folder shows exactly the snippet needed.)

### Step 3: Restart Claude Code

Close and reopen Claude Code. The status line appears at the bottom immediately.

---

## How It Works

Claude Code runs the script after each turn, piping it a JSON payload on `stdin` (model info, context window stats, rate-limit usage, workspace details). The script prints one ANSI-colored line, and Claude Code displays it as the status bar. Running it by hand does nothing interesting — it only makes sense when Claude Code is the one calling it.

Key behaviors:
- **Context warning:** percentage turns red plus a `!!` tag above 80% usage or past 200k tokens
- **Rate-limit sections appear only when the data exists** — older Claude Code versions without rate-limit reporting just show fewer sections
- **Git-aware:** detects the current branch; silently omitted if git is unavailable or you're not in a repo
- **Cross-platform:** handles both Unix `/` and Windows `\` paths
- **No dependencies:** Node built-ins only; nothing to install

## Files

| File | Description |
|------|-------------|
| `statusline.js` | The status line script — copy this to `~/.claude/` |
| `settings-example.json` | Example settings snippet showing the required config |

---

Adapted from [chriskehayias/ContextEngineering](https://github.com/chriskehayias/ContextEngineering/tree/main/resources/Claude/statusline) — ours swaps the token-count/cost display for rate-limit (day/week) tracking.
