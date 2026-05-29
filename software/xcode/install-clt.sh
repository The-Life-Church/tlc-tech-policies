#!/bin/bash

# The Life Church — Xcode Command Line Tools Silent Install
#
# ===== What to put in Mosyle =================================================
#   Mosyle -> Scripts (Custom Command) -> new shell script
#     Name:   TLC Xcode Command Line Tools — Silent Install
#     Run:    Once or recurring     As: root     Scope: any group needing CLT (vibe coders, devs)
#     Script:
#       #!/bin/bash
#       curl -fsSL https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/xcode/install-clt.sh | bash
# =============================================================================
#
# Failures are captured in the log file and reflected in the exit code.

set -euo pipefail

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="/tmp/clt-install-${TIMESTAMP}.log"
HOSTNAME=$(scutil --get ComputerName 2>/dev/null || hostname)
SERIAL=$(ioreg -c IOPlatformExpertDevice -d 2 | awk -F\" '/IOPlatformSerialNumber/{print $4}')

log() {
    local msg="[CLT-INSTALL $(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$LOG_FILE"
}

# macOS doesn't ship with GNU `timeout` (it's part of coreutils). Provide a
# shim using perl's alarm(), which is bundled with the OS. Same usage:
# `timeout SECONDS command args...`. SIGALRM kills the process on expiry.
timeout() {
    perl -e 'alarm shift; exec @ARGV' "$@"
}

# --- Guard: already installed ---
if xcode-select -p &>/dev/null; then
    log "CLT already installed at $(xcode-select -p). Nothing to do."
    rm -f "$LOG_FILE"
    exit 0
fi

log "CLT not found. Starting install on ${HOSTNAME} (${SERIAL})."

# Signal softwareupdate to include CLT in the catalog
touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

log "Searching software update catalog for CLT package..."
PROD=$(softwareupdate -l 2>&1 | grep -o 'Command Line Tools for Xcode-[0-9.]*' | sort -V | tail -1)

if [ -z "$PROD" ]; then
    log "ERROR: No CLT package found in software update catalog."
    rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    exit 1
fi

log "Found package: ${PROD}. Installing (30 min timeout)..."
# Cap softwareupdate at 30 min — Apple's CDN occasionally hangs.
# timeout exits 124 on timeout; pipefail surfaces that through the pipeline.
if ! timeout 1800 softwareupdate -i "$PROD" --verbose 2>&1 | tee -a "$LOG_FILE"; then
    log "ERROR: softwareupdate failed or timed out."
    rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    exit 1
fi

rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

# --- Verify ---
if xcode-select -p &>/dev/null; then
    log "CLT installed successfully at $(xcode-select -p)."
    rm -f "$LOG_FILE"
    exit 0
else
    log "ERROR: Install appeared to complete but xcode-select -p still fails."
    exit 1
fi
