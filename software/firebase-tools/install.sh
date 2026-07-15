#!/bin/bash

# The Life Church — Firebase CLI (firebase-tools) Silent Install
#
# ===== What to put in Mosyle =================================================
#   Mosyle -> Scripts (Custom Command) -> new shell script
#     Name:   TLC Firebase CLI — Silent Install
#     Run:    Recurring     As: root     Scope: vibe coders / IT-dev (opt-in)
#     Script:
#       #!/bin/bash
#       curl -fsSL https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/firebase-tools/install.sh | bash
# =============================================================================
#
# Installs the pinned `firebase-tools` npm package system-wide via the fleet
# Node's global prefix, so `firebase` is on PATH for every user. One binary
# carries the CLI, the local **emulator suite**, and the **MCP server**
# (`firebase mcp`) — this is the entire Firebase toolchain for builders, per
# the runbook in software/firebase/README.md.
#
# Staff and Claude never run `npx firebase-tools` — npx is blocked in Bash and
# deliberately rejected in MCP configs (it pulls unreviewed @latest, bypassing
# this pin). Project repos and their `.mcp.json` reference the bare `firebase`
# command and never carry a CLI version of their own — forks stay maintenance-
# free, and merging a bump PR here updates the whole fleet on the next
# recurring run.
#
# Like hyperframes: npm package, so integrity is the exact-version pin + the
# npm registry (no per-arch SHA). Bump via the firebase-tools job in
# bump-pins.yml (14-day cooldown).
#
# This one script stands up the whole vibe-coder chain, in order:
#   1. ensures Node >= 20 — bootstraps software/node/install.sh if missing/old
#   2. ensures Java >= 21 — bootstraps software/java/install.sh if missing/old
#      (the Firestore emulator requires it; the CLI itself does not)
#   3. converges the GitHub CLI — always runs software/gh/install.sh (it is
#      version-idempotent), so gh pin bumps reach these machines too. Not a
#      firebase need — gh is how builders clone org repos and reach the
#      private plugin marketplace, and this script is the one-stop chain.
#   4. installs/pins `firebase-tools` globally (fleet Node's prefix)
#
# Notes:
#   - Emulator JARs download per-user on first `firebase emulators:start`
#     (into ~/.cache/firebase/emulators — needs egress; not this script's job).
#   - firebase-tools shows update-notifier notices but does NOT self-install
#     updates — no wrapper needed (unlike hyperframes).
#   - No auth ships here. Builders are never logged in (`firebase login` is an
#     IT thing); emulators run against `demo-*` projects with no login at all.
#     gh auth is likewise per-user and IT-assisted, not this script's job.
#
# Exit codes:
#   0 — firebase-tools present at the pinned version; Node + Java + gh satisfied
#   1 — install failure, or a prerequisite bootstrap (Node, Java, or gh) failed

set -euo pipefail

# --- Pinned release ----------------------------------------------------------
# npm package `firebase-tools`. Bump via the firebase-tools job in
# bump-pins.yml (14-day cooldown), or manually:
# `npm view firebase-tools version`, update, open a PR.
FIREBASE_TOOLS_VERSION="15.22.3"
# Minimum Node major the CLI requires (firebase-tools v15 engines: ">=20").
NODE_MIN_MAJOR="20"
# Minimum Java major the emulators require (firebase-tools v15 emulators need
# Java >= 21 — an older JRE passes a naive presence check but fails at
# `emulators:start`).
JAVA_MIN_MAJOR="21"
# Prerequisites/companions — bootstrapped from this repo's own pinned
# installers if missing (same raw URLs Mosyle uses; each target is idempotent).
NODE_INSTALLER_URL="https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/node/install.sh"
JAVA_INSTALLER_URL="https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/java/install.sh"
GH_INSTALLER_URL="https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/gh/install.sh"
# ------------------------------------------------------------------------------

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="/tmp/firebase-tools-install-${TIMESTAMP}.log"
HOSTNAME=$(scutil --get ComputerName 2>/dev/null || hostname)
SERIAL=$(ioreg -c IOPlatformExpertDevice -d 2 | awk -F\" '/IOPlatformSerialNumber/{print $4}')

log() {
    local msg="[FIREBASE-TOOLS-INSTALL $(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$LOG_FILE"
}

# macOS ships no GNU `timeout`; shim it with perl's alarm() (bundled with the OS).
timeout() {
    perl -e 'alarm shift; exec @ARGV' "$@"
}

WORK_DIR=$(mktemp -d /tmp/tlc-firebase-tools-installer.XXXXXX)
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT INT TERM

# Fetch and run one of this repo's own pinned installers (same raw URL Mosyle
# uses) to bootstrap a prerequisite — Node or Java — that this script needs
# but doesn't own. Idempotent: each target installer no-ops when current.
bootstrap_from_repo() {
    local name="$1" url="$2"
    log "Bootstrapping ${name} via ${url} ..."
    if ! timeout 120 curl -fsSL -o "${WORK_DIR}/${name}-install.sh" "$url" 2>&1 | tee -a "$LOG_FILE"; then
        log "ERROR: failed to download the ${name} installer from ${url}."
        return 1
    fi
    if ! bash "${WORK_DIR}/${name}-install.sh" 2>&1 | tee -a "$LOG_FILE"; then
        log "ERROR: ${name} bootstrap failed — see its output above."
        return 1
    fi
    hash -r  # refresh command lookup so freshly-installed binaries resolve
    return 0
}

# --- Guard: must run as root (npm -g writes to the global prefix) ---
if [ "$(id -u)" -ne 0 ]; then
    log "ERROR: must run as root (Mosyle default). Got uid $(id -u)."
    exit 1
fi

# --- Ensure the fleet Node/npm (bootstrap software/node if missing or too old) ---
export PATH="/usr/local/bin:${PATH}"
node_ok() {
    command -v node >/dev/null 2>&1 || return 1
    command -v npm  >/dev/null 2>&1 || return 1
    local major
    major=$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)
    [ "$major" -ge "$NODE_MIN_MAJOR" ]
}
if ! node_ok; then
    log "Node >= ${NODE_MIN_MAJOR} not found (or too old) — bootstrapping the pinned fleet Node..."
    bootstrap_from_repo node "$NODE_INSTALLER_URL" || exit 1
fi
if ! node_ok; then
    log "ERROR: Node >= ${NODE_MIN_MAJOR} still not present after bootstrap — cannot continue."
    exit 1
fi

NPM_ROOT=$(npm root -g)
NPM_BIN="$(npm prefix -g)/bin"
PKG_DIR="${NPM_ROOT}/firebase-tools"
BIN="${NPM_BIN}/firebase"

log "Starting on ${HOSTNAME} (${SERIAL}). Node $(node -v), npm $(npm -v). Global prefix: $(npm prefix -g)."

# --- Ensure Java >= JAVA_MIN_MAJOR (Firestore emulator requirement) ---
# An older JRE (11/17) on the machine would pass a bare presence check, but
# the emulators refuse it — require the actual minimum before skipping.
if ! /usr/libexec/java_home -v "${JAVA_MIN_MAJOR}+" >/dev/null 2>&1; then
    log "Java >= ${JAVA_MIN_MAJOR} not found — bootstrapping the pinned Temurin JRE..."
    bootstrap_from_repo java "$JAVA_INSTALLER_URL" || exit 1
fi
if ! /usr/libexec/java_home -v "${JAVA_MIN_MAJOR}+" >/dev/null 2>&1; then
    log "ERROR: Java >= ${JAVA_MIN_MAJOR} still not found after bootstrap — the Firestore emulator would not run."
    exit 1
fi
log "Java OK: $(/usr/libexec/java_home -v "${JAVA_MIN_MAJOR}+" 2>/dev/null)."

# --- Converge the GitHub CLI (always run the repo's pinned installer) ---
# Not a firebase prerequisite — gh is how builders clone org repos and reach
# the private plugin marketplace, and this script is the one-stop chain for
# vibe-coder machines. Run unconditionally: the gh installer is version-
# idempotent (fast no-op at the pin), so gh pin bumps also reach machines
# that only run THIS script (the standalone gh script is a manual-run deploy).
bootstrap_from_repo gh "$GH_INSTALLER_URL" || exit 1
if ! command -v gh >/dev/null 2>&1; then
    log "ERROR: gh still not found after bootstrap."
    exit 1
fi
log "gh OK: $(command -v gh)."

installed_version() {
    [ -f "${PKG_DIR}/package.json" ] || { echo ""; return; }
    node -p "require('${PKG_DIR}/package.json').version" 2>/dev/null || echo ""
}

# --- Install / pin the CLI ---
INSTALLED=$(installed_version)
if [ "$INSTALLED" = "$FIREBASE_TOOLS_VERSION" ]; then
    log "firebase-tools ${FIREBASE_TOOLS_VERSION} already installed globally."
else
    if [ -n "$INSTALLED" ]; then
        log "firebase-tools ${INSTALLED} found; pinned version is ${FIREBASE_TOOLS_VERSION}. Reinstalling."
    else
        log "firebase-tools not installed. Installing ${FIREBASE_TOOLS_VERSION} (npm -g, 10 min timeout)..."
    fi
    if ! timeout 600 npm install -g --no-fund --no-audit "firebase-tools@${FIREBASE_TOOLS_VERSION}" 2>&1 | tee -a "$LOG_FILE"; then
        log "ERROR: npm install -g firebase-tools@${FIREBASE_TOOLS_VERSION} failed or timed out."
        exit 1
    fi
    INSTALLED=$(installed_version)
    if [ "$INSTALLED" != "$FIREBASE_TOOLS_VERSION" ]; then
        log "ERROR: install completed but global firebase-tools reports '${INSTALLED:-nothing}'."
        exit 1
    fi
    log "firebase-tools ${FIREBASE_TOOLS_VERSION} installed."
fi

# --- Verify the CLI runs ---
if ! timeout 60 "$BIN" --version >/dev/null 2>&1; then
    log "ERROR: firebase-tools installed but failed to run (--version)."
    exit 1
fi

log "Firebase toolchain ready: firebase-tools ${FIREBASE_TOOLS_VERSION}, Node $(node -v), Java present, gh present."
rm -f "$LOG_FILE"
exit 0
