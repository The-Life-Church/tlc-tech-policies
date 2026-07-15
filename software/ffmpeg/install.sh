#!/bin/bash

# The Life Church — FFmpeg (static) Silent Install
#
# ===== Mosyle ================================================================
#   Paste-ready block: this folder's README (Deployment/Mosyle section).
#   Name: TLC FFmpeg (static) — Silent Install · root · once or recurring · scope: creative / IT-dev (opt-in)
#   Installs: ffmpeg + ffprobe static binaries only (pinned per-arch SHAs)
#   Note: usually arrives via the HyperFrames one-stop script instead
# =============================================================================
#
# Installs pinned static `ffmpeg` + `ffprobe` binaries to /usr/local/bin — the
# encode/probe half of the HyperFrames toolchain (software/hyperframes). Runs
# cleanly as root — no Homebrew, no console-user dance.
#
# Source is the GitHub releases of eugeneware/ffmpeg-static, which publishes
# per-arch macOS binaries (ffmpeg-darwin-arm64 / ffmpeg-darwin-x64). The assets
# are bare, UNSIGNED Mach-O binaries and upstream ships NO checksums file — so
# the pinned per-arch SHA-256 below (computed from the release artifact and
# reviewed into this script) is the only integrity check. Never remove it.
# Version + both SHAs are pinned together; bumping is a reviewed PR from the
# ffmpeg job in bump-pins.yml (devices converge on the next recurring run).
#
# Idempotency is by SHA, not by version string: the installed binary's SHA-256
# is compared to the pin. `ffmpeg -version`'s exact text is not relied on for
# the "already installed" check (static builds vary), only as a post-install
# smoke test that the binary executes.
#
# ffprobe IS installed alongside ffmpeg: HyperFrames requires it to probe media
# assets (durations/dimensions of audio/video inputs), per `hyperframes doctor`.
#
# Exit codes:
#   0 — ffmpeg + ffprobe present at the pinned build (already installed, or now)
#   1 — download, checksum, or install failure (or unsupported arch / not root)

set -euo pipefail

# --- Pinned release ----------------------------------------------------------
# FFMPEG_VERSION is the eugeneware/ffmpeg-static *package* release — the GitHub
# tag is b<version> (e.g. b6.1.1). This is NOT the ffmpeg version: ffmpeg-static
# carries its own semver, and b6.1.1 bundles ffmpeg 6.0 (fine for HyperFrames).
# The pin/URL/bump job all key on the package release; the actual ffmpeg version
# is whatever that release ships. Upstream publishes no checksums file; the SHAs
# below were computed from the release assets. Update the version + all four
# SHAs together via the ffmpeg job in bump-pins.yml (or manually — see README).
FFMPEG_VERSION="6.1.1"
FFMPEG_SHA256_ARM64="a90e3db6a3fd35f6074b013f948b1aa45b31c6375489d39e572bea3f18336584"
FFMPEG_SHA256_AMD64="ebdddc936f61e14049a2d4b549a412b8a40deeff6540e58a9f2a2da9e6b18894"
# ffprobe ships in the same release (HyperFrames requires it — see above).
FFPROBE_SHA256_ARM64="bb2db6f5d8cef919da12fbf592119a987202a8c060a886f3cab091f9cab90b64"
FFPROBE_SHA256_AMD64="fa3add0ce901f7241abe0dfc0155d958fc834aca3f8ce61f87cc712ae669c1e0"
# ------------------------------------------------------------------------------

ARCH=$(uname -m)
case "$ARCH" in
    arm64)  BIN_ARCH="arm64"; FFMPEG_PIN_SHA="$FFMPEG_SHA256_ARM64"; FFPROBE_PIN_SHA="$FFPROBE_SHA256_ARM64" ;;
    x86_64) BIN_ARCH="x64";   FFMPEG_PIN_SHA="$FFMPEG_SHA256_AMD64"; FFPROBE_PIN_SHA="$FFPROBE_SHA256_AMD64" ;;
    *) echo "ERROR: unsupported architecture: ${ARCH}"; exit 1 ;;
esac

RELEASE_TAG="b${FFMPEG_VERSION}"
BASE_URL="https://github.com/eugeneware/ffmpeg-static/releases/download/${RELEASE_TAG}"
BIN_DIR="/usr/local/bin"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="/tmp/ffmpeg-install-${TIMESTAMP}.log"
HOSTNAME=$(scutil --get ComputerName 2>/dev/null || hostname)
SERIAL=$(ioreg -c IOPlatformExpertDevice -d 2 | awk -F\" '/IOPlatformSerialNumber/{print $4}')

log() {
    local msg="[FFMPEG-INSTALL $(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$LOG_FILE"
}

WORK_DIR=$(mktemp -d /tmp/tlc-ffmpeg-installer.XXXXXX)
cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT INT TERM

# macOS doesn't ship GNU `timeout` (coreutils). Shim it with perl's alarm(),
# bundled with the OS. Usage: `timeout SECONDS command args...`.
timeout() {
    perl -e 'alarm shift; exec @ARGV' "$@"
}

# --- Guard: must run as root (writes to /usr/local/bin) ---
if [ "$(id -u)" -ne 0 ]; then
    log "ERROR: must run as root (Mosyle default). Got uid $(id -u)."
    exit 1
fi

export PATH="/usr/local/bin:${PATH}"

# --- Per-binary fetch/verify/install helper ---------------------------------
# ffmpeg and ffprobe are both bare Mach-O binaries in the same release. Each is
# idempotent by SHA: if the installed binary already matches its pin it's a
# no-op; otherwise download -> verify pinned SHA -> Mach-O sanity -> install.
# Pinning the SHA in-script (upstream publishes none) means a tampered download
# can't pass silently — a hash change must come through a reviewed PR.
# NOTE: called as `fetch_verify_install ... || exit 1`, which disables `set -e`
# inside the function, so every failure path returns explicitly.
fetch_verify_install() {
    local name="$1" pin_sha="$2"
    local asset="${name}-darwin-${BIN_ARCH}"
    local dest="${BIN_DIR}/${name}"
    local cur_sha actual_sha installed_sha

    if [ -x "$dest" ]; then
        cur_sha=$(shasum -a 256 "$dest" | awk '{print $1}')
        if [ "$cur_sha" = "$pin_sha" ]; then
            log "${name} matching pinned SHA already installed at ${dest}."
            return 0
        fi
        log "${name} at ${dest} differs from pin (installed ${cur_sha:0:12}...); reinstalling."
    fi

    log "Downloading ${asset} (10 min timeout)..."
    if ! timeout 600 curl -fsSL -o "${WORK_DIR}/${asset}" "${BASE_URL}/${asset}" 2>&1 | tee -a "$LOG_FILE"; then
        log "ERROR: download failed or timed out: ${BASE_URL}/${asset}"
        return 1
    fi

    actual_sha=$(shasum -a 256 "${WORK_DIR}/${asset}" | awk '{print $1}')
    if [ "$actual_sha" != "$pin_sha" ]; then
        log "ERROR: ${name} checksum mismatch. Expected ${pin_sha}, got ${actual_sha}. Refusing to install."
        return 1
    fi
    if ! file "${WORK_DIR}/${asset}" | grep -q 'Mach-O'; then
        log "ERROR: ${asset} is not a Mach-O binary — upstream asset layout changed. Review before bumping."
        return 1
    fi

    mkdir -p "$BIN_DIR"
    if ! install -m 0755 "${WORK_DIR}/${asset}" "$dest"; then
        log "ERROR: failed to install ${name} to ${dest}."
        return 1
    fi
    # Clear quarantine if the download path set it (curl typically sets only
    # com.apple.provenance, so this is usually a no-op — kept as insurance).
    xattr -d com.apple.quarantine "$dest" 2>/dev/null || true

    installed_sha=$(shasum -a 256 "$dest" | awk '{print $1}')
    if [ "$installed_sha" != "$pin_sha" ]; then
        log "ERROR: post-install SHA mismatch at ${dest} (got ${installed_sha})."
        return 1
    fi
    log "${name} installed at ${dest}."
    return 0
}

log "Starting on ${HOSTNAME} (${SERIAL}). ffmpeg-static ${FFMPEG_VERSION} (${BIN_ARCH})."

# ffmpeg (encoder) + ffprobe (media probing — HyperFrames requires it).
fetch_verify_install "ffmpeg"  "$FFMPEG_PIN_SHA"  || exit 1
fetch_verify_install "ffprobe" "$FFPROBE_PIN_SHA" || exit 1

# --- Smoke test: both binaries execute ---
if ! timeout 60 "${BIN_DIR}/ffmpeg" -version 2>/dev/null | grep -q '^ffmpeg version'; then
    log "ERROR: ffmpeg installed but failed to run (-version)."
    exit 1
fi
if ! timeout 60 "${BIN_DIR}/ffprobe" -version 2>/dev/null | grep -q '^ffprobe version'; then
    log "ERROR: ffprobe installed but failed to run (-version)."
    exit 1
fi

log "ffmpeg-static ${FFMPEG_VERSION} ready at ${BIN_DIR}: $("${BIN_DIR}/ffmpeg" -version 2>/dev/null | head -1) + ffprobe."
rm -f "$LOG_FILE"
exit 0
