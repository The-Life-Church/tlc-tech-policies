#!/bin/bash

# The Life Church — Self-Service progress wrapper
#
# ===== Mosyle ================================================================
#   Paste-ready per-tool blocks: this folder's README (and each tool's README).
#   Used ONLY by Self-Service catalog items — recurring/remote deployments keep
#   calling the tool installers directly and stay silent. The dialog is
#   triggered by the entry point, never by the installers themselves.
#   Usage: curl .../with-progress.sh | bash -s -- <tool> "<Display Name>"
# =============================================================================
#
# Wraps any fleet installer with a native progress window (swiftDialog) so a
# Self-Service "Install Now" click shows immediate feedback, live step text
# while it works, and an unambiguous success/failure ending — instead of
# running invisibly in the background.
#
# Design rules:
#   - The wrapped installers are UNCHANGED — this script downloads and runs
#     the same software/<tool>/install.sh the silent entries use, and streams
#     its log lines into the dialog as progress text.
#   - Degrades to a plain silent run whenever UI isn't possible: nobody at the
#     console, or swiftDialog missing and its bootstrap fails. The install
#     always proceeds; the window is presentation only.
#   - The installer's exit code passes through untouched, so Mosyle's
#     success/failure indicator for the Self-Service item keeps working.
#   - Known tools only (allowlist below) — the wrapper won't fetch arbitrary
#     paths.
#
# Exit codes: whatever the wrapped installer exits with (1 for wrapper-level
# failures: unknown tool, download failure).

set -euo pipefail

RAW="https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main"
DIALOG_INSTALLER_URL="${RAW}/software/dialog/install.sh"
DIALOG_BIN="/usr/local/bin/dialog"

TOOL="${1:-}"
NAME="${2:-$TOOL}"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="/tmp/selfservice-${TOOL:-unknown}-${TIMESTAMP}.log"

log() {
    local msg="[SELF-SERVICE $(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$LOG_FILE"
}

# macOS ships no GNU `timeout`; shim it with perl's alarm() (bundled with the OS).
timeout() {
    perl -e 'alarm shift; exec @ARGV' "$@"
}

WORK_DIR=$(mktemp -d /tmp/tlc-selfservice.XXXXXX)
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT INT TERM

# --- Guard: must run as root (the wrapped installers require it) ---
if [ "$(id -u)" -ne 0 ]; then
    log "ERROR: must run as root (Mosyle default). Got uid $(id -u)."
    exit 1
fi

# --- Tool allowlist: slug -> installer path in this repo ---
case "$TOOL" in
    firebase-tools|hyperframes|gh|node|java|ffmpeg|higgsfield)
        SCRIPT_PATH="software/${TOOL}/install.sh" ;;
    xcode)
        SCRIPT_PATH="software/xcode/install-clt.sh" ;;
    staff-dock)
        SCRIPT_PATH="hardware/dock/install-staff-dock.sh" ;;
    *)
        log "ERROR: unknown tool '${TOOL}'. Usage: with-progress.sh <tool> \"<Display Name>\""
        exit 1 ;;
esac

log "Self-Service install: ${NAME} (${SCRIPT_PATH})."

# --- Fetch the real installer (same file the silent entries run) ---
if ! timeout 120 curl -fsSL -o "${WORK_DIR}/tool-install.sh" "${RAW}/${SCRIPT_PATH}" 2>&1 | tee -a "$LOG_FILE"; then
    log "ERROR: failed to download ${SCRIPT_PATH}."
    exit 1
fi

# --- Decide whether UI is possible ---
UI="yes"
CONSOLE_USER=$(stat -f%Su /dev/console 2>/dev/null || echo "")
if [ -z "$CONSOLE_USER" ] || [ "$CONSOLE_USER" = "root" ] || [ "$CONSOLE_USER" = "loginwindow" ]; then
    UI="no"
    log "No console user — running silently (no dialog)."
fi

if [ "$UI" = "yes" ] && [ ! -x "$DIALOG_BIN" ]; then
    log "swiftDialog not present — bootstrapping software/dialog..."
    if ! { timeout 120 curl -fsSL -o "${WORK_DIR}/dialog-install.sh" "$DIALOG_INSTALLER_URL" && \
           bash "${WORK_DIR}/dialog-install.sh"; } 2>&1 | tee -a "$LOG_FILE"; then
        UI="no"
        log "WARN: swiftDialog bootstrap failed — proceeding silently; the install is unaffected."
    fi
fi
[ "$UI" = "yes" ] && [ ! -x "$DIALOG_BIN" ] && UI="no"

# --- Launch the dialog (as the console user, so it renders in their session) ---
# The command file must be root-created at an UNPREDICTABLE path: a fixed name
# in world-writable /var/tmp could be pre-created by a local user as a symlink,
# and a root-side truncate/chmod would then follow it into root-owned files.
# mktemp -d gives a fresh root-owned dir (contents writable only by root);
# 755/644 lets the console user's dialog process read it. Old dirs are swept
# here (rm on a planted symlink removes the link, never the target) — the dir
# outlives the script on purpose, since the dialog polls it until dismissed.
CMD_FILE=""
dlg() { [ "$UI" = "yes" ] && echo "$1" >> "$CMD_FILE" || true; }

if [ "$UI" = "yes" ]; then
    rm -rf /var/tmp/tlc-dialog.* 2>/dev/null || true
    CMD_DIR=$(mktemp -d /var/tmp/tlc-dialog.XXXXXX)
    chmod 755 "$CMD_DIR"
    CMD_FILE="${CMD_DIR}/dialog.cmd"
    : > "$CMD_FILE"
    chmod 644 "$CMD_FILE"
    CONSOLE_UID=$(id -u "$CONSOLE_USER")
    launchctl asuser "$CONSOLE_UID" sudo -u "$CONSOLE_USER" nohup "$DIALOG_BIN" \
        --title "Installing ${NAME}" \
        --message "Getting things ready — this can take a few minutes. You can keep working; we'll let you know when it's done." \
        --icon "SF=arrow.down.circle.fill,colour=blue" \
        --progress 100 \
        --progresstext "Starting…" \
        --button1text "Please wait…" \
        --button1disabled \
        --commandfile "$CMD_FILE" \
        --ontop --moveable --small >/dev/null 2>&1 &
    disown || true
    log "Dialog launched for ${CONSOLE_USER}."
fi

# --- Run the installer, streaming its log lines into the dialog ---
# Mosyle still gets every line on stdout; the dialog gets a trimmed copy as
# progress text, with the bar nudged forward per step (capped so it never
# fakes completion).
set +e
bash "${WORK_DIR}/tool-install.sh" 2>&1 | {
    pct=5
    while IFS= read -r line; do
        echo "$line"
        printf '%s\n' "$line" >> "$LOG_FILE"
        short=$(printf '%s' "$line" | sed -E 's/^\[[A-Z-]+ [0-9: -]+\] //' | cut -c1-110)
        if [ -n "$short" ]; then
            dlg "progresstext: ${short}"
            if [ "$pct" -lt 90 ]; then pct=$((pct + 2)); dlg "progress: ${pct}"; fi
        fi
    done
}
RC=${PIPESTATUS[0]}
set -e

# --- End state: unambiguous success or failure ---
if [ "$RC" -eq 0 ]; then
    dlg "progress: 100"
    dlg "icon: SF=checkmark.circle.fill,colour=green"
    dlg "progresstext: Done"
    dlg "message: **${NAME} is installed.** You're good to go."
    dlg "button1text: Done"
    dlg "button1: enable"
    log "${NAME} installed successfully."
    rm -f "$LOG_FILE"
else
    dlg "icon: SF=exclamationmark.triangle.fill,colour=orange"
    dlg "progresstext: Something needs attention"
    dlg "message: **${NAME} didn't finish installing.** No harm done — IT can sort it out. Mention this log when you reach out: \`${LOG_FILE}\` — staff.thelifechurch.com"
    dlg "button1text: Close"
    dlg "button1: enable"
    log "ERROR: ${NAME} installer exited ${RC}. Log kept at ${LOG_FILE}."
fi

exit "$RC"
