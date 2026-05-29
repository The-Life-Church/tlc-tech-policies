#!/bin/bash

# The Life Church — GitHub CLI (gh) Silent Install
#
# ===== What to put in Mosyle =================================================
#   Mosyle -> Scripts (Custom Command) -> new shell script
#     Name:   TLC GitHub CLI (gh) — Silent Install
#     Run:    Once or recurring     As: root (script drops to console user)     Scope: vibe coders / IT-dev (after Homebrew)
#     Script:
#       #!/bin/bash
#       curl -fsSL https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/gh/install.sh | bash
# =============================================================================
#
# Requires Homebrew (see software/homebrew/install.sh). Runs `brew install gh`
# as the active console user. No sudo dance needed — brew already owns its prefix
# after install. Failures are captured in the log file and reflected in the exit code.

set -euo pipefail

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="/tmp/gh-install-${TIMESTAMP}.log"
HOSTNAME=$(scutil --get ComputerName 2>/dev/null || hostname)
SERIAL=$(ioreg -c IOPlatformExpertDevice -d 2 | awk -F\" '/IOPlatformSerialNumber/{print $4}')

log() {
    local msg="[GH-INSTALL $(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$LOG_FILE"
}

# macOS doesn't ship with GNU `timeout` (it's part of coreutils). Provide a
# shim using perl's alarm(), which is bundled with the OS. Same usage:
# `timeout SECONDS command args...`. SIGALRM kills the process on expiry.
timeout() {
    perl -e 'alarm shift; exec @ARGV' "$@"
}

# Homebrew prefix depends on architecture
if [ "$(uname -m)" = "arm64" ]; then
    BREW="/opt/homebrew/bin/brew"
else
    BREW="/usr/local/bin/brew"
fi

# --- Guard: brew is required ---
if [ ! -x "$BREW" ]; then
    log "ERROR: Homebrew not found at ${BREW}. Run software/homebrew/install.sh first."
    exit 1
fi

# --- Identify the console user ---
# gh installs into brew's prefix, which is owned by the console user.
# `brew install` refuses to run as root.
CONSOLE_USER=$(stat -f%Su /dev/console 2>/dev/null || echo "")
if [ -z "$CONSOLE_USER" ] || [ "$CONSOLE_USER" = "root" ] || [ "$CONSOLE_USER" = "_mbsetupuser" ]; then
    log "ERROR: No real console user logged in (got '${CONSOLE_USER}')."
    exit 1
fi

log "Starting on ${HOSTNAME} (${SERIAL}) for user '${CONSOLE_USER}'."

# --- Install gh ---
if sudo -u "$CONSOLE_USER" "$BREW" list gh &>/dev/null; then
    log "gh already installed. Checking for updates..."
    # Idempotent — also catches stale installs on recurring runs.
    if ! timeout 600 sudo -u "$CONSOLE_USER" "$BREW" upgrade gh 2>&1 | tee -a "$LOG_FILE"; then
        log "WARNING: brew upgrade gh failed or timed out (existing install still functional)."
    fi
else
    log "Installing gh via Homebrew (10 min timeout)..."
    if ! timeout 600 sudo -u "$CONSOLE_USER" "$BREW" install gh 2>&1 | tee -a "$LOG_FILE"; then
        log "ERROR: gh install failed or timed out."
        exit 1
    fi
    log "gh installed."
fi

# --- Verify ---
if sudo -u "$CONSOLE_USER" "$BREW" list gh &>/dev/null; then
    GH_VERSION=$(sudo -u "$CONSOLE_USER" "$BREW" list --versions gh 2>/dev/null || echo "unknown")
    log "gh verified: ${GH_VERSION}."
    rm -f "$LOG_FILE"
    exit 0
else
    log "ERROR: Verification failed after install."
    exit 1
fi
