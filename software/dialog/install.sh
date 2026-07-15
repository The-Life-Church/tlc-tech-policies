#!/bin/bash

# The Life Church — swiftDialog Silent Install
#
# ===== Mosyle ================================================================
#   Paste-ready block: this folder's README.
#   Name: TLC swiftDialog — Silent Install · root · once or recurring · scope: Self-Service Macs
#   Installs: swiftDialog (/usr/local/bin/dialog + Dialog.app) only — the native
#   progress/notification UI used by software/selfservice/with-progress.sh
#   Note: usually arrives via the Self-Service wrapper's bootstrap instead
# =============================================================================
#
# Installs the pinned swiftDialog release from its official GitHub pkg.
# swiftDialog is the Mac-admin-standard UI tool for showing native dialogs and
# progress bars from management scripts — here it powers the Self-Service
# progress wrapper (software/selfservice/), so "Install Now" clicks show a
# live window instead of running silently.
#
# Pinning: version + build + SHA-256. Upstream publishes NO checksums file, so
# the SHA is computed by downloading the asset in CI (the ffmpeg pattern) —
# bumps arrive as PRs from the `dialog` job in bump-pins.yml (14-day cooldown).
# The pkg is also Developer ID-signed and notarized; this script verifies the
# signature and the signing team as a second integrity layer.
#
# Exit codes:
#   0 — pinned swiftDialog present (already, or installed now)
#   1 — download, checksum, signature, or install failure

set -euo pipefail

# --- Pinned release ----------------------------------------------------------
# Bump via the dialog job in bump-pins.yml. Asset: dialog-<ver>-<build>.pkg
DIALOG_VERSION="3.0.1"
DIALOG_BUILD="4955"
DIALOG_SHA256="8977a08d706a4615b6c48b6b47badf0fd61cd6c9904c7a4712aa4431c612f385"
# Developer ID team for swiftDialog's signing cert (CSIRO — Bart Reardon).
DIALOG_TEAM_ID="PWA5E9TQ59"
# ------------------------------------------------------------------------------

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="/tmp/dialog-install-${TIMESTAMP}.log"
HOSTNAME=$(scutil --get ComputerName 2>/dev/null || hostname)
SERIAL=$(ioreg -c IOPlatformExpertDevice -d 2 | awk -F\" '/IOPlatformSerialNumber/{print $4}')

log() {
    local msg="[DIALOG-INSTALL $(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$LOG_FILE"
}

# macOS ships no GNU `timeout`; shim it with perl's alarm() (bundled with the OS).
timeout() {
    perl -e 'alarm shift; exec @ARGV' "$@"
}

WORK_DIR=$(mktemp -d /tmp/tlc-dialog-installer.XXXXXX)
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT INT TERM

# --- Guard: must run as root (installer -target /) ---
if [ "$(id -u)" -ne 0 ]; then
    log "ERROR: must run as root (Mosyle default). Got uid $(id -u)."
    exit 1
fi

BIN="/usr/local/bin/dialog"

log "Starting on ${HOSTNAME} (${SERIAL}). Pin: ${DIALOG_VERSION} build ${DIALOG_BUILD}."

# --- Guard: swiftDialog 3.x requires macOS 15+ (upstream: use v2.5.6 below that) ---
# On older Macs this exits non-zero so Mosyle shows the gap; the Self-Service
# wrapper treats the failed bootstrap as "no UI" and installs silently — the
# designed degradation. If a macOS 13/14 cohort ever matters, pin v2.5.6 in a
# separate legacy path rather than loosening this pin.
OS_MAJOR=$(sw_vers -productVersion | cut -d. -f1)
if [ "$OS_MAJOR" -lt 15 ]; then
    log "ERROR: macOS ${OS_MAJOR} detected — swiftDialog ${DIALOG_VERSION} requires macOS 15+. Self-Service items will run silently on this Mac."
    exit 1
fi

# --- Idempotency: exact pinned version+build already installed? ---
# `dialog --version` prints version.build (e.g. 3.0.1.4955). Exact match so a
# build-only respin (or a stale older build) still converges — a bare version
# prefix would also wrongly match e.g. 3.0.10. If the output format ever
# changes, this degrades to reinstall-per-run: verify the no-op on a test Mac.
if [ -x "$BIN" ]; then
    INSTALLED=$("$BIN" --version 2>/dev/null | tr -d '[:space:]' || echo "")
    if [ "$INSTALLED" = "${DIALOG_VERSION}.${DIALOG_BUILD}" ]; then
        log "swiftDialog ${INSTALLED} already installed. Nothing to do."
        rm -f "$LOG_FILE"
        exit 0
    fi
    log "swiftDialog '${INSTALLED:-none}' found; pinned ${DIALOG_VERSION}.${DIALOG_BUILD}. Reinstalling."
fi

PKG_NAME="dialog-${DIALOG_VERSION}-${DIALOG_BUILD}.pkg"
PKG_URL="https://github.com/swiftDialog/swiftDialog/releases/download/v${DIALOG_VERSION}/${PKG_NAME}"
PKG_PATH="${WORK_DIR}/${PKG_NAME}"

# --- Download + verify (SHA pin, then signature + team as a second layer) ---
log "Downloading ${PKG_NAME} (5 min timeout)..."
if ! timeout 300 curl -fsSL -o "$PKG_PATH" "$PKG_URL" 2>&1 | tee -a "$LOG_FILE"; then
    log "ERROR: download failed from ${PKG_URL}."
    exit 1
fi

SHA_ACTUAL=$(shasum -a 256 "$PKG_PATH" | awk '{print $1}')
if [ "$SHA_ACTUAL" != "$DIALOG_SHA256" ]; then
    log "ERROR: checksum mismatch for ${PKG_NAME}."
    log "  expected: ${DIALOG_SHA256}"
    log "  actual:   ${SHA_ACTUAL}"
    log "Refusing to install."
    exit 1
fi
log "Checksum verified."

SIG=$(pkgutil --check-signature "$PKG_PATH" 2>&1 || true)
if ! echo "$SIG" | grep -q "signed by a developer certificate issued by Apple" || \
   ! echo "$SIG" | grep -q "$DIALOG_TEAM_ID"; then
    log "ERROR: pkg signature check failed or signing team is not ${DIALOG_TEAM_ID}."
    echo "$SIG" | tee -a "$LOG_FILE"
    exit 1
fi
log "Signature verified (Developer ID team ${DIALOG_TEAM_ID})."

# --- Install ---
log "Installing ${PKG_NAME}..."
if ! timeout 300 installer -pkg "$PKG_PATH" -target / 2>&1 | tee -a "$LOG_FILE"; then
    log "ERROR: installer failed for ${PKG_NAME}."
    exit 1
fi

# --- Verify it runs ---
if ! [ -x "$BIN" ] || ! "$BIN" --version >>"$LOG_FILE" 2>&1; then
    log "ERROR: dialog not runnable at ${BIN} after install."
    exit 1
fi

log "swiftDialog $("$BIN" --version 2>/dev/null | tr -d '[:space:]') installed."
rm -f "$LOG_FILE"
exit 0
