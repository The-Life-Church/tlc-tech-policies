# swiftDialog — Silent Installer

Installs the pinned [swiftDialog](https://github.com/swiftDialog/swiftDialog) release — the Mac-admin-standard tool for showing native dialogs and progress bars from management scripts. On this fleet it exists for one job: powering the **Self-Service progress wrapper** (`software/selfservice/`), so "Install Now" clicks show a live window instead of running invisibly.

Machines normally get it via the wrapper's bootstrap on first Self-Service use — scope this script directly only if you want it pre-staged.

## What It Does

- Downloads the pinned pkg (`dialog-<version>-<build>.pkg`) from the official GitHub release and verifies it **twice**: against the pinned SHA-256, and via `pkgutil --check-signature` (Developer ID team `PWA5E9TQ59`, notarized).
- Installs `/usr/local/bin/dialog` + `Dialog.app`. Nothing else.
- Idempotent — fast no-op when `dialog --version` matches the pinned **version.build** exactly; reinstalls on any mismatch (including build-only respins).
- **Requires macOS 15+** (upstream requirement for swiftDialog 3.x). On older Macs the installer exits 1 and the Self-Service wrapper degrades to silent installs; if a macOS 13/14 cohort ever matters, pin upstream's v2.5.6 as a separate legacy path.

**Pinning.** Version + build + SHA at the top of `install.sh`. Upstream publishes **no checksums file**, so the SHA is computed by downloading the asset in CI (the ffmpeg pattern). Bumps arrive as PRs from the `dialog` job in `bump-pins.yml` (14-day cooldown; `releases/latest` skips upstream's RC/beta releases automatically).

## Mosyle

```bash
#!/bin/bash
# TLC swiftDialog — Silent Install
# Installs: swiftDialog (/usr/local/bin/dialog + Dialog.app) only — Self-Service progress UI
# Usually arrives via the Self-Service wrapper's bootstrap — deploy alone only to pre-stage it
# root · once or recurring · scope: Self-Service Macs
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/dialog/install.sh" | bash
```

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Pinned swiftDialog present (already, or after install) |
| 1 | Download, checksum, signature, or install failure |

Logs to `/tmp/dialog-install-<timestamp>.log` — removed on success, kept on failure.
