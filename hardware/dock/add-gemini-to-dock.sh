#!/bin/zsh

# The Life Church — add Google Gemini to a user's Dock (standalone)
#
# ===== What to put in Mosyle =================================================
#   Mosyle -> Scripts (Custom Command) -> new shell script
#     Name:   TLC Dock — add Gemini (existing Macs)
#     Run:    Once     As: root     Scope: existing Macs that didn't run enrollment
#     Script:
#       #!/bin/bash
#       curl -fsSL https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/hardware/dock/add-gemini-to-dock.sh | bash
# =============================================================================
#
# New enrollments already get Gemini via the staff-dock seeder (slot 2). This is for
# adding Gemini to an EXISTING Mac that didn't go through enrollment — append-only,
# no wipe. Idempotent (no-op if Gemini's already docked) and doesn't reorder. Fully
# standalone: installs dockutil from its signed upstream release if it isn't already
# present, so it does not depend on the staff-dock bootstrap having run. The Gemini
# app itself must already be pushed from Mosyle.

set -u

DOCKUTIL="${DOCKUTIL:-/usr/local/bin/dockutil}"
GEMINI_APP="${GEMINI_APP:-/Applications/Gemini.app}"
# Pinned signed upstream dockutil (same release the staff-dock bootstrap uses).
DOCKUTIL_VERSION="${DOCKUTIL_VERSION:-3.1.3}"
DOCKUTIL_PKG_URL="https://github.com/kcrawford/dockutil/releases/download/${DOCKUTIL_VERSION}/dockutil-${DOCKUTIL_VERSION}.pkg"

if [[ ! -d "$GEMINI_APP" ]]; then
  echo "Gemini not installed at $GEMINI_APP — push it from Mosyle first" >&2
  exit 1
fi

# Install dockutil from its signed upstream release if missing. This script is
# standalone — it does not assume the staff-dock bootstrap ran. (Installing needs
# root; Mosyle runs scripts as root. DOCKUTIL_DIRECT test runs point DOCKUTIL at
# an existing binary and skip this.)
if [[ ! -x "$DOCKUTIL" ]]; then
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "dockutil not present and not root — run as root (deploy via Mosyle) so it can be installed" >&2
    exit 1
  fi
  echo "dockutil not present; installing $DOCKUTIL_VERSION from upstream release"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/tlc-gemini-dock.XXXXXX")"
  trap 'rm -rf "$tmp"' EXIT
  if ! curl -fsSL "$DOCKUTIL_PKG_URL" -o "$tmp/dockutil.pkg"; then
    echo "Failed to download dockutil from $DOCKUTIL_PKG_URL" >&2
    exit 1
  fi
  installer -pkg "$tmp/dockutil.pkg" -target / >/dev/null
  if [[ ! -x "$DOCKUTIL" ]]; then
    echo "dockutil still not present at $DOCKUTIL after install" >&2
    exit 1
  fi
fi

console_user=$(/usr/bin/stat -f %Su /dev/console)
if [[ -z "$console_user" || "$console_user" == "root" ]]; then
  echo "No logged-in console user found" >&2
  exit 1
fi
console_uid=$(/usr/bin/id -u "$console_user" 2>/dev/null)
user_home=$(/usr/bin/dscl . -read "/Users/$console_user" NFSHomeDirectory 2>/dev/null | /usr/bin/awk '{print $2}')
dock_plist="${DOCK_PLIST:-$user_home/Library/Preferences/com.apple.dock.plist}"
if [[ ! -f "$dock_plist" ]]; then
  echo "Dock plist not found at $dock_plist" >&2
  exit 1
fi

# Run dockutil as the console user against their Dock. DOCKUTIL_DIRECT (test
# only) skips the asuser/sudo wrapper and the Dock restart.
run_dockutil() {
  if [[ -n "${DOCKUTIL_DIRECT-}" ]]; then
    "$DOCKUTIL" "$@"
    return $?
  fi
  /bin/launchctl asuser "$console_uid" /usr/bin/sudo -u "$console_user" "$DOCKUTIL" "$@"
}

# Already there? (match by label; do nothing.)
if run_dockutil --find "Gemini" "$dock_plist" >/dev/null 2>&1; then
  echo "Gemini already in $console_user's Dock — nothing to do"
  exit 0
fi

echo "Adding Gemini to $console_user's Dock"
output=$(run_dockutil --add "$GEMINI_APP" --no-restart "$dock_plist" 2>&1)
if [[ $? -ne 0 ]]; then
  # Tolerate the "already exists" race; fail on anything else.
  if printf '%s\n' "$output" | /usr/bin/grep -q "already exists in dock"; then
    echo "Gemini already in $console_user's Dock — nothing to do"
    exit 0
  fi
  echo "Failed to add Gemini: $output" >&2
  exit 1
fi

if [[ -z "${DOCKUTIL_DIRECT-}" ]]; then
  /usr/bin/sudo -u "$console_user" /usr/bin/killall Dock 2>/dev/null || echo "killall Dock failed for $console_user" >&2
fi
echo "Done — Gemini added to $console_user's Dock"
exit 0
