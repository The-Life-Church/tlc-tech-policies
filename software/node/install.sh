#!/bin/bash

# The Life Church — Node.js Silent Install
#
# ===== What to put in Mosyle =================================================
#   Mosyle -> Scripts (Custom Command) -> new shell script
#     Name:   TLC Node.js — Silent Install
#     Run:    Once or recurring     As: root     Scope: IT-dev / vibe coders
#             (NOT fleet-wide — the Claude Code desktop app does not need Node;
#             only machines running node tooling or npx do)
#     Script:
#       #!/bin/bash
#       curl -fsSL https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/node/install.sh | bash
# =============================================================================
#
# Installs the official Node.js LTS universal .pkg (arm64 + x64) from
# nodejs.org. Lands node/npm/npx in /usr/local/bin, system-wide, root-friendly.
# Version and SHA-256 are pinned below; bumping Node is a two-line PR (devices
# converge on the next recurring run). Failures are captured in the log file
# and reflected in the exit code:
#   0 — Node present at the pinned version (already installed, or installed now)
#   1 — download, checksum, or install failure

set -euo pipefail

# --- Pinned release ----------------------------------------------------------
# Update both lines together. Pick the current LTS from https://nodejs.org/dist/
# and copy the .pkg line from https://nodejs.org/dist/<ver>/SHASUMS256.txt
NODE_VERSION="v24.16.0"
NODE_SHA256="65843aafbab48999c9d5f072746836965340c9ef2fbf17a377d3f919dcb0cb7a"
# ------------------------------------------------------------------------------

PKG_URL="https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}.pkg"
NODE_BIN="/usr/local/bin/node"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="/tmp/node-install-${TIMESTAMP}.log"
HOSTNAME=$(scutil --get ComputerName 2>/dev/null || hostname)
SERIAL=$(ioreg -c IOPlatformExpertDevice -d 2 | awk -F\" '/IOPlatformSerialNumber/{print $4}')

log() {
    local msg="[NODE-INSTALL $(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$LOG_FILE"
}

PKG_FILE=$(mktemp /tmp/tlc-node-installer.XXXXXX.pkg)
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
if [ -x "$NODE_BIN" ]; then
    INSTALLED=$("$NODE_BIN" --version 2>/dev/null || echo "")
    if [ "$INSTALLED" = "$NODE_VERSION" ]; then
        log "Node ${NODE_VERSION} already installed at ${NODE_BIN}. Nothing to do."
        rm -f "$LOG_FILE"
        exit 0
    fi
    log "Node ${INSTALLED:-unknown} found at ${NODE_BIN}; pinned version is ${NODE_VERSION}. Reinstalling."
fi

# Flag per-user Node installs that would shadow this one in user shells
# (brew's /opt/homebrew/bin precedes /usr/local/bin in brew-managed PATHs;
# nvm prepends its own dir). Informational only — the system install still
# proceeds so root/MDM contexts always have a known Node.
if [ -x "/opt/homebrew/bin/node" ]; then
    log "WARNING: Homebrew-installed node found at /opt/homebrew/bin/node — it may shadow ${NODE_BIN} in user shells."
fi

log "Starting on ${HOSTNAME} (${SERIAL}). Downloading Node ${NODE_VERSION} (15 min timeout)..."
if ! timeout 900 curl -fsSL -o "$PKG_FILE" "$PKG_URL" 2>&1 | tee -a "$LOG_FILE"; then
    log "ERROR: Download failed or timed out: ${PKG_URL}"
    exit 1
fi

# --- Verify checksum against the pinned SHA ---
# Pinning in the script (instead of fetching SHASUMS256.txt at runtime) means
# a compromised download can't pass silently — a hash change has to come
# through a reviewed PR.
ACTUAL_SHA=$(shasum -a 256 "$PKG_FILE" | awk '{print $1}')
if [ "$ACTUAL_SHA" != "$NODE_SHA256" ]; then
    log "ERROR: Checksum mismatch. Expected ${NODE_SHA256}, got ${ACTUAL_SHA}. Refusing to install."
    exit 1
fi
log "Checksum verified."

log "Installing (15 min timeout)..."
if ! timeout 900 installer -pkg "$PKG_FILE" -target / 2>&1 | tee -a "$LOG_FILE"; then
    log "ERROR: installer failed or timed out."
    exit 1
fi

# --- Verify ---
INSTALLED=$("$NODE_BIN" --version 2>/dev/null || echo "")
if [ "$INSTALLED" = "$NODE_VERSION" ]; then
    NPX_VERSION=$(/usr/local/bin/npx --version 2>/dev/null || echo "missing")
    log "Node ${NODE_VERSION} installed and verified at ${NODE_BIN} (npx ${NPX_VERSION})."
    rm -f "$LOG_FILE"
    exit 0
else
    log "ERROR: Install appeared to complete but ${NODE_BIN} reports '${INSTALLED:-nothing}'."
    exit 1
fi
