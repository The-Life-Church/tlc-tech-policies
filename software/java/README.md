# Temurin JRE — Silent Installer

Installs a pinned [Eclipse Temurin](https://adoptium.net/) JRE (LTS major) system-wide from the official Adoptium GitHub release pkg. Exists because the **Firebase emulator suite requires a Java runtime** — the Firestore emulator won't start without one. Machines getting the Firebase CLI (`software/firebase-tools/`) need this; that installer bootstraps this one automatically, so scope this script separately only for hosts that want Java without the Firebase toolchain.

## What It Does

- Downloads the pinned per-arch Temurin **JRE** pkg (`aarch64` / `x64`) from the [`adoptium/temurin21-binaries`](https://github.com/adoptium/temurin21-binaries) release, verifies it against the pinned SHA-256 (from the Adoptium API's published checksums), and runs `installer -pkg -target /`.
- Installs side-by-side under `/Library/Java/JavaVirtualMachines/temurin-21.jre` — **other JVMs on the machine are left alone**; `/usr/bin/java` and `java_home` resolve as usual.
- Idempotent by **exact Temurin release**: checks the installed JRE's release file for `IMPLEMENTOR_VERSION="Temurin-<version>+<build>"` — a match is a fast no-op; anything else (missing, older build) converges to the pin.

**Pinning.** `TEMURIN_VERSION` + `TEMURIN_BUILD` + two per-arch SHAs at the top of `install.sh`. The pkgs are signed by Eclipse Adoptium, but the SHA is verified anyway. Bumps arrive as PRs from the `temurin` job in `bump-pins.yml` (14-day cooldown). The job tracks **the pinned LTS major only** (currently 21) — moving to a new major (e.g. 25 LTS) is a deliberate manual change to the script and the workflow job, not an automated bump.

## Mosyle

- Run as: `root` · Schedule: recurring · Scope: firebase-emulator hosts (opt-in; usually just scope `software/firebase-tools/` instead, which bootstraps this)

```bash
#!/bin/bash
# TLC Temurin JRE — Silent Install
# Installs: Temurin Java (JRE) only — Firestore emulator runtime; other JVMs untouched
# Usually arrives via the Firebase CLI script — deploy alone only when needed without it
# root · once or recurring · scope: firebase-emulator hosts (opt-in)
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/java/install.sh" | bash
```

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Pinned Temurin JRE present (already, or after install) |
| 1 | Download, checksum mismatch, or install failure |

Logs to `/tmp/java-install-<timestamp>.log` — removed on success, kept on failure.
