#!/bin/bash

# The Life Church — Higgsfield CLI Silent Install
#
# ===== Mosyle ================================================================
#   Paste-ready block: this folder's README (Deployment/Mosyle section).
#   Name: TLC Higgsfield CLI — Silent Install · root · once or recurring · scope: creative / IT-dev (opt-in)
#   Installs: Higgsfield CLI (higgsfield + higgs) only (pinned; nothing else)
# =============================================================================
#
# Installs the Higgsfield CLI from the official GitHub release tarball — no
# Homebrew, no console-user dance, runs cleanly as root. The release ships a
# bare unsigned binary, so the pinned per-arch SHA-256 below is the only
# integrity check — never remove it. Version and SHAs are pinned together;
# bumping is a three-line PR (devices converge on the next recurring run).
#
# Installs /usr/local/bin/higgsfield plus a `higgs` symlink. Deliberately does
# NOT install upstream's optional `hf` shortcut — it collides with the Hugging
# Face CLI.
#
# Auth note: the binary is fleet-installed, but each user signs in themselves
# with `higgsfield auth login` (interactive device flow, org Higgsfield
# workspace). No keys, no secrets in this script.
#
# Exit codes:
#   0 — higgsfield present at the pinned version (already installed, or installed now)
#   1 — download, checksum, or install failure

set -euo pipefail

# --- Pinned release ----------------------------------------------------------
# Update all three lines together. SHAs come from checksums.txt on the
# release page: https://github.com/higgsfield-ai/cli/releases
HIGGSFIELD_VERSION="0.1.40"
HIGGSFIELD_SHA256_ARM64="17209e0ac15e9123f700ee16882f49469372e9e5c399a607227994d91943366e"
HIGGSFIELD_SHA256_AMD64="571f5dbb97db333f053b04d0cca4478cd97dce8548d9fccb57d7a3432f48b572"
# ------------------------------------------------------------------------------

ARCH=$(uname -m)
case "$ARCH" in
    arm64)  TARBALL_ARCH="arm64"; PIN_SHA="$HIGGSFIELD_SHA256_ARM64" ;;
    x86_64) TARBALL_ARCH="amd64"; PIN_SHA="$HIGGSFIELD_SHA256_AMD64" ;;
    *) echo "ERROR: unsupported architecture: ${ARCH}"; exit 1 ;;
esac

TARBALL="hf_${HIGGSFIELD_VERSION}_darwin_${TARBALL_ARCH}.tar.gz"
TARBALL_URL="https://github.com/higgsfield-ai/cli/releases/download/v${HIGGSFIELD_VERSION}/${TARBALL}"
BIN_DIR="/usr/local/bin"
HF_BIN="${BIN_DIR}/higgsfield"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="/tmp/higgsfield-install-${TIMESTAMP}.log"
HOSTNAME=$(scutil --get ComputerName 2>/dev/null || hostname)
SERIAL=$(ioreg -c IOPlatformExpertDevice -d 2 | awk -F\" '/IOPlatformSerialNumber/{print $4}')

log() {
    local msg="[HIGGSFIELD-INSTALL $(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$LOG_FILE"
}

WORK_DIR=$(mktemp -d /tmp/tlc-higgsfield-installer.XXXXXX)
cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT INT TERM

# macOS doesn't ship with GNU `timeout` (it's part of coreutils). Provide a
# shim using perl's alarm(), which is bundled with the OS. Same usage:
# `timeout SECONDS command args...`. SIGALRM kills the process on expiry.
timeout() {
    perl -e 'alarm shift; exec @ARGV' "$@"
}

installed_version() {
    # Output format (verified against v0.1.40):
    #   higgsfield 0.1.40 (<commit-sha>) built 2026-05-12T11:19:03Z
    # First x.y.z match is the version (hash is dotless hex; timestamp has no dots).
    "$HF_BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo ""
}

# --- Guard: pinned version already installed ---
if [ -x "$HF_BIN" ]; then
    INSTALLED=$(installed_version)
    if [ "$INSTALLED" = "$HIGGSFIELD_VERSION" ]; then
        log "higgsfield ${HIGGSFIELD_VERSION} already installed at ${HF_BIN}. Nothing to do."
        rm -f "$LOG_FILE"
        exit 0
    fi
    log "higgsfield ${INSTALLED:-unknown} found at ${HF_BIN}; pinned version is ${HIGGSFIELD_VERSION}. Reinstalling."
fi

log "Starting on ${HOSTNAME} (${SERIAL}). Downloading higgsfield ${HIGGSFIELD_VERSION} (${TARBALL_ARCH}, 10 min timeout)..."
if ! timeout 600 curl -fsSL -o "${WORK_DIR}/${TARBALL}" "$TARBALL_URL" 2>&1 | tee -a "$LOG_FILE"; then
    log "ERROR: Download failed or timed out: ${TARBALL_URL}"
    exit 1
fi

# --- Verify checksum against the pinned SHA ---
# Pinning in the script (instead of fetching checksums.txt at runtime) means a
# tampered download can't pass silently — a hash change has to come through a
# reviewed PR.
ACTUAL_SHA=$(shasum -a 256 "${WORK_DIR}/${TARBALL}" | awk '{print $1}')
if [ "$ACTUAL_SHA" != "$PIN_SHA" ]; then
    log "ERROR: Checksum mismatch. Expected ${PIN_SHA}, got ${ACTUAL_SHA}. Refusing to install."
    exit 1
fi
log "Checksum verified."

# --- Extract and install ---
# The tarball contains a single binary named `hf`. Install it as `higgsfield`
# with a `higgs` symlink (mirrors upstream's installer, minus the `hf`
# shortcut, which collides with the Hugging Face CLI).
tar -xzf "${WORK_DIR}/${TARBALL}" -C "$WORK_DIR"
if [ ! -f "${WORK_DIR}/hf" ]; then
    log "ERROR: tarball did not contain the expected 'hf' binary. Upstream layout changed — review before bumping."
    exit 1
fi
mkdir -p "$BIN_DIR"
install -m 0755 "${WORK_DIR}/hf" "$HF_BIN"
ln -sf "$HF_BIN" "${BIN_DIR}/higgs"

# Clear quarantine if curl/tar picked it up. Verified: curl downloads don't
# set com.apple.quarantine (only com.apple.provenance), so this is a no-op
# today — kept as insurance against future download-path changes.
xattr -d com.apple.quarantine "$HF_BIN" 2>/dev/null || true

# --- Verify ---
INSTALLED=$(installed_version)
if [ "$INSTALLED" = "$HIGGSFIELD_VERSION" ]; then
    log "higgsfield ${HIGGSFIELD_VERSION} installed and verified at ${HF_BIN}."
    rm -f "$LOG_FILE"
    exit 0
else
    log "ERROR: Install appeared to complete but ${HF_BIN} reports '${INSTALLED:-nothing}'."
    exit 1
fi
