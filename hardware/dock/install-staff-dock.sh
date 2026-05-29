#!/bin/bash

# The Life Church — Staff Dock Bootstrap
# Deploy via Mosyle as a ONE-TIME script (run as root).
# curl -fsSL https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/hardware/dock/install-staff-dock.sh | bash
#
# Replaces the old .pkg installer. Pulls the runtime scripts + LaunchDaemon
# from this repo and the dockutil binary from its signed upstream release,
# then bootstraps the seeding daemon. No binary is vendored in this repo and
# nothing is version-pinned by filename — the daemon always runs latest main.

set -euo pipefail

RAW_BASE="https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/hardware/dock"

# Pinned dockutil release (signed Developer ID pkg, installs /usr/local/bin/dockutil).
DOCKUTIL_VERSION="3.1.3"
DOCKUTIL_PKG_URL="https://github.com/kcrawford/dockutil/releases/download/${DOCKUTIL_VERSION}/dockutil-${DOCKUTIL_VERSION}.pkg"

LIB_DIR="/usr/local/lib/tlc/dock"
BIN="/usr/local/bin/dockutil"
PLIST="/Library/LaunchDaemons/com.tlc.dock.seed.plist"
LABEL="com.tlc.dock.seed"

ATTEMPT_FILE="/var/tmp/tlc-dock-attempt-count.txt"
STATUS_FILE="/var/tmp/tlc-dock-status.txt"
DEFER_FILE="/var/tmp/tlc-dock-defer-count.txt"
# NOTE: the first-run reset marker (/var/tmp/tlc-dock-reset-done.txt) is deliberately
# NOT cleared here — re-running this bootstrap tops up missing apps without re-wiping
# a Dock the user may have customized. To force a full re-wipe, delete that marker first.

log() { echo "[dock-seed-bootstrap $(date '+%Y-%m-%d %H:%M:%S')] $1"; }

if [[ "$(id -u)" -ne 0 ]]; then
  log "ERROR: must run as root (deploy via Mosyle)."
  exit 1
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tlc-dock-seed.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

fetch() {  # fetch <url> <dest>  — atomic: download to temp, then move into place
  local url="$1" dest="$2" tmp
  tmp="$(mktemp "${TMP}/dl.XXXXXX")"
  if ! curl -fsSL "$url" -o "$tmp"; then
    log "ERROR: failed to download $url"
    return 1
  fi
  mv "$tmp" "$dest"
}

# --- dockutil: install from upstream signed pkg if missing or wrong version ---
need_dockutil=1
if [[ -x "$BIN" ]]; then
  current="$("$BIN" --version 2>/dev/null | tr -d '[:space:]')"
  if [[ "$current" == "$DOCKUTIL_VERSION" ]]; then
    need_dockutil=0
    log "dockutil $DOCKUTIL_VERSION already present."
  else
    log "dockutil version '$current' != pinned $DOCKUTIL_VERSION; reinstalling."
  fi
fi

if [[ "$need_dockutil" -eq 1 ]]; then
  log "Downloading dockutil $DOCKUTIL_VERSION from upstream release..."
  fetch "$DOCKUTIL_PKG_URL" "$TMP/dockutil.pkg"
  log "Installing dockutil pkg..."
  installer -pkg "$TMP/dockutil.pkg" -target / >/dev/null
  if [[ ! -x "$BIN" ]]; then
    log "ERROR: dockutil not present at $BIN after install."
    exit 1
  fi
fi

# --- Runtime scripts + LaunchDaemon ---
mkdir -p "$LIB_DIR"
log "Fetching runtime scripts and LaunchDaemon..."
fetch "$RAW_BASE/setup-dock.sh"    "$LIB_DIR/setup-dock.sh"
fetch "$RAW_BASE/report-status.sh" "$LIB_DIR/report-status.sh"
fetch "$RAW_BASE/com.tlc.dock.seed.plist" "$PLIST"

chmod 755 "$LIB_DIR/setup-dock.sh" "$LIB_DIR/report-status.sh" "$BIN"
chown root:wheel "$LIB_DIR/setup-dock.sh" "$LIB_DIR/report-status.sh" "$BIN" "$PLIST"
chmod 644 "$PLIST"

# --- Reset retry state so the daemon runs a clean cycle ---
rm -f "$ATTEMPT_FILE" "$STATUS_FILE" "$DEFER_FILE"

# --- (Re)bootstrap the LaunchDaemon ---
launchctl bootout system "$PLIST" >/dev/null 2>&1 || true
if ! launchctl bootstrap system "$PLIST"; then
  log "ERROR: failed to bootstrap LaunchDaemon $LABEL."
  exit 1
fi

log "Dock seed bootstrapped. Daemon $LABEL loaded; seeding will run shortly."
exit 0
