#!/bin/bash

# The Life Church — Xcode Command Line Tools Silent Install
# Deploy via Mosyle as a one-time or recurring script (run as root)
# Failures are captured in the log file and reflected in the exit code.
# curl -fsSL https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/xcode/install-clt.sh | bash

set -euo pipefail

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="/tmp/clt-install-${TIMESTAMP}.log"
HOSTNAME=$(scutil --get ComputerName 2>/dev/null || hostname)
SERIAL=$(ioreg -c IOPlatformExpertDevice -d 2 | awk -F\" '/IOPlatformSerialNumber/{print $4}')

log() {
    local msg="[CLT-INSTALL $(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$LOG_FILE"
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

log "Found package: ${PROD}. Installing..."
if ! softwareupdate -i "$PROD" --verbose 2>&1 | tee -a "$LOG_FILE"; then
    log "ERROR: softwareupdate exited with non-zero status."
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
