# CLAUDE.md — working in tlc-tech-policies

Guidance for Claude Code sessions in this repo. (Not to be confused with `software/claude/CLAUDE.md`, which is the fleet policy this repo *deploys* — editing that file changes what every staff Mac's Claude loads.)

## What this repo is

Managed IT policy for The Life Church staff Macs and Claude surfaces. **Merging to `main` is deploying**: Mosyle pulls scripts from `raw.githubusercontent.com/.../main/...` on recurring schedules, so anything merged here runs as root on staff machines on the next cycle. Review accordingly. The repo is public so Mosyle's unauthenticated pulls work — nothing sensitive goes in here, ever.

## Hard rules

- Scripts run as root via `curl | bash` from Mosyle. Treat every edit as fleet-impacting.
- Test scripts before merge: `bash -n` at minimum; logic changes get a real run on a test Mac.
- Validate workflow YAML with `ruby -ryaml -e "YAML.safe_load(File.read('<file>'), aliases: true)"` — stock macOS has no PyYAML. JSON: `/usr/bin/python3 -m json.tool <file>`.
- Mosyle's root shell has a stripped PATH — use absolute paths for anything outside `/usr/bin:/bin:/usr/sbin:/sbin`.

## Adding a managed tool installer — do all four

The one people forget is #3.

1. `software/<tool>/install.sh` — copy the shape of `software/gh/install.sh`: pinned `VERSION` (+ `SHA256` if the artifact is unsigned), idempotent version check, download → verify checksum → `installer -pkg -target /`, log + exit codes, `trap` cleanup.
2. `software/<tool>/README.md` — what it does, Mosyle deploy block, scope, exit codes.
3. **`.github/workflows/bump-pins.yml`** — GitHub-release tool: add a matrix entry to the `github-release` job (~6 lines; multi-arch tools pinning two SHAs set `sha_var2` + `asset2`, see the higgsfield entry). Other source: add a dedicated job modeled on the `node` job. Skipping this means the pin never gets bump PRs and the tool silently goes stale on the fleet.
4. Mosyle — new Custom Script entry, scoped to the right group, **recurring** (recurring runs are how merged pin bumps reach devices).

Exceptions: tools with no version pin need no workflow entry (CLT installs via `softwareupdate`; Homebrew is always-latest). If the bespoke-installer count grows past ~6, adopt [Installomator](https://github.com/Installomator/Installomator) instead of adding more.

## Established patterns

- **Installers:** pinned version + SHA in the script, bump = two-line PR, devices converge via recurring runs. `bump-pins.yml` opens the bump PRs (14-day release cooldown; manual dispatch `ignore_cooldown` for urgent security fixes).
- **Scripts log** to `/tmp/<name>-<timestamp>.log` — cleaned on success, kept on failure — and use meaningful exit codes so Mosyle's success/failure indicator works.
- **macOS has no GNU `timeout`** — scripts use the perl `alarm` shim (see any installer).
- **Three Claude policy artifacts in `software/claude/`:** `CLAUDE.md` (fleet behavioral policy), `managed-settings.json` (deny list), `ADMIN.md` (Claude.ai org prefs). The fleet `CLAUDE.md` carries no command lists — it and the `coding:command-blocked` skill (tlc-claude-plugins) treat `managed-settings.json` and the shell policy script as the source of truth, so when a deny rule changes, sync only `software/shell/README.md`'s human-readable list (and the summary bullets in `software/claude/README.md`).
- **Fleet `CLAUDE.md` points at `coding:*` skills by name** (tlc-claude-plugins). Renaming a skill there silently breaks the policy pointer — keep names in lockstep; the pointer table lives in `software/claude/README.md`.
- **Shell policy wrappers** (`software/shell/`) only affect interactive zsh — npm scripts and git hooks are unaffected. Keep the vibe-coder block list in parity with `managed-settings.json` where it makes sense (installs and package runners blocked; restores and `npm run` allowed).
- **Per-user installers** (`install-claude-code.sh`, `statusline/install.sh`) run as root but **drop to the console user** (`stat -f%Su /dev/console` + `dscl … NFSHomeDirectory`, then `sudo -u "$USER" -H …`) because they write to the user's home — running them as root would install into `/var/root`. They're not pinned and not in bump-pins: Claude Code self-updates; the status line tracks main. No sudoers dance needed (unlike Homebrew) since they only touch the user's own files.
- **`chore/bump-<slug>-<version>` branch names are reserved** — `bump-pins.yml` uses branch existence as its already-open dedupe; creating one manually suppresses that tool's bump PR.
- **Testing shell-policy wrappers:** extract the heredoc and source it in a sandboxed zsh with `command`/PATH stubbed *first* — a bad extraction means the real package managers run (this has happened).

## Docs to keep in sync

Each folder's README is the source of truth for its details. The root README stays short — tree, areas table, cross-surface table, canonical raw URLs. This file carries the working conventions and the add-a-tool checklist. (There is no STRUCTURE.md — it was merged into the README.)
