#!/bin/bash

# The Life Church — Claude Code Silent Install (per-user)
#
# ===== What to put in Mosyle =================================================
#   Mosyle -> Scripts (Custom Command) -> new shell script
#     Name:   TLC Claude Code — Silent Install
#     Run:    Recurring     As: root (script drops to console user)
#     Scope:  Claude Code users (same group that receives the managed policy)
#     Script:
#       #!/bin/bash
#       curl -fsSL https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/claude/install-claude-code.sh | bash
# =============================================================================
#
# Claude Code's native installer is PER-USER (installs into the user's
# ~/.claude + ~/.local/bin/claude) and SELF-UPDATES in the background. So:
#   - This must run as the logged-in console user, NOT root. Mosyle runs as
#     root by default, so the script detects the console user and drops to it.
#     Running the installer as root would land Claude Code in /var/root,
#     invisible to the actual user.
#   - It is NOT version-pinned and NOT in bump-pins.yml — the binary keeps
#     itself current. Bootstrapping once is enough; a recurring schedule just
#     heals machines where it's missing (e.g. a new user on a shared Mac).
#   - The official installer checksum-verifies its own binary, so this wrapper
#     doesn't re-pin a SHA. Version bounds, if ever needed, go in
#     managed-settings.json (minimumVersion / requiredMaximumVersion), not here.
#
# Exit codes:
#   0 — Claude Code present for the console user (already installed, or installed now)
#   1 — no real console user, or install failed

set -euo pipefail

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="/tmp/claude-code-install-${TIMESTAMP}.log"
HOSTNAME=$(scutil --get ComputerName 2>/dev/null || hostname)
SERIAL=$(ioreg -c IOPlatformExpertDevice -d 2 | awk -F\" '/IOPlatformSerialNumber/{print $4}')

log() {
    local msg="[CLAUDE-CODE-INSTALL $(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$LOG_FILE"
}

# macOS doesn't ship with GNU `timeout` (it's part of coreutils). Provide a
# shim using perl's alarm(), which is bundled with the OS.
timeout() {
    perl -e 'alarm shift; exec @ARGV' "$@"
}

# --- Identify the console user (the one logged in at the GUI) ---
CONSOLE_USER=$(stat -f%Su /dev/console 2>/dev/null || echo "")
if [ -z "$CONSOLE_USER" ] || [ "$CONSOLE_USER" = "root" ] || [ "$CONSOLE_USER" = "_mbsetupuser" ]; then
    log "ERROR: No real console user logged in (got '${CONSOLE_USER}'). Claude Code installs per-user; nothing to do."
    exit 1
fi

USER_HOME=$(dscl . -read "/Users/${CONSOLE_USER}" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
if [ -z "$USER_HOME" ] || [ ! -d "$USER_HOME" ]; then
    log "ERROR: Could not resolve home directory for '${CONSOLE_USER}'."
    exit 1
fi

CLAUDE_BIN="${USER_HOME}/.local/bin/claude"

# --- Guard: already installed for this user ---
# The binary self-updates, so presence is enough — no version check, no reinstall.
if [ -x "$CLAUDE_BIN" ]; then
    VER=$(sudo -u "$CONSOLE_USER" -H "$CLAUDE_BIN" --version 2>/dev/null | head -1 || echo "unknown")
    log "Claude Code already installed for ${CONSOLE_USER} (${VER}). Self-updates handle currency. Nothing to do."
    rm -f "$LOG_FILE"
    exit 0
fi

log "Installing Claude Code for '${CONSOLE_USER}' on ${HOSTNAME} (${SERIAL}) — 15 min timeout..."

# Run the official native installer AS THE USER, with their HOME. The installer
# downloads + checksum-verifies the binary and runs `claude install` to set up
# the ~/.local/bin/claude launcher and shell integration.
if ! timeout 900 sudo -u "$CONSOLE_USER" -H bash -c 'curl -fsSL https://claude.ai/install.sh | bash' 2>&1 | tee -a "$LOG_FILE"; then
    log "ERROR: Claude Code install failed or timed out."
    exit 1
fi

# --- Verify ---
if sudo -u "$CONSOLE_USER" -H test -x "$CLAUDE_BIN"; then
    VER=$(sudo -u "$CONSOLE_USER" -H "$CLAUDE_BIN" --version 2>/dev/null | head -1 || echo "unknown")
    log "Claude Code installed for ${CONSOLE_USER} (${VER}). User completes sign-in with /login on first run."
    rm -f "$LOG_FILE"
    exit 0
else
    log "ERROR: Install reported success but ${CLAUDE_BIN} is not present."
    exit 1
fi
