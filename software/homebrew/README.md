# Homebrew — Silent Installer

This folder contains the silent installer for Homebrew, deployed to Life Church Macs via Mosyle. The Xcode CLT installer in `software/xcode/` is a prerequisite.

> **Scope: IT-dev only.** Homebrew is no longer part of the standard dev-tools chain — `gh` now installs from its official pkg (`software/gh/`) with no brew dependency. Brew is per-user, refuses to run as root, and bootstrapping it requires a temporary `NOPASSWD: ALL` sudoers window (see below), so it stays scoped to IT-dev machines that want it for their own tooling — don't deploy it to vibe coders or general staff.

---

## What It Does

Installs Homebrew non-interactively. Idempotent — safe to run on a recurring schedule.

**The root problem:** Homebrew explicitly refuses to install as root, but its installer internally calls `sudo` to create and chown its install prefix. Mosyle's default script context is root. So this script:

1. Runs as root (consistent with every other Mosyle script in this repo)
2. Detects the active console user via `stat -f%Su /dev/console`
3. Writes a temporary `/etc/sudoers.d/tlc-brew-install` granting that user passwordless sudo
4. Drops privileges to the user via `sudo -u` and runs the installer with `NONINTERACTIVE=1`
5. The user's internal `sudo` calls (chown the brew prefix, etc.) succeed without prompting because of step 3
6. A `trap` removes the sudoers drop-in on every exit path — success, error, or signal

Without the sudoers drop-in, `NONINTERACTIVE=1` plus a standard admin user fails with "Need sudo access" because the installer can't prompt for a password. Without `NONINTERACTIVE=1`, the installer would prompt — also no good under Mosyle. The two together with a temporary drop-in is the working combination.

If no real user is logged in (e.g., `_mbsetupuser` during Setup Assistant, or no GUI session), the script exits cleanly with an error — there's no safe user to install brew under.

**Other guarantees:**
- Hard `id -u == 0` check at the top — refuses to run if not started as root
- CLT prereq check (fails fast if `xcode-select -p` returns nothing)
- `visudo -c` validates the sudoers drop-in before relying on it
- Arch-aware brew prefix: `/opt/homebrew` on Apple Silicon, `/usr/local` on Intel
- Brew installer wrapped in `timeout 1800` (30 min)
- Logs to `/tmp/brew-install-<timestamp>.log` — cleaned up on success, kept on failure

---

## Files

- `install.sh` — Mosyle script. Installs Homebrew as the console user. Idempotent.

---

## Deployment

Mosyle → **Custom Scripts → Add Script**

**Homebrew Install**
- Run as: `root`
- Schedule: One-time or recurring (idempotent)
- Scope: Vibe coders / IT-dev group (anyone who needs brew)

**Paste into Mosyle's Custom Script box** (the shebang is required — Mosyle writes the body to a file and executes it):
```bash
#!/bin/bash
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/homebrew/install.sh" | bash
```

**To test on your own Mac** — open Terminal and paste just the `curl` line (no shebang — zsh will try to run `#!/bin/bash` as a command and error out). Pipe to `sudo bash` because the script needs root to write `/etc/sudoers.d/tlc-brew-install` (Mosyle runs as root automatically; in Terminal you have to opt in). Note: this actually installs brew under the console user, so only run it on a Mac you want brew installed on:
```bash
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/homebrew/install.sh" | sudo bash
```

**Prerequisite:** CLT must be installed first. See [`software/xcode/README.md`](../xcode/README.md). The script will fail fast if CLT is missing.

**Follow-up:** for `gh`, see [`software/gh/README.md`](../gh/README.md) — separate Mosyle entry, depends on this one.

**Verify:**
```bash
/opt/homebrew/bin/brew --version    # or /usr/local/bin/brew on Intel
```

If the install fails, the log at `/tmp/brew-install-*.log` is kept for diagnosis.

---

## Why drop to the console user instead of installing brew as root?

Homebrew has a hard refusal — running the official installer as root prints an error and exits. The two workable patterns are:

1. **Mosyle "run as logged-in user" script** — simpler script, but inconsistent with the rest of this repo's root deployment model, and we'd still need to solve the sudo-without-prompting problem for brew's internal escalation.
2. **Mosyle "run as root" script that drops privileges internally** — what this script does. One Mosyle deploy convention, one log location in `/tmp`, full control over the temporary sudoers grant.

We use (2) for consistency.

## What if someone is paranoid about temporary NOPASSWD sudo?

The drop-in exists only during the install run — typically 1–3 minutes. The `trap` removes it on every exit path: success, error, `set -e` abort, `SIGINT`, `SIGTERM`. The only way it could persist is if the entire script (and its trap) is killed with `SIGKILL` mid-run. If you want a belt-and-suspenders for that case, add a Mosyle "remove `/etc/sudoers.d/tlc-brew-install` if older than 1 hour" cleanup script as a recurring guard — but it's overkill for the actual risk surface.

---

## Updating

1. Branch, edit `install.sh`, open a PR
2. Get one reviewer to approve
3. Merge to `main`
4. Mosyle picks up the change on the next scheduled run
