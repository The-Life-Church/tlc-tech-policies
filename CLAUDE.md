# CLAUDE.md — working in tlc-tech-policies

Guidance for Claude Code sessions in this repo. (Not to be confused with `software/claude/CLAUDE.md`, which is the fleet policy this repo *deploys* — editing that file changes what every staff Mac's Claude loads.)

## What this repo is

Managed IT policy for The Life Church staff Macs and Claude surfaces. **Merging to `main` is deploying**: Mosyle pulls scripts from `raw.githubusercontent.com/.../main/...` on recurring schedules, so anything merged here runs as root on staff machines on the next cycle. Review accordingly. The repo is public so Mosyle's unauthenticated pulls work — nothing sensitive goes in here, ever.

## Hard rules

- Scripts run as root via `curl | bash` from Mosyle. Treat every edit as fleet-impacting.
- Test scripts before merge: `bash -n` at minimum; logic changes get a real run on a test Mac.
- Mosyle's root shell has a stripped PATH — use absolute paths for anything outside `/usr/bin:/bin:/usr/sbin:/sbin`.

## Adding a managed tool installer — do all four

The one people forget is #3.

1. `software/<tool>/install.sh` — copy the shape of `software/gh/install.sh`: pinned `VERSION` (+ `SHA256` if the artifact is unsigned), idempotent version check, download → verify checksum → `installer -pkg -target /`, log + exit codes, `trap` cleanup.
2. `software/<tool>/README.md` — what it does, Mosyle deploy block, scope, exit codes.
3. **`.github/workflows/bump-pins.yml`** — GitHub-release tool: add a matrix entry to the `github-release` job (~6 lines). Other source: add a dedicated job modeled on the `node` job. Skipping this means the pin never gets bump PRs and the tool silently goes stale on the fleet.
4. Mosyle — new Custom Script entry, scoped to the right group, **recurring** (recurring runs are how merged pin bumps reach devices).

Exceptions: tools with no version pin need no workflow entry (CLT installs via `softwareupdate`; Homebrew is always-latest). If the bespoke-installer count grows past ~6, adopt [Installomator](https://github.com/Installomator/Installomator) instead of adding more.

## Established patterns

- **Installers:** pinned version + SHA in the script, bump = two-line PR, devices converge via recurring runs. `bump-pins.yml` opens the bump PRs (14-day release cooldown; manual dispatch `ignore_cooldown` for urgent security fixes).
- **Scripts log** to `/tmp/<name>-<timestamp>.log` — cleaned on success, kept on failure — and use meaningful exit codes so Mosyle's success/failure indicator works.
- **macOS has no GNU `timeout`** — scripts use the perl `alarm` shim (see any installer).
- **Three Claude policy artifacts in `software/claude/`:** `CLAUDE.md` (fleet behavioral policy), `managed-settings.json` (deny list), `ADMIN.md` (Claude.ai org prefs). When a deny rule changes, sync the human-readable lists in the fleet `CLAUDE.md` ("When a Command Is Blocked") and `software/shell/README.md`.
- **Shell policy wrappers** (`software/shell/`) only affect interactive zsh — npm scripts and git hooks are unaffected. Keep the vibe-coder block list in parity with `managed-settings.json` where it makes sense (installs and package runners blocked; restores and `npm run` allowed).

## Docs to keep in sync

Each folder's README is the source of truth for its details. The root README stays short — tree, areas table, cross-surface table, canonical raw URLs. This file carries the working conventions and the add-a-tool checklist. (There is no STRUCTURE.md — it was merged into the README.)
