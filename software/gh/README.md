# GitHub CLI (`gh`) — Silent Installer

This folder contains the silent installer for the GitHub CLI, deployed to Life Church Macs via Mosyle. It's separated from Homebrew so the two can be deployed independently — `gh` here, brew in `software/homebrew/`.

---

## What It Does

Runs `brew install gh` as the active console user. Idempotent — on recurring runs it calls `brew upgrade gh` so devices stay current with the latest release.

No sudo dance like the brew installer — once Homebrew is installed, its prefix is already owned by the user, so package installs don't need privilege escalation.

**Guarantees:**
- Refuses to run if Homebrew is missing (points at the brew script)
- Refuses to run if no real console user is logged in
- `brew install` / `brew upgrade` wrapped in `timeout 600` (10 min)
- Logs to `/tmp/gh-install-<timestamp>.log` — cleaned up on success, kept on failure

---

## Files

- `install.sh` — Mosyle script. Installs or upgrades `gh` as the console user.

---

## Deployment

Mosyle → **Custom Scripts → Add Script**

**gh Install**
- Run as: `root` (drops to console user internally)
- Schedule: Recurring (idempotent — upgrades on subsequent runs)
- Scope: Vibe coders / IT-dev group
- Script:
```bash
#!/bin/bash
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/gh/install.sh" | bash
```

**Prerequisite:** Homebrew must be installed first. See [`software/homebrew/README.md`](../homebrew/README.md). The script will fail fast if brew is missing.

**Verify on a test Mac:**
```bash
gh --version
```

If the install fails, the log at `/tmp/gh-install-*.log` is kept for diagnosis.

---

## Deployment Order

```
software/xcode/install-clt.sh     → CLT (prereq for brew)
software/homebrew/install.sh      → Homebrew (prereq for gh)
software/gh/install.sh            → gh
```

Each script fails fast if its prereq is missing, so deploy order matters but accidents won't cascade.

---

## Why a separate script and not bundled with brew?

- **Independent updates** — gh ships releases more frequently than brew. A standalone script lets us bump `gh` on a different cadence.
- **Optional install** — not everyone who needs brew needs gh.
- **One tool per Mosyle entry** — easier to track which device groups have which tool.

---

## Updating

1. Branch, edit `install.sh`, open a PR
2. Get one reviewer to approve
3. Merge to `main`
4. Mosyle picks up the change on the next scheduled run
