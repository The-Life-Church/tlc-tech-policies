#!/bin/bash

# The Life Church — Xcode Command Line Tools Silent Install
#
# ===== Mosyle ================================================================
#   Paste-ready block: this folder's README.
#   Name: TLC Xcode Command Line Tools — Silent Install · root · once or recurring
#   Scope: anyone needing git — vibe coders, devs, Claude Code desktop app users
#   Installs: Xcode Command Line Tools (git etc.) only; self-heals CLT broken by
#   macOS major upgrades (healthy machines exit 0 in under a second)
# =============================================================================
#
# Failures are captured in the log file and reflected in the exit code:
#   0 — CLT healthy (already installed, or installed successfully)
#   1 — install failed (download/install error, or still broken after install)
#   3 — software update catalog returned no CLT package (catalog parse breakage
#       or an MDM update deferral hiding the label — see README fallback)

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

CLT_PATH="/Library/Developer/CommandLineTools"
SENTINEL="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"

# Remove the sentinel on every exit path — success, error, or signal. With
# `set -euo pipefail` an early failure (e.g. catalog grep finding nothing)
# would otherwise leak it.
cleanup() {
    rm -f "$SENTINEL"
}
trap cleanup EXIT INT TERM

# --- Guard: healthy install already present ---
# `xcode-select -p` alone is not enough: macOS major upgrades leave the CLT
# directory (and the xcode-select pointer) in place while the tools inside go
# stale or break. Health = the selected developer dir's git actually runs.
# This also passes on machines with full Xcode selected instead of CLT.
DEV_DIR=$(xcode-select -p 2>/dev/null || echo "")
if [ -n "$DEV_DIR" ] && [ -x "${DEV_DIR}/usr/bin/git" ] && "${DEV_DIR}/usr/bin/git" --version &>/dev/null; then
    log "Developer tools healthy at ${DEV_DIR} ($("${DEV_DIR}/usr/bin/git" --version)). Nothing to do."
    rm -f "$LOG_FILE"
    exit 0
fi

# --- Stale install: clear it so softwareupdate offers a fresh package ---
if [ -n "$DEV_DIR" ]; then
    log "Developer dir present at ${DEV_DIR} but git is broken or missing (common after a macOS upgrade)."
    if [ "$DEV_DIR" = "$CLT_PATH" ] && [ -d "$CLT_PATH" ]; then
        log "Removing stale CLT at ${CLT_PATH} before reinstall."
        rm -rf "$CLT_PATH"
    else
        log "WARNING: Selected dir is not the CLT path (likely a broken Xcode install). Installing CLT anyway; the xcode-select pointer may need manual attention."
    fi
fi

log "Starting CLT install on ${HOSTNAME} (${SERIAL})."

# Signal softwareupdate to include CLT in the catalog
touch "$SENTINEL"

log "Searching software update catalog for CLT package..."
# Filter beta-seed lines before extracting the label, and `|| true` so an
# empty catalog falls through to the explicit exit-3 check instead of dying
# silently under pipefail.
PROD=$(softwareupdate -l 2>&1 | grep 'Command Line Tools' | grep -vi 'beta' | grep -o 'Command Line Tools for Xcode-[0-9.]*' | sort -V | tail -1 || true)

if [ -z "$PROD" ]; then
    log "ERROR: No CLT package found in software update catalog. Apple may have changed the 'softwareupdate -l' output format, or an MDM software-update deferral is hiding the label. Fallback: push Apple's CLT .pkg directly (see README)."
    exit 3
fi

log "Found package: ${PROD}. Installing (30 min timeout)..."
# Cap softwareupdate at 30 min — Apple's CDN occasionally hangs.
# timeout exits 124 on timeout; pipefail surfaces that through the pipeline.
if ! timeout 1800 softwareupdate -i "$PROD" --verbose 2>&1 | tee -a "$LOG_FILE"; then
    log "ERROR: softwareupdate failed or timed out."
    exit 1
fi

# --- Verify: same functional check as the guard, not just path presence ---
if [ -x "${CLT_PATH}/usr/bin/git" ] && "${CLT_PATH}/usr/bin/git" --version &>/dev/null; then
    log "CLT installed and verified at ${CLT_PATH} ($("${CLT_PATH}/usr/bin/git" --version))."
    rm -f "$LOG_FILE"
    exit 0
else
    log "ERROR: Install appeared to complete but git at ${CLT_PATH} is missing or broken."
    exit 1
fi
