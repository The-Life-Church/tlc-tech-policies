#!/bin/bash

# The Life Church — GitHub CLI (gh) Silent Install
#
# ===== Mosyle ================================================================
#   Paste-ready block: this folder's README (Deployment/Mosyle section).
#   Name: TLC GitHub CLI (gh) — Silent Install · root · manual on pin bumps (or recurring) · scope: vibe coders / IT-dev
#   Installs: GitHub CLI only (pinned; nothing else)
# =============================================================================
#
# Installs GitHub's universal .pkg directly from the official release — no
# Homebrew, no console-user dance, runs cleanly as root. NOTE: GitHub ships
# this pkg unsigned, so the pinned SHA-256 below is the only integrity check —
# never remove it. Version and SHA are pinned together; bumping gh is a
# two-line PR (devices converge on the next recurring run). Failures are
# captured in the log file and reflected in the exit code:
#   0 — gh present at the pinned version (already installed, or installed now)
#   1 — download, checksum, or install failure

set -euo pipefail

# --- Pinned release ----------------------------------------------------------
# Update both lines together. SHA comes from gh_<ver>_checksums.txt on the
# release page: https://github.com/cli/cli/releases
GH_VERSION="2.93.0"
GH_SHA256="29c391a42a6c2312df12412e6c1e27ffbdb51ad44c6a3d55cd7bec38bff7335a"
# ------------------------------------------------------------------------------

PKG_URL="https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_macOS_universal.pkg"
GH_BIN="/usr/local/bin/gh"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="/tmp/gh-install-${TIMESTAMP}.log"
HOSTNAME=$(scutil --get ComputerName 2>/dev/null || hostname)
SERIAL=$(ioreg -c IOPlatformExpertDevice -d 2 | awk -F\" '/IOPlatformSerialNumber/{print $4}')

log() {
    local msg="[GH-INSTALL $(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$LOG_FILE"
}

PKG_FILE=$(mktemp /tmp/tlc-gh-installer.XXXXXX.pkg)
cleanup() {
    rm -f "$PKG_FILE"
}
trap cleanup EXIT INT TERM

# macOS doesn't ship with GNU `timeout` (it's part of coreutils). Provide a
# shim using perl's alarm(), which is bundled with the OS. Same usage:
# `timeout SECONDS command args...`. SIGALRM kills the process on expiry.
timeout() {
    perl -e 'alarm shift; exec @ARGV' "$@"
}

# --- Guard: pinned version already installed ---
if [ -x "$GH_BIN" ]; then
    INSTALLED=$("$GH_BIN" --version 2>/dev/null | grep -o 'gh version [0-9.]*' | awk '{print $3}' || echo "")
    if [ "$INSTALLED" = "$GH_VERSION" ]; then
        log "gh ${GH_VERSION} already installed at ${GH_BIN}. Nothing to do."
        rm -f "$LOG_FILE"
        exit 0
    fi
    log "gh ${INSTALLED:-unknown} found at ${GH_BIN}; pinned version is ${GH_VERSION}. Reinstalling."
fi

# Flag leftover Homebrew installs from the old install path — /opt/homebrew/bin
# usually precedes /usr/local/bin in brew-managed PATHs, so a stale brew gh
# would shadow this one in user shells.
if [ -x "/opt/homebrew/bin/gh" ]; then
    log "WARNING: Homebrew-installed gh found at /opt/homebrew/bin/gh. It may shadow ${GH_BIN} in user shells — remove it with 'brew uninstall gh'."
fi

log "Starting on ${HOSTNAME} (${SERIAL}). Downloading gh ${GH_VERSION} (10 min timeout)..."
if ! timeout 600 curl -fsSL -o "$PKG_FILE" "$PKG_URL" 2>&1 | tee -a "$LOG_FILE"; then
    log "ERROR: Download failed or timed out: ${PKG_URL}"
    exit 1
fi

# --- Verify checksum against the pinned SHA ---
# Pinning in the script (instead of fetching checksums.txt at runtime) means a
# tampered download can't pass silently — a hash change has to come through a
# reviewed PR.
ACTUAL_SHA=$(shasum -a 256 "$PKG_FILE" | awk '{print $1}')
if [ "$ACTUAL_SHA" != "$GH_SHA256" ]; then
    log "ERROR: Checksum mismatch. Expected ${GH_SHA256}, got ${ACTUAL_SHA}. Refusing to install."
    exit 1
fi
log "Checksum verified."

log "Installing (10 min timeout)..."
if ! timeout 600 installer -pkg "$PKG_FILE" -target / 2>&1 | tee -a "$LOG_FILE"; then
    log "ERROR: installer failed or timed out."
    exit 1
fi

# --- Verify ---
INSTALLED=$("$GH_BIN" --version 2>/dev/null | grep -o 'gh version [0-9.]*' | awk '{print $3}' || echo "")
if [ "$INSTALLED" = "$GH_VERSION" ]; then
    log "gh ${GH_VERSION} installed and verified at ${GH_BIN}."
    rm -f "$LOG_FILE"
    exit 0
else
    log "ERROR: Install appeared to complete but ${GH_BIN} reports '${INSTALLED:-nothing}'."
    exit 1
fi
