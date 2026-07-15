# Firebase CLI (firebase-tools) — Silent Installer

Installs the pinned [`firebase-tools`](https://github.com/firebase/firebase-tools) npm package system-wide via the fleet Node's global prefix, so `firebase` is on PATH for every user. One binary carries the **CLI**, the local **emulator suite**, and the **MCP server** (`firebase mcp`) — the entire Firebase toolchain for builders. How builders actually use it (emulator-first dev, MCP boundaries, ship-by-git-push) is defined in the runbook: [`software/firebase/README.md`](../firebase/README.md).

## Why a fleet install (and not npx or a repo devDependency)

- **npx is never the delivery mechanism**: blocked in Bash/Terminal, and in `.mcp.json` (where it isn't blocked — MCP spawning bypasses deny rules) it pulls unreviewed `@latest`, skipping this pin entirely. Project MCP configs reference the bare `firebase` command.
- **Repo-local pins go stale forever**: projects fork off the app template and never pull from it again, so a devDependency pin would be orphaned per-fork. The fleet pin is the single version everywhere — merging one bump PR updates every machine and every project on the next recurring run, regardless of repo age.

## What It Does

1. Converges **Node** — always runs `software/node/install.sh` (fast no-op at the pin), so Node pin bumps reach these machines on every run; the CLI needs ≥ 20.
2. Converges **Java** — always runs `software/java/install.sh` (no-op at the exact pinned Temurin release), so JRE patch/CVE bumps propagate too. The Firestore emulator needs ≥ 21; other JVMs on the machine are left alone.
3. Converges the **GitHub CLI** — always runs `software/gh/install.sh` (version-idempotent; fast no-op at the pin). Not a firebase need — gh is how builders clone org repos and reach the private plugin marketplace — and running it unconditionally means **gh pin bumps reach machines that only get this script** (the standalone gh script is a manual-run deploy). Per-user `gh auth login` remains the IT-assisted first-time step.
4. Installs/pins `firebase-tools` globally (fleet Node's prefix, binary at `/usr/local/bin/firebase`).

So Mosyle only needs **this** script scoped to the group — Node, Java, and gh come along, making it the one-stop vibe-coder toolchain script. (`software/node/`, `software/java/`, and `software/gh/` stay independently deployable.)

**Pinning.** `FIREBASE_TOOLS_VERSION` at the top of `install.sh` — npm package, so integrity is the exact-version pin + the npm registry (no per-arch SHA; same posture as hyperframes). Bumps arrive as PRs from the `firebase-tools` job in `bump-pins.yml` (14-day cooldown).

**Idempotent** — fast no-op when the pinned version is installed; reinstalls on version mismatch (up- or downgrade). firebase-tools shows update-notifier notices but does **not** self-install updates, so no wrapper is needed (unlike hyperframes).

**No auth ships here.** Builders are never logged in (`firebase login` is an IT step); the emulators run against `demo-*` project IDs with no login at all. Emulator JARs download per-user on first `firebase emulators:start` (into `~/.cache/firebase/emulators` — needs egress; expected, one-time).

## Mosyle

- Run as: `root` · Schedule: **recurring** (recurring runs are how merged pin bumps reach devices) · Scope: vibe coders / IT-dev (opt-in)

```bash
#!/bin/bash
# TLC Firebase CLI — Silent Install
# Installs: firebase-tools — firebase CLI + emulator suite + Firebase MCP server (pinned)
# Also converges to fleet pins: Node.js, Temurin Java, GitHub CLI
# root · recurring · scope: vibe coders / IT-dev (opt-in)
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/firebase-tools/install.sh" | bash
```

## Exit codes

| Code | Meaning |
|---|---|
| 0 | firebase-tools at the pinned version; Node + Java satisfied |
| 1 | Install failure, or a prerequisite bootstrap (Node or Java) failed |

Logs to `/tmp/firebase-tools-install-<timestamp>.log` — removed on success, kept on failure.
