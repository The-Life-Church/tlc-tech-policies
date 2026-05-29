#!/bin/bash

# The Life Church — Homebrew Silent Install
#
# ===== What to put in Mosyle =================================================
#   Mosyle -> Scripts (Custom Command) -> new shell script
#     Name:   TLC Homebrew — Silent Install
#     Run:    Once or recurring     As: root (script drops to console user)     Scope: vibe coders / IT-dev (after CLT)
#     Script:
#       #!/bin/bash
#       curl -fsSL https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/homebrew/install.sh | bash
# =============================================================================
#
# Homebrew refuses to install as root, so this script detects the active console
# user and runs the brew install as them. The brew installer needs sudo
# internally; we grant the console user temporary NOPASSWD sudo for the duration
# via a /etc/sudoers.d drop-in removed by trap on every exit path. Failures are
# captured in the log file and reflected in the exit code.

set -euo pipefail

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="/tmp/brew-install-${TIMESTAMP}.log"
HOSTNAME=$(scutil --get ComputerName 2>/dev/null || hostname)
SERIAL=$(ioreg -c IOPlatformExpertDevice -d 2 | awk -F\" '/IOPlatformSerialNumber/{print $4}')
SUDOERS_DROPIN="/etc/sudoers.d/tlc-brew-install"

log() {
    local msg="[BREW-INSTALL $(date '+%Y-%m-%d %H:%M:%S')] $1"
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

# --- Guard: must run as root ---
# We need root to write the temporary sudoers drop-in.
if [ "$(id -u)" -ne 0 ]; then
    log "ERROR: This script must run as root (Mosyle default). Got uid $(id -u)."
    exit 1
fi

# --- Guard: CLT is a hard prerequisite ---
# Homebrew needs git/make/etc. Without CLT the official installer will
# prompt a GUI dialog and stall under Mosyle. Run install-clt.sh first.
if ! xcode-select -p &>/dev/null; then
    log "ERROR: Xcode Command Line Tools not installed. Run install-clt.sh before this script."
    exit 1
fi

# --- Identify the console user (the one logged in at the GUI) ---
CONSOLE_USER=$(stat -f%Su /dev/console 2>/dev/null || echo "")
if [ -z "$CONSOLE_USER" ] || [ "$CONSOLE_USER" = "root" ] || [ "$CONSOLE_USER" = "_mbsetupuser" ]; then
    log "ERROR: No real console user logged in (got '${CONSOLE_USER}'). Homebrew requires an active user session."
    exit 1
fi

log "Starting on ${HOSTNAME} (${SERIAL}) for user '${CONSOLE_USER}'."

# --- Temporary passwordless sudo for the console user ---
# The Homebrew installer (running as the user) calls `sudo` to chown/chmod
# its install prefix. With NONINTERACTIVE=1 it can't prompt for a password,
# so we grant short-lived NOPASSWD sudo via /etc/sudoers.d. The trap removes
# this file on EVERY exit path — success, error, or signal.
cleanup_sudoers() {
    if [ -f "$SUDOERS_DROPIN" ]; then
        rm -f "$SUDOERS_DROPIN"
        log "Removed temporary sudoers drop-in."
    fi
}
trap cleanup_sudoers EXIT INT TERM

log "Granting '${CONSOLE_USER}' temporary NOPASSWD sudo via ${SUDOERS_DROPIN}..."
umask 077
echo "${CONSOLE_USER} ALL=(ALL) NOPASSWD: ALL" > "$SUDOERS_DROPIN"
chown root:wheel "$SUDOERS_DROPIN"
chmod 0440 "$SUDOERS_DROPIN"
# Validate the file before relying on it — visudo -c -f returns non-zero on bad syntax.
if ! visudo -c -f "$SUDOERS_DROPIN" >/dev/null; then
    log "ERROR: sudoers drop-in failed validation. Aborting."
    exit 1
fi

# --- Install Homebrew ---
if [ -x "$BREW" ]; then
    log "Homebrew already installed at ${BREW}."
else
    log "Homebrew not found. Downloading installer..."
    # `mktemp` with no args uses $TMPDIR, which on macOS defaults to
    # /var/folders/<user>/... — root's copy is mode 700, so williamturner
    # (or any console user) can't traverse it. Pin the path under /tmp
    # (world-readable on macOS) and chmod the file so the dropped user
    # can read and execute it.
    INSTALLER=$(mktemp /tmp/tlc-brew-installer.XXXXXX)
    if ! curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$INSTALLER"; then
        log "ERROR: Failed to download Homebrew installer."
        rm -f "$INSTALLER"
        exit 1
    fi
    chmod 0644 "$INSTALLER"

    log "Running Homebrew installer as '${CONSOLE_USER}' (30 min timeout)..."
    # NONINTERACTIVE=1 suppresses the "press return to continue" prompt.
    # `sudo -u user env VAR=val` is the portable way to pass env across the privilege drop.
    if ! timeout 1800 sudo -u "$CONSOLE_USER" env NONINTERACTIVE=1 /bin/bash "$INSTALLER" 2>&1 | tee -a "$LOG_FILE"; then
        log "ERROR: Homebrew install failed or timed out."
        rm -f "$INSTALLER"
        exit 1
    fi
    rm -f "$INSTALLER"

    if [ ! -x "$BREW" ]; then
        log "ERROR: Install reported success but ${BREW} is not present."
        exit 1
    fi
    log "Homebrew installed at ${BREW}."
fi

# --- Verify ---
if sudo -u "$CONSOLE_USER" "$BREW" --version &>/dev/null; then
    log "Homebrew verified successfully."
    rm -f "$LOG_FILE"
    exit 0
else
    log "ERROR: Verification failed after install."
    exit 1
fi
