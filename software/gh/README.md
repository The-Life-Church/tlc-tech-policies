# GitHub CLI (`gh`) — Silent Installer

This folder contains the silent installer for the GitHub CLI, deployed to Life Church Macs via Mosyle. It installs GitHub's universal `.pkg` directly from the official release — no Homebrew dependency.

> **Note:** GitHub ships this pkg **unsigned** (verified — `pkgutil --check-signature` reports no signature). That's fine for `installer -pkg` as root in a script (signature checks only gate GUI/Gatekeeper installs and MDM-native pkg pushes), but it means the pinned SHA-256 below is the *only* integrity check on the download. Don't skip it, and don't switch this to Mosyle's native pkg-push flow without re-checking — Mosyle's InstallApplication path requires signed pkgs.

---

## What It Does

Downloads the pinned `gh_<ver>_macOS_universal.pkg` from the official `cli/cli` GitHub release, verifies its SHA-256 against a hash pinned in the script, and installs it with `installer -pkg -target /` as root. Lands at `/usr/local/bin/gh`. No console-user dance, no privilege juggling — the pkg is built to install as root.

**Version pinning.** `GH_VERSION` and `GH_SHA256` are pinned at the top of `install.sh`. Bumping gh is a two-line PR; devices converge on the next recurring run. Pinning the SHA in the script (instead of fetching the checksums file at runtime) means a tampered download can't pass silently — a hash change has to come through a reviewed PR.

**Guarantees:**
- Idempotent — exits 0 immediately if the pinned version is already installed
- Reinstalls if the installed version differs from the pin (up- or downgrade)
- Checksum-verified before `installer` runs; refuses on mismatch
- Download and install each wrapped in `timeout 600` (10 min)
- Warns if a leftover Homebrew-installed gh exists at `/opt/homebrew/bin/gh` (it would shadow `/usr/local/bin/gh` in brew-managed user shells)
- Logs to `/tmp/gh-install-<timestamp>.log` — cleaned up on success, kept on failure

**Exit codes:**

| Code | Meaning |
|---|---|
| 0 | gh present at the pinned version (already installed, or installed now) |
| 1 | Download, checksum, or install failure |

---

## Files

- `install.sh` — Mosyle script. Downloads, verifies, and installs the pinned gh release as root.

---

## Deployment

Mosyle → **Custom Scripts → Add Script**

**gh Install**
- Run as: `root`
- Schedule: Once or recurring (idempotent — recurring picks up version bumps merged to `main`)
- Scope: Vibe coders / IT-dev group

**Paste into Mosyle's Custom Script box** (the shebang is required — Mosyle writes the body to a file and executes it):
```bash
#!/bin/bash
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/gh/install.sh" | bash
```

**To test on your own Mac** — open Terminal and paste just the `curl` line (no shebang — zsh will try to run `#!/bin/bash` as a command and error out):
```bash
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/gh/install.sh" | bash
```

**No prerequisites.** gh doesn't need CLT, Homebrew, or a logged-in user. (Using it for actual git work still wants CLT on the machine — see `software/xcode/`.)

**Verify:**
```bash
gh --version
```

If the install fails, the log at `/tmp/gh-install-*.log` is kept for diagnosis.

**Egress note:** the download comes from `github.com` → redirects to `objects.githubusercontent.com`. Both must be reachable through any web filtering.

---

## Updating the pinned version

1. Find the new release at <https://github.com/cli/cli/releases>
2. Copy the SHA-256 for `gh_<ver>_macOS_universal.pkg` from that release's `gh_<ver>_checksums.txt`
3. Branch, update `GH_VERSION` and `GH_SHA256` in `install.sh`, open a PR
4. Get one reviewer to approve, merge to `main`
5. Devices reinstall to the new pin on their next scheduled run

---

## Why not Homebrew?

The previous version of this script ran `brew install gh` as the console user, which required Homebrew on every target machine — and bootstrapping brew required granting the console user a temporary `NOPASSWD: ALL` sudoers drop-in. Brew also refuses to run as root, is per-user rather than system-wide, and upgrades on its own rolling cadence rather than a pinned version.

Installing the official pkg directly removes the brew prerequisite, the sudoers exposure, and the version drift. `software/homebrew/` remains available for IT-dev machines that want brew for other reasons, but nothing in the standard deploy chain depends on it anymore.
