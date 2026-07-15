# Xcode Command Line Tools — Silent Installer

This folder contains the silent installer for Xcode Command Line Tools (CLT), deployed to Life Church Macs via Mosyle. CLT is the prerequisite for git, Homebrew, and most developer tooling, so it ships first.

---

## What It Does

Runs `softwareupdate -i` headlessly with the `.com.apple.dt.CommandLineTools.installondemand.in-progress` flag, which makes the hidden CLT package visible to the catalog. No GUI prompt.

**Health check, not just presence check.** The "already installed" guard runs `git --version` from the selected developer directory rather than trusting `xcode-select -p`. macOS major upgrades leave the CLT directory and the xcode-select pointer in place while the tools inside break — a path check passes, but git (and the Claude Code desktop app, which hard-gates on git) is dead. When the script finds a present-but-broken CLT, it removes it and reinstalls fresh. Machines with full Xcode selected pass the health check and are left alone.

Logs to `/tmp/clt-install-<timestamp>.log`:
- Cleaned up on success
- Kept on failure so the log is available for Mosyle reporting

`set -euo pipefail` plus explicit exit codes makes Mosyle's success/failure indicator meaningful. `softwareupdate -i` is wrapped in `timeout 1800` so a stuck Apple CDN can't hang the device. The catalog sentinel file is removed by a `trap` on every exit path, so a failed run can't leak it.

**Exit codes:**

| Code | Meaning |
|---|---|
| 0 | CLT healthy — already installed, or installed successfully |
| 1 | Install failed — download/install error, or git still broken after install |
| 3 | Catalog returned no CLT package — `softwareupdate -l` output format changed, or an MDM software-update deferral is hiding the label. See Fallback below. |

---

## Files

- `install-clt.sh` — Mosyle script. Health-checks the existing install (`git --version`, not just path presence), clears a stale CLT if a macOS upgrade broke it, locates the newest non-beta CLT package in the software update catalog, and installs it as root. Idempotent — safe to run on a recurring schedule.

---

## Deployment

The script lives in this repo and is invoked by Mosyle via `curl | bash` — merge a PR to `main` and devices pick up the latest version on the next run.

Mosyle → **Custom Scripts → Add Script**

**CLT Install**
- Run as: `root`
- Schedule: One-time or recurring (idempotent either way). Note: macOS major upgrades break CLT in place — if scheduled one-time, re-run on the fleet after each major OS upgrade. Recurring makes that self-healing, and healthy machines exit in under a second with no download.
- Scope: Any group that needs git — vibe coders, IT/dev, and anyone receiving the Claude Code desktop app (it won't proceed until git is present)

**Paste into Mosyle's Custom Script box** (the shebang is required — Mosyle writes the body to a file and executes it):
```bash
#!/bin/bash
# TLC Xcode Command Line Tools — Silent Install
# Installs: Xcode Command Line Tools (git etc.) only — self-heals CLT broken by macOS upgrades
# root · once or recurring · scope: anyone needing git (vibe coders, devs, Claude Code desktop app)
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/xcode/install-clt.sh" | bash
```

**Self-Service catalog item (with progress window)** — background/recurring entries keep the silent block above; see [`software/selfservice/`](../selfservice/README.md):
```bash
#!/bin/bash
# TLC Self-Service — Xcode CLI (with progress window)
# Runs the same installer with a swiftDialog progress UI — Self-Service items ONLY.
# root · Self-Service · scope: anyone needing git
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/selfservice/with-progress.sh" | bash -s -- xcode "Xcode CLI"
```

**To test on your own Mac** — open Terminal and paste the `curl` line with `sudo bash` (the `softwareupdate` install needs root, which Mosyle has automatically; no shebang — zsh would try to run `#!/bin/bash` as a command):
```bash
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/xcode/install-clt.sh" | sudo bash
```

**Verify:**
```bash
xcode-select -p
# Should print: /Library/Developer/CommandLineTools
```

If the install fails, check `/tmp/clt-install-*.log` — it's only kept on failure.

---

## Fallback — exit code 3

Exit 3 means the software update catalog returned no CLT package. Two known causes:

1. **Apple changed the `softwareupdate -l` output format** — the label grep is the fragile part of this approach and historically shifts between macOS releases. Test on the new OS version after each major release and fix the parse if needed.
2. **An MDM software-update deferral is hiding the label** — if Mosyle defers macOS updates, the CLT entry may not appear in the catalog during the deferral window. Verify on a deferred device.

If the catalog path is broken and can't wait for a parse fix: download "Command Line Tools for Xcode" (.dmg containing a .pkg) from [developer.apple.com/download/all](https://developer.apple.com/download/all/) (Apple Developer login required), and push the .pkg through Mosyle as a managed install. Same artifact, version-pinned, no catalog dependency — at the cost of re-hosting it yourself when Apple ships a new version.

---

## Deployment Order

If you're rolling out a fresh dev-tools stack:

1. `software/xcode/install-clt.sh` — installs CLT (git)
2. `software/gh/install.sh` — installs the GitHub CLI (standalone pkg, no prereqs)

Homebrew (`software/homebrew/`) is no longer part of the standard chain — it's IT-dev-only, and CLT remains its prerequisite if it's deployed.

---

## Updating

1. Branch, edit `install-clt.sh`, open a PR
2. Get one reviewer to approve
3. Merge to `main`
4. Mosyle picks up the change on the next scheduled run
