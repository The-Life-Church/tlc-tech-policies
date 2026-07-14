# Firebase CLI (firebase-tools) — Silent Installer

Installs the pinned [`firebase-tools`](https://github.com/firebase/firebase-tools) npm package system-wide via the fleet Node's global prefix, so `firebase` is on PATH for every user. One binary carries the **CLI**, the local **emulator suite**, and the **MCP server** (`firebase mcp`) — the entire Firebase toolchain for builders. How builders actually use it (emulator-first dev, MCP boundaries, ship-by-git-push) is defined in the runbook: [`software/firebase/README.md`](../firebase/README.md).

## Why a fleet install (and not npx or a repo devDependency)

- **npx is never the delivery mechanism**: blocked in Bash/Terminal, and in `.mcp.json` (where it isn't blocked — MCP spawning bypasses deny rules) it pulls unreviewed `@latest`, skipping this pin entirely. Project MCP configs reference the bare `firebase` command.
- **Repo-local pins go stale forever**: projects fork off the app template and never pull from it again, so a devDependency pin would be orphaned per-fork. The fleet pin is the single version everywhere — merging one bump PR updates every machine and every project on the next recurring run, regardless of repo age.

## What It Does

1. Ensures **Node ≥ 20** — bootstraps `software/node/install.sh` if missing or too old.
2. Ensures **Java ≥ 21** — bootstraps `software/java/install.sh` if missing or too old (the Firestore emulator requires it; the CLI itself doesn't; an existing 11/17 JRE is not enough).
3. Installs/pins `firebase-tools` globally (fleet Node's prefix, binary at `/usr/local/bin/firebase`).

So Mosyle only needs **this** script scoped to the group — Node and Java come along. (`software/node/` and `software/java/` stay independently deployable.)

**Pinning.** `FIREBASE_TOOLS_VERSION` at the top of `install.sh` — npm package, so integrity is the exact-version pin + the npm registry (no per-arch SHA; same posture as hyperframes). Bumps arrive as PRs from the `firebase-tools` job in `bump-pins.yml` (14-day cooldown).

**Idempotent** — fast no-op when the pinned version is installed; reinstalls on version mismatch (up- or downgrade). firebase-tools shows update-notifier notices but does **not** self-install updates, so no wrapper is needed (unlike hyperframes).

**No auth ships here.** Builders are never logged in (`firebase login` is an IT step); the emulators run against `demo-*` project IDs with no login at all. Emulator JARs download per-user on first `firebase emulators:start` (into `~/.cache/firebase/emulators` — needs egress; expected, one-time).

## Mosyle

- Run as: `root` · Schedule: **recurring** (recurring runs are how merged pin bumps reach devices) · Scope: vibe coders / IT-dev (opt-in)

```bash
#!/bin/bash
curl -fsSL https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/firebase-tools/install.sh | bash
```

## Exit codes

| Code | Meaning |
|---|---|
| 0 | firebase-tools at the pinned version; Node + Java satisfied |
| 1 | Install failure, or a prerequisite bootstrap (Node or Java) failed |

Logs to `/tmp/firebase-tools-install-<timestamp>.log` — removed on success, kept on failure.
