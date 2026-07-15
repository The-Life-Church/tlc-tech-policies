#!/bin/bash

# The Life Church — HyperFrames CLI Silent Install
#
# ===== What to put in Mosyle =================================================
#   Mosyle -> Scripts (Custom Command) -> new shell script
#     Name:   TLC HyperFrames CLI — Silent Install
#     Run:    Once or recurring     As: root     Scope: creative / IT-dev (opt-in)
#     Script:
#       #!/bin/bash
#       curl -fsSL https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/hyperframes/install.sh | bash
# =============================================================================
#
# Installs the HyperFrames CLI (npm package `hyperframes`) system-wide via the
# fleet Node's global prefix, so `hyperframes` is on PATH for every user and
# the on-device skills never need `npx` (blocked on TLC machines). Runs as root
# — this is the IT-managed path; staff and Claude never run upstream's
# `npx hyperframes` / `npx skills add`.
#
# Unlike the Higgsfield CLI (a single pinned binary), HyperFrames ships as an
# npm package, so integrity is npm's version pin + registry, NOT a per-arch
# SHA. Pin the exact version below; bump via the npm job in bump-pins.yml.
#
# HyperFrames renders locally with headless Chrome + FFmpeg. This one script
# stands up the whole local toolchain, in order:
#   1. ensures Node >= 22 — bootstraps software/node/install.sh from the repo if
#      it's missing or too old (idempotent; skipped when already current)
#   2. converges FFmpeg + ffprobe — always runs software/ffmpeg/install.sh (it
#      is SHA-idempotent), so hosts with a stray brew/manual ffmpeg still get
#      the reviewed pinned binaries at /usr/local/bin
#   3. converges the GitHub CLI — always runs software/gh/install.sh (it is
#      version-idempotent), so gh pin bumps reach these machines too. Not a
#      render need — gh is how staff clone org repos and reach the private
#      plugin marketplace; this script is these machines' one-stop.
#   4. installs/pins the `hyperframes` CLI globally (fleet Node's prefix)
#   5. installs the HyperFrames skills + routing rule for the CONSOLE USER
#      (drops from root), so the agent has them; the CLI itself needs no skills
#
# So Mosyle only needs THIS script scoped to the group — Node, ffmpeg, gh, and
# skills all come along. (software/node/, software/ffmpeg/, and software/gh/
# stay independently deployable for hosts that want them without HyperFrames.)
#
# The CLI provisions its own headless browser on first render
# (chrome-headless-shell, into the invoking user's ~/.cache/puppeteer) — the
# version-matched self-download is more reliable than the fleet Chrome.
#
# Skills install is best-effort — a hiccup logs a WARN and retries on the next
# recurring run; it never fails the toolchain.
#
# Auth note: local rendering needs no key or account. (The hosted HyperFrames
# MCP — cloud render on HeyGen credits — is a separate product, not this.)
#
# Exit codes:
#   0 — hyperframes present at the pinned version; Node + ffmpeg/ffprobe + gh satisfied
#   1 — install failure, or a prerequisite bootstrap (Node, ffmpeg, or gh) failed

set -euo pipefail

# --- Pinned release ----------------------------------------------------------
# npm package `hyperframes`. Bump via the npm job in bump-pins.yml (14-day
# cooldown), or manually: `npm view hyperframes version`, update, open a PR.
HYPERFRAMES_VERSION="0.7.56"
# Minimum Node major the CLI requires (README: "Node.js 22+").
NODE_MIN_MAJOR="22"
# Node/FFmpeg prerequisites + the gh companion — bootstrapped from this repo's
# own pinned installers if missing (same raw URLs Mosyle uses; each target is
# idempotent).
NODE_INSTALLER_URL="https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/node/install.sh"
FFMPEG_INSTALLER_URL="https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/ffmpeg/install.sh"
GH_INSTALLER_URL="https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/gh/install.sh"
# ------------------------------------------------------------------------------

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="/tmp/hyperframes-install-${TIMESTAMP}.log"
HOSTNAME=$(scutil --get ComputerName 2>/dev/null || hostname)
SERIAL=$(ioreg -c IOPlatformExpertDevice -d 2 | awk -F\" '/IOPlatformSerialNumber/{print $4}')

log() {
    local msg="[HYPERFRAMES-INSTALL $(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$LOG_FILE"
}

# macOS ships no GNU `timeout`; shim it with perl's alarm() (bundled with the OS).
timeout() {
    perl -e 'alarm shift; exec @ARGV' "$@"
}

WORK_DIR=$(mktemp -d /tmp/tlc-hyperframes-installer.XXXXXX)
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT INT TERM

# Fetch and run one of this repo's own pinned installers (same raw URL Mosyle
# uses) to bootstrap a prerequisite — Node or FFmpeg — that this script needs
# but doesn't own. Idempotent: each target installer no-ops when current.
# Called as `bootstrap_from_repo <name> <url> || exit 1`.
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
PKG_DIR="${NPM_ROOT}/hyperframes"
BIN="${NPM_BIN}/hyperframes"

log "Starting on ${HOSTNAME} (${SERIAL}). Node $(node -v), npm $(npm -v). Global prefix: $(npm prefix -g)."

# --- Converge FFmpeg + ffprobe (always run the repo's pinned installer) ---
# HyperFrames shells out to system ffmpeg/ffprobe for encoding + media probing.
# Run the bootstrap unconditionally: a host that already has a brew or manual
# ffmpeg on PATH would otherwise never converge to the reviewed pinned binaries.
# The installer is SHA-idempotent — a fast no-op once /usr/local/bin is current.
bootstrap_from_repo ffmpeg "$FFMPEG_INSTALLER_URL" || exit 1
if ! command -v ffmpeg >/dev/null 2>&1 || ! command -v ffprobe >/dev/null 2>&1; then
    log "ERROR: ffmpeg/ffprobe still not found after bootstrap — toolchain incomplete."
    exit 1
fi
log "FFmpeg OK: $(command -v ffmpeg) + $(command -v ffprobe)."

# --- Converge the GitHub CLI (always run the repo's pinned installer) ---
# Not a render prerequisite — gh is how staff clone org repos and reach the
# private plugin marketplace, and this script is these machines' one-stop.
# Unconditional: the gh installer is version-idempotent (fast no-op at the
# pin), so gh pin bumps also reach hosts that only run THIS script (the
# standalone gh script is a manual-run deploy).
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
if [ "$INSTALLED" = "$HYPERFRAMES_VERSION" ]; then
    log "hyperframes ${HYPERFRAMES_VERSION} already installed globally."
else
    if [ -n "$INSTALLED" ]; then
        log "hyperframes ${INSTALLED} found; pinned version is ${HYPERFRAMES_VERSION}. Reinstalling."
    else
        log "hyperframes not installed. Installing ${HYPERFRAMES_VERSION} (npm -g, 10 min timeout)..."
    fi
    # --no-fund/--no-audit keep the run quiet; native deps (sharp, onnxruntime-node,
    # puppeteer-core) fetch prebuilt binaries during this step — needs egress.
    if ! timeout 600 npm install -g --no-fund --no-audit "hyperframes@${HYPERFRAMES_VERSION}" 2>&1 | tee -a "$LOG_FILE"; then
        log "ERROR: npm install -g hyperframes@${HYPERFRAMES_VERSION} failed or timed out."
        exit 1
    fi
    INSTALLED=$(installed_version)
    if [ "$INSTALLED" != "$HYPERFRAMES_VERSION" ]; then
        log "ERROR: install completed but global hyperframes reports '${INSTALLED:-nothing}'."
        exit 1
    fi
    log "hyperframes ${HYPERFRAMES_VERSION} installed."
fi

# --- Pin protection: disable the CLI's self-update path -----------------------
# The CLI schedules its own `npm install -g hyperframes@latest` unless
# HYPERFRAMES_NO_AUTO_INSTALL / HYPERFRAMES_NO_UPDATE_CHECK are set (verified
# in 0.7.56's cli.js). On a writable prefix that silently bypasses the 14-day
# reviewed pin; on a root-owned one it fails noisily on every user run. Replace
# npm's bin symlink with a wrapper that sets both and execs the real CLI. npm
# recreates the symlink on every (re)install, so this re-wraps right after —
# idempotent on repeat runs.
NODE_BIN=$(command -v node)
wrap_cli() {
    local target
    target=$(node -p "const p=require('${PKG_DIR}/package.json'); const b=p.bin; require('path').resolve('${PKG_DIR}', typeof b==='string' ? b : b.hyperframes)" 2>/dev/null || echo "")
    if [ -z "$target" ] || [ ! -f "$target" ]; then
        log "WARN: could not resolve the hyperframes entry point — leaving npm's bin untouched (self-update stays enabled)."
        return 0
    fi
    if [ ! -L "$BIN" ] && ! grep -q "TLC-managed wrapper" "$BIN" 2>/dev/null; then
        log "WARN: ${BIN} is neither npm's symlink nor our wrapper — leaving it untouched."
        return 0
    fi
    rm -f "$BIN"   # a plain redirect would write THROUGH the symlink into cli.js
    cat > "$BIN" <<WRAP
#!/bin/bash
# TLC-managed wrapper — keeps hyperframes on the reviewed fleet pin.
# Without these, the CLI schedules its own npm -g upgrade to @latest.
# Recreated by software/hyperframes/install.sh on every run.
export HYPERFRAMES_NO_UPDATE_CHECK=1
export HYPERFRAMES_NO_AUTO_INSTALL=1
exec "${NODE_BIN}" "${target}" "\$@"
WRAP
    chmod 755 "$BIN"
    log "Wrapped ${BIN} — self-update/auto-install disabled; the reviewed pin is authoritative."
}
wrap_cli

# --- Verify the CLI runs (npm's own global bin) ---
if ! timeout 60 "$BIN" --version >/dev/null 2>&1; then
    log "ERROR: hyperframes installed but failed to run (--version)."
    exit 1
fi

# --- Install the HyperFrames skills for the console user (best-effort) ---
# `hyperframes skills` writes to the USER's ~/.claude/skills (and other AI-tool
# skill dirs) — a per-user location — so drop from root to the logged-in user.
# Install only when absent; the skills self-update at runtime, so recurring runs
# skip. A failure here never fails the toolchain (the CLI is already installed).
CONSOLE_USER=$(stat -f%Su /dev/console 2>/dev/null || echo "")
if [ -z "$CONSOLE_USER" ] || [ "$CONSOLE_USER" = "root" ] || [ "$CONSOLE_USER" = "loginwindow" ]; then
    log "No console user logged in — skipping skills; a recurring run lands them once someone's logged in."
else
    USER_HOME=$(dscl . -read "/Users/${CONSOLE_USER}" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
    if [ -d "${USER_HOME}/.claude/skills/hyperframes" ]; then
        log "HyperFrames skills already present for ${CONSOLE_USER} — leaving them (they self-update at runtime)."
    elif ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
        # The skills installer shells out to git; without it, it prints a skip
        # and still exits 0 — so check up front instead of trusting the exit code.
        log "WARN: Xcode CLT (git) not installed — the skills step needs it. Deploy software/xcode to this host; a recurring run will land the skills."
    else
        log "Installing HyperFrames skills for ${CONSOLE_USER} (dropping from root)..."
        # Run as the user with the fleet toolchain on PATH so hyperframes and
        # the node its shebang needs both resolve.
        if ! sudo -u "$CONSOLE_USER" -H env PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" "$BIN" skills 2>&1 | tee -a "$LOG_FILE"; then
            log "WARN: skills install returned non-zero — CLI is fine; a recurring run will retry."
        elif [ -d "${USER_HOME}/.claude/skills/hyperframes" ]; then
            log "HyperFrames skills installed for ${CONSOLE_USER}."
        else
            # Exit 0 with no skills dir = the installer skipped internally.
            log "WARN: skills command exited 0 but ~/.claude/skills/hyperframes is absent — treating as not installed; a recurring run will retry."
        fi
    fi

    # Routing directive -> ~/.claude/rules/ (auto-loads at user scope; no import,
    # no approval dialog). Tells the agent to call the global `hyperframes`
    # binary, since the installed skills print the blocked `npx hyperframes ...`.
    # Rewritten each run so the canonical directive stays current; user-owned.
    RULES_DIR="${USER_HOME}/.claude/rules"
    sudo -u "$CONSOLE_USER" -H mkdir -p "$RULES_DIR" 2>/dev/null || true
    if sudo -u "$CONSOLE_USER" -H tee "${RULES_DIR}/hyperframes-cli.md" >/dev/null 2>&1 <<'RULE'
# HyperFrames — invoke the global binary, never npx

The HyperFrames CLI is installed globally (`hyperframes` is on `PATH`). The
HyperFrames skills print their commands as `npx hyperframes ...` / `npx skills
...`, but `npx` is blocked on this machine. When following a HyperFrames skill,
**drop the `npx ` prefix and run `hyperframes ...` directly** — `hyperframes
render`, `hyperframes init`, `hyperframes skills update`, and so on. (`npx
hyperframes` would only run this same global binary anyway; the block is on
`npx` itself.) Never try to install HyperFrames via `npx`, `npm install`, or
`npx skills add` — those are blocked, and IT manages the install.
RULE
    then
        log "Routing directive written: ${RULES_DIR}/hyperframes-cli.md"
    else
        log "WARN: could not write the routing directive to ${RULES_DIR} — skills may hit the npx block until it's present."
    fi
fi

log "HyperFrames toolchain ready: hyperframes ${HYPERFRAMES_VERSION}, Node $(node -v), ffmpeg + ffprobe OK, gh present."
rm -f "$LOG_FILE"
exit 0
