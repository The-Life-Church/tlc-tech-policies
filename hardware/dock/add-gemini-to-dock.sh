#!/bin/zsh

# The Life Church — add Google Gemini to a user's Dock (standalone, selective)
#
# NOT part of the everybody staff-dock seed (install-staff-dock.sh). Gemini is
# rolled out selectively, so this is a separate one-shot you scope to just the
# users who should have it:
#
#   Mosyle → Custom Scripts → scope to the Gemini group → run ONCE:
#   curl -fsSL https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/hardware/dock/add-gemini-to-dock.sh | bash
#
# Idempotent: if Gemini is already in the Dock it does nothing. Adds to the end
# of the current Dock (it doesn't reorder or wipe — this isn't the seeder).
# Assumes dockutil is already present at /usr/local/bin/dockutil (the staff-dock
# bootstrap installs it) and the Gemini app has been pushed from Mosyle.

set -u

DOCKUTIL="${DOCKUTIL:-/usr/local/bin/dockutil}"
GEMINI_APP="${GEMINI_APP:-/Applications/Gemini.app}"

if [[ ! -x "$DOCKUTIL" ]]; then
  echo "dockutil not found at $DOCKUTIL — run the staff-dock bootstrap first (it installs dockutil)" >&2
  exit 1
fi
if [[ ! -d "$GEMINI_APP" ]]; then
  echo "Gemini not installed at $GEMINI_APP — push it from Mosyle first" >&2
  exit 1
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
