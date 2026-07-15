#!/bin/bash

# The Life Church — Claude Code Status Line Install (per-user)
#
# ===== Mosyle ================================================================
#   Paste-ready block: this folder's README.
#   Name: TLC Claude Code Status Line — Install · root (drops to console user) · recurring
#   Scope: Node-bearing Claude Code users (the status line runs node)
#   Installs: the custom status line into the console user's ~/.claude — nothing else
# =============================================================================
#
# Places statusline.js at ~/.claude/statusline.js for the logged-in console
# user and MERGES the `statusLine` key into their ~/.claude/settings.json
# without touching their other settings. Per-user, like the Claude Code binary
# install — Mosyle runs as root, so this drops to the console user.
#
# Hard dependency: Node.js. The status line is `node ~/.claude/statusline.js`,
# and this installer uses `node` to merge settings.json. If Node isn't present
# for the user, the script exits non-zero pointing at the Node installer —
# scope this script to the same machines that get software/node/install.sh.
#
# Idempotent: re-copies the (possibly updated) script each run and re-asserts
# the settings key. Safe on a recurring schedule.
#
# Exit codes:
#   0 — status line installed/refreshed for the console user
#   1 — no real console user, Node missing, download failure, or unparseable
#       existing settings.json (refused rather than clobber)

set -euo pipefail

RAW_BASE="https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/claude/statusline"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="/tmp/statusline-install-${TIMESTAMP}.log"
HOSTNAME=$(scutil --get ComputerName 2>/dev/null || hostname)

log() {
    local msg="[STATUSLINE-INSTALL $(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$LOG_FILE"
}

timeout() {
    perl -e 'alarm shift; exec @ARGV' "$@"
}

WORK_DIR=$(mktemp -d /tmp/tlc-statusline.XXXXXX)
# `mktemp -d` makes the dir mode 0700 owned by root. We later drop to the
# console user to run the merge script that lives in here — a 0700 root dir
# isn't traversable by them, so node would fail MODULE_NOT_FOUND. Open the
# dir so the dropped user can read its (non-sensitive) contents. No secrets
# live here — only the fetched statusline.js and the merge script.
chmod 0755 "$WORK_DIR"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT INT TERM

# --- Identify the console user ---
CONSOLE_USER=$(stat -f%Su /dev/console 2>/dev/null || echo "")
if [ -z "$CONSOLE_USER" ] || [ "$CONSOLE_USER" = "root" ] || [ "$CONSOLE_USER" = "_mbsetupuser" ]; then
    log "ERROR: No real console user logged in (got '${CONSOLE_USER}'). Nothing to do."
    exit 1
fi

USER_HOME=$(dscl . -read "/Users/${CONSOLE_USER}" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
if [ -z "$USER_HOME" ] || [ ! -d "$USER_HOME" ]; then
    log "ERROR: Could not resolve home directory for '${CONSOLE_USER}'."
    exit 1
fi

# --- Guard: Node is required (the status line is a node script) ---
# Resolve node via a LOGIN shell so the user's full PATH (Homebrew, nvm, the
# managed /usr/local/bin pkg) is in scope, then keep the absolute path. We must
# call node by absolute path later: `sudo -u user node ...` runs with sudo's
# stripped secure_path, which won't contain /opt/homebrew/bin etc., so a bare
# `node` under sudo fails "node: command not found" even when node is installed.
NODE_BIN=$(sudo -u "$CONSOLE_USER" -H bash -lc 'command -v node' 2>/dev/null || true)
if [ -z "$NODE_BIN" ]; then
    log "ERROR: Node.js not found for ${CONSOLE_USER}. The status line runs 'node ~/.claude/statusline.js'. Deploy software/node/install.sh to this machine first."
    exit 1
fi
log "Using node at ${NODE_BIN} (for ${CONSOLE_USER})."

CLAUDE_DIR="${USER_HOME}/.claude"
SETTINGS="${CLAUDE_DIR}/settings.json"

log "Installing status line for '${CONSOLE_USER}' on ${HOSTNAME}..."

# --- Fetch the current statusline.js from the repo ---
if ! timeout 120 curl -fsSL -o "${WORK_DIR}/statusline.js" "${RAW_BASE}/statusline.js" 2>&1 | tee -a "$LOG_FILE"; then
    log "ERROR: Failed to download statusline.js from ${RAW_BASE}."
    exit 1
fi

# --- Place the script in the user's ~/.claude (as the user) ---
sudo -u "$CONSOLE_USER" -H mkdir -p "$CLAUDE_DIR"
install -m 0644 -o "$CONSOLE_USER" "${WORK_DIR}/statusline.js" "${CLAUDE_DIR}/statusline.js"
log "Placed ${CLAUDE_DIR}/statusline.js"

# --- Merge the statusLine key into settings.json (as the user, via node) ---
# Reads existing settings (or starts {}), sets .statusLine, writes back with
# the user's other keys preserved. Refuses to overwrite a settings.json that
# exists but won't parse — a human should look rather than lose config.
MERGE_JS="${WORK_DIR}/merge.js"
cat > "$MERGE_JS" <<'NODE'
const fs = require("fs");
const p = process.argv[2]; // argv[1] is this script's path; the settings path is argv[2]
let s = {};
if (fs.existsSync(p)) {
  const raw = fs.readFileSync(p, "utf8").trim();
  if (raw) {
    try { s = JSON.parse(raw); }
    catch (e) { console.error("existing settings.json is not valid JSON — refusing to overwrite"); process.exit(2); }
  }
}
s.statusLine = { type: "command", command: "node ~/.claude/statusline.js" };
fs.writeFileSync(p, JSON.stringify(s, null, 2) + "\n");
NODE

install -m 0644 -o "$CONSOLE_USER" "$MERGE_JS" "${WORK_DIR}/merge-user.js"
# Call node by absolute path (see NODE_BIN note above). Distinguish exit 2
# (existing settings.json won't parse — deliberately refused) from any other
# failure (node couldn't run, write failed, etc.) so the log isn't misleading.
set +e
sudo -u "$CONSOLE_USER" -H "$NODE_BIN" "${WORK_DIR}/merge-user.js" "$SETTINGS" 2>&1 | tee -a "$LOG_FILE"
merge_rc=${PIPESTATUS[0]}
set -e
if [ "$merge_rc" -eq 2 ]; then
    log "ERROR: ${SETTINGS} exists but is not valid JSON — refused to overwrite. Fix or remove it, then re-run."
    exit 1
elif [ "$merge_rc" -ne 0 ]; then
    log "ERROR: merge step failed (rc=${merge_rc}) running ${NODE_BIN}. ${SETTINGS} left untouched."
    exit 1
fi

log "Status line wired into ${SETTINGS}. Takes effect next Claude Code launch."
rm -f "$LOG_FILE"
exit 0
