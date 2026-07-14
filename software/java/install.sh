#!/bin/bash

# The Life Church — Temurin JRE Silent Install
#
# ===== What to put in Mosyle =================================================
#   Mosyle -> Scripts (Custom Command) -> new shell script
#     Name:   TLC Temurin JRE — Silent Install
#     Run:    Once or recurring     As: root     Scope: firebase-emulator hosts (opt-in)
#     Script:
#       #!/bin/bash
#       curl -fsSL https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/java/install.sh | bash
# =============================================================================
#
# Installs the pinned Eclipse Temurin JRE (LTS major below) system-wide from
# the official Adoptium GitHub release pkg. Exists because the Firebase
# emulator suite (Firestore/Storage/PubSub emulators) requires a Java runtime —
# machines getting software/firebase-tools/ need this first (that installer
# bootstraps this one automatically, so scoping THIS script separately is only
# needed for hosts that want Java without the Firebase CLI).
#
# Pinning: version + build + per-arch pkg SHA-256s, all from the Adoptium API's
# published checksums. The pkgs are signed by Eclipse Adoptium, but we verify
# the pinned SHA anyway — same belt-and-suspenders as the other installers.
# Bumps arrive as PRs from the `temurin` job in bump-pins.yml (14-day cooldown,
# pinned to the LTS major — major-version jumps are a deliberate manual change).
#
# Idempotency is by exact Temurin release: the installed JRE's release file is
# checked for IMPLEMENTOR_VERSION="Temurin-<version>+<build>". Other JVMs on
# the machine are left alone — the pkg installs side-by-side under
# /Library/Java/JavaVirtualMachines/ and /usr/bin/java resolves the newest.
#
# Exit codes:
#   0 — pinned Temurin JRE present (already or after install)
#   1 — download, checksum, or install failure

set -euo pipefail

# --- Pinned release ----------------------------------------------------------
# Eclipse Temurin JRE, LTS major. Bump via the temurin job in bump-pins.yml.
TEMURIN_MAJOR="21"
TEMURIN_VERSION="21.0.11"
TEMURIN_BUILD="10"
TEMURIN_SHA256_ARM64="ebcc624592cedaac2e5166b4e1a8bec635f3560825379b85d9009f8bb544e16c"
TEMURIN_SHA256_X64="a886566d86e334420876a74e32172a1ddb8e86db40cbc0e6edf6e2f517e26986"
# ------------------------------------------------------------------------------

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="/tmp/java-install-${TIMESTAMP}.log"
HOSTNAME=$(scutil --get ComputerName 2>/dev/null || hostname)
SERIAL=$(ioreg -c IOPlatformExpertDevice -d 2 | awk -F\" '/IOPlatformSerialNumber/{print $4}')

log() {
    local msg="[JAVA-INSTALL $(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$LOG_FILE"
}

# macOS ships no GNU `timeout`; shim it with perl's alarm() (bundled with the OS).
timeout() {
    perl -e 'alarm shift; exec @ARGV' "$@"
}

WORK_DIR=$(mktemp -d /tmp/tlc-java-installer.XXXXXX)
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT INT TERM

# --- Guard: must run as root (installer -target /) ---
if [ "$(id -u)" -ne 0 ]; then
    log "ERROR: must run as root (Mosyle default). Got uid $(id -u)."
    exit 1
fi

JVM_DIR="/Library/Java/JavaVirtualMachines/temurin-${TEMURIN_MAJOR}.jre"
RELEASE_FILE="${JVM_DIR}/Contents/Home/release"
PIN_STRING="Temurin-${TEMURIN_VERSION}+${TEMURIN_BUILD}"

log "Starting on ${HOSTNAME} (${SERIAL}). Pin: ${PIN_STRING}."

# --- Idempotency: exact pinned Temurin release already installed? ---
if [ -f "$RELEASE_FILE" ] && grep -q "IMPLEMENTOR_VERSION=\"${PIN_STRING}\"" "$RELEASE_FILE"; then
    log "Temurin JRE ${PIN_STRING} already installed at ${JVM_DIR}. Nothing to do."
    rm -f "$LOG_FILE"
    exit 0
fi

# --- Resolve the per-arch asset ---
case "$(uname -m)" in
    arm64)  ARCH="aarch64"; SHA_EXPECTED="$TEMURIN_SHA256_ARM64" ;;
    x86_64) ARCH="x64";     SHA_EXPECTED="$TEMURIN_SHA256_X64" ;;
    *) log "ERROR: unsupported architecture $(uname -m)."; exit 1 ;;
esac

# Release tag contains '+', which must be %2B in the URL.
PKG_NAME="OpenJDK${TEMURIN_MAJOR}U-jre_${ARCH}_mac_hotspot_${TEMURIN_VERSION}_${TEMURIN_BUILD}.pkg"
PKG_URL="https://github.com/adoptium/temurin${TEMURIN_MAJOR}-binaries/releases/download/jdk-${TEMURIN_VERSION}%2B${TEMURIN_BUILD}/${PKG_NAME}"
PKG_PATH="${WORK_DIR}/${PKG_NAME}"

# --- Download + verify ---
log "Downloading ${PKG_NAME} (10 min timeout)..."
if ! timeout 600 curl -fsSL -o "$PKG_PATH" "$PKG_URL" 2>&1 | tee -a "$LOG_FILE"; then
    log "ERROR: download failed from ${PKG_URL}."
    exit 1
fi

SHA_ACTUAL=$(shasum -a 256 "$PKG_PATH" | awk '{print $1}')
if [ "$SHA_ACTUAL" != "$SHA_EXPECTED" ]; then
    log "ERROR: checksum mismatch for ${PKG_NAME}."
    log "  expected: ${SHA_EXPECTED}"
    log "  actual:   ${SHA_ACTUAL}"
    log "Refusing to install."
    exit 1
fi
log "Checksum verified."

# --- Install ---
log "Installing ${PKG_NAME}..."
if ! timeout 600 installer -pkg "$PKG_PATH" -target / 2>&1 | tee -a "$LOG_FILE"; then
    log "ERROR: installer failed for ${PKG_NAME}."
    exit 1
fi

# --- Verify the runtime actually resolves and runs ---
if ! JAVA_HOME_PATH=$(/usr/libexec/java_home -v "$TEMURIN_MAJOR" 2>/dev/null); then
    log "ERROR: java_home cannot find a ${TEMURIN_MAJOR} JVM after install."
    exit 1
fi
if ! "${JAVA_HOME_PATH}/bin/java" -version >>"$LOG_FILE" 2>&1; then
    log "ERROR: installed java failed to run (-version)."
    exit 1
fi
if [ -f "$RELEASE_FILE" ] && ! grep -q "IMPLEMENTOR_VERSION=\"${PIN_STRING}\"" "$RELEASE_FILE"; then
    log "WARN: installed Temurin release file does not match pin ${PIN_STRING} — check the pkg contents."
fi

log "Temurin JRE ${PIN_STRING} installed (${JAVA_HOME_PATH})."
rm -f "$LOG_FILE"
exit 0
