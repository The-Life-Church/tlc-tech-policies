# Xcode Command Line Tools — Silent Installer

This folder contains the silent installer for Xcode Command Line Tools (CLT), deployed to Life Church Macs via Mosyle. CLT is the prerequisite for git, Homebrew, and most developer tooling, so it ships first.

---

## What It Does

Runs `softwareupdate -i` headlessly with the `.com.apple.dt.CommandLineTools.installondemand.in-progress` flag, which makes the hidden CLT package visible to the catalog. No GUI prompt. Skips if CLT is already installed.

Logs to `/tmp/clt-install-<timestamp>.log`:
- Cleaned up on success
- Kept on failure so the log is available for Mosyle reporting

`set -euo pipefail` plus explicit exit codes makes Mosyle's success/failure indicator meaningful. `softwareupdate -i` is wrapped in `timeout 1800` so a stuck Apple CDN can't hang the device.

---

## Files

- `install-clt.sh` — Mosyle script. Detects whether CLT is installed, locates the newest CLT package in the software update catalog, and installs it as root. Idempotent — safe to run on a recurring schedule.

---

## Deployment

The script lives in this repo and is invoked by Mosyle via `curl | bash` — merge a PR to `main` and devices pick up the latest version on the next run.

Mosyle → **Custom Scripts → Add Script**

**CLT Install**
- Run as: `root`
- Schedule: One-time or recurring (idempotent either way)
- Scope: Any group that needs developer tooling (vibe coders, IT/dev)

**Paste into Mosyle's Custom Script box** (the shebang is required — Mosyle writes the body to a file and executes it):
```bash
#!/bin/bash
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/xcode/install-clt.sh" | bash
```

**To test on your own Mac** — open Terminal and paste just the `curl` line (no shebang — zsh will try to run `#!/bin/bash` as a command and error out):
```bash
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/xcode/install-clt.sh" | bash
```

**Verify:**
```bash
xcode-select -p
# Should print: /Library/Developer/CommandLineTools
```

If the install fails, check `/tmp/clt-install-*.log` — it's only kept on failure.

---

## Deployment Order

CLT is a prerequisite for Homebrew. If you're rolling out a fresh dev-tools stack:

1. `software/xcode/install-clt.sh` — installs CLT
2. `software/homebrew/install.sh` — installs Homebrew + gh (refuses to run without CLT)

---

## Updating

1. Branch, edit `install-clt.sh`, open a PR
2. Get one reviewer to approve
3. Merge to `main`
4. Mosyle picks up the change on the next scheduled run
