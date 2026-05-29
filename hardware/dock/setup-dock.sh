#!/bin/zsh

# The Life Church — Dock seeding runtime
# Invoked by the com.tlc.dock.seed LaunchDaemon (RunAtLoad + StartInterval).
#
# Model: seed once, don't enforce.
#   - First run only: wipe the Dock to a clean slate (dockutil --remove all),
#     then add the managed app set in order.
#   - Subsequent retries: only top up managed apps that still aren't present
#     (e.g. ClickUp / Self Service / PWAs that hadn't installed yet at first boot).
#   - Never re-wipes after the first successful reset, so user customizations
#     made after seeding are preserved.

set -u

DOCKUTIL="${DOCKUTIL:-/usr/local/bin/dockutil}"
ATTEMPT_FILE="${ATTEMPT_FILE:-/var/tmp/tlc-dock-attempt-count.txt}"
RESET_MARKER="${RESET_MARKER:-/var/tmp/tlc-dock-reset-done.txt}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-6}"
LAUNCHDAEMON_PLIST="${LAUNCHDAEMON_PLIST:-/Library/LaunchDaemons/com.tlc.dock.seed.plist}"
STATUS_FILE="${STATUS_FILE:-/var/tmp/tlc-dock-status.txt}"
# Chrome-wait cap: each run with Chrome absent counts as a deferral (no attempt
# spent, no wipe). After MAX_DEFERS of them (~MAX_DEFERS * 10 min) we give up and
# report FAILED, so a broken Chrome push surfaces instead of waiting forever.
DEFER_FILE="${DEFER_FILE:-/var/tmp/tlc-dock-defer-count.txt}"
MAX_DEFERS="${MAX_DEFERS:-24}"

if [[ ! -x "$DOCKUTIL" ]]; then
  echo "dockutil not found at $DOCKUTIL" >&2
  exit 1
fi

console_user=$(/usr/bin/stat -f %Su /dev/console)
if [[ -z "$console_user" || "$console_user" == "root" ]]; then
  echo "No logged-in console user found" >&2
  exit 1
fi

user_home=$(/usr/bin/dscl . -read "/Users/$console_user" NFSHomeDirectory 2>/dev/null | /usr/bin/awk '{print $2}')
if [[ -z "$user_home" ]]; then
  echo "Unable to resolve home directory for $console_user" >&2
  exit 1
fi

console_uid=$(/usr/bin/id -u "$console_user" 2>/dev/null)
if [[ -z "$console_uid" ]]; then
  echo "Unable to resolve uid for $console_user" >&2
  exit 1
fi

dock_plist="${DOCK_PLIST:-$user_home/Library/Preferences/com.apple.dock.plist}"
if [[ ! -f "$dock_plist" ]]; then
  echo "Dock plist not found at $dock_plist" >&2
  exit 1
fi

# --- Managed app definitions ---------------------------------------------
# Order here IS the Dock order (Finder is pinned first by macOS, Trash last).
# Each app has: a label, an optional explicit bundle id (preferred for the
# Dock-match key — required for PWAs whose label differs from the stored id),
# and one or more newline-separated candidate install paths (first match wins).
# PWAs install per-user into the home folder and only exist once Chrome has
# created them for that user, so their candidate paths are home-relative.

typeset -a managed_order
# Docs/Sheets/Slides are force-installed via Chrome but intentionally NOT docked
# (too much dock clutter). To dock them, add `gdocs gsheets gslides` back to the
# order below and uncomment their app_label / app_bid / app_paths entries.
managed_order=(chrome gemini gmail gchat gcal gmeet drivepwa clickup settings selfservice)

typeset -A app_label app_bid app_paths

app_label[chrome]="Google Chrome"
app_label[gmail]="Gmail"
app_label[gcal]="Google Calendar"
app_label[gmeet]="Google Meet"
app_label[gchat]="Google Chat"
app_label[drivepwa]="Google Drive (web)"
# app_label[gdocs]="Google Docs"      # force-installed via Chrome, not docked
# app_label[gsheets]="Google Sheets"  # force-installed via Chrome, not docked
# app_label[gslides]="Google Slides"  # force-installed via Chrome, not docked
app_label[gemini]="Gemini"
app_label[clickup]="ClickUp"
app_label[settings]="System Settings"
app_label[selfservice]="Self Service"

# Explicit Dock-match bundle ids. PWAs use deterministic Chrome app ids.
app_bid[chrome]="com.google.Chrome"
app_bid[gmail]="com.google.Chrome.app.fmgjjmmmlfnkbppncabfkddbjimcfncm"
app_bid[gcal]="com.google.Chrome.app.kjbdgfilnfhdoflbpgamdcdgpehopbep"
app_bid[gmeet]="com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan"
app_bid[gchat]="com.google.Chrome.app.pommaclcbfghclhalboakcipcmmndhcj"
app_bid[drivepwa]="com.google.Chrome.app.aghbiahbpaijignceidepookljebhfak"
# app_bid[gdocs]="com.google.Chrome.app.mpnpojknpmmopombnjdcgaaiekajbnjb"     # not docked
# app_bid[gsheets]="com.google.Chrome.app.fhihpiojkbmbpdjeoajapmgkhlnakfjf"   # not docked
# app_bid[gslides]="com.google.Chrome.app.kefjledonklijopmnomlcbpllchaibag"   # not docked
app_bid[gemini]="com.google.GeminiMacOS"
# clickup / settings / selfservice: derived from the app bundle at runtime.

app_paths[chrome]="/Applications/Google Chrome.app"
app_paths[gmail]="$user_home/Applications/Chrome Apps.localized/Gmail.app
$user_home/Applications/Gmail.app"
app_paths[gcal]="$user_home/Applications/Chrome Apps.localized/Google Calendar.app
$user_home/Applications/Google Calendar.app"
app_paths[gmeet]="$user_home/Applications/Chrome Apps.localized/Google Meet.app
$user_home/Applications/Google Meet.app"
app_paths[gchat]="$user_home/Applications/Chrome Apps.localized/Google Chat.app
$user_home/Applications/Google Chat.app"
app_paths[drivepwa]="$user_home/Applications/Chrome Apps.localized/Google Drive.app
$user_home/Applications/Google Drive.app"
# app_paths[gdocs]="$user_home/Applications/Chrome Apps.localized/Docs.app
# $user_home/Applications/Docs.app"
# app_paths[gsheets]="$user_home/Applications/Chrome Apps.localized/Sheets.app
# $user_home/Applications/Sheets.app"
# app_paths[gslides]="$user_home/Applications/Chrome Apps.localized/Slides.app
# $user_home/Applications/Slides.app"
app_paths[gemini]="/Applications/Gemini.app"
app_paths[clickup]="/Applications/ClickUp.app"
app_paths[settings]="/System/Applications/System Settings.app"
app_paths[selfservice]="/Applications/Self-Service.app"

typeset -a retry_keys
typeset -a added_labels

# First existing candidate path for an app key, or empty if none installed.
resolve_path() {
  local key="$1"
  local line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ -d "$line" ]]; then
      printf '%s\n' "$line"
      return 0
    fi
  done <<< "${app_paths[$key]-}"
  return 1
}

# Is a Chrome PWA shim fully baked? A freshly force-installed PWA can land as a
# placeholder whose CFBundleName is the raw start_url (e.g.
# "https:::mail.google.com:chat:") and/or whose icon hasn't been written yet.
# Docking that gives a Dock tile labeled with the URL and a blank icon —
# permanently, since the wipe is one-shot and retries only top up. Treat such a
# shim as not-ready (skip + retry) until its name is real and its icon exists.
pwa_ready() {
  local app="$1" info name iconfile
  info="$app/Contents/Info"
  name=$(/usr/bin/defaults read "$info" CFBundleName 2>/dev/null) || return 1
  [[ -z "$name" || "$name" == http* || "$name" == *"://"* ]] && return 1
  iconfile=$(/usr/bin/defaults read "$info" CFBundleIconFile 2>/dev/null) || return 1
  [[ -z "$iconfile" ]] && return 1
  [[ "$iconfile" != *.icns ]] && iconfile="${iconfile}.icns"
  [[ -s "$app/Contents/Resources/$iconfile" ]] || return 1
  return 0
}

# Dock-match key: explicit bundle id > bundle id read from the app > label.
dock_key_for() {
  local key="$1"
  if [[ -n "${app_bid[$key]-}" ]]; then
    printf '%s\n' "${app_bid[$key]}"
    return 0
  fi
  local path
  if path=$(resolve_path "$key"); then
    local bid
    bid=$(/usr/bin/mdls -name kMDItemCFBundleIdentifier -raw "$path" 2>/dev/null)
    if [[ -n "$bid" && "$bid" != "(null)" ]]; then
      printf '%s\n' "$bid"
      return 0
    fi
  fi
  printf '%s\n' "${app_label[$key]}"
}

# All dockutil calls run as the console user against their Dock.
# DOCKUTIL_DIRECT (test only) runs dockutil directly, skipping asuser/sudo.
run_dockutil() {
  if [[ -n "${DOCKUTIL_DIRECT-}" ]]; then
    "$DOCKUTIL" "$@"
    return $?
  fi
  /bin/launchctl asuser "$console_uid" /usr/bin/sudo -u "$console_user" "$DOCKUTIL" "$@"
}

dock_has_item() {
  run_dockutil --find "$1" "$dock_plist" >/dev/null 2>&1
}

restart_user_dock() {
  if [[ -n "${DOCKUTIL_DIRECT-}" ]]; then
    echo "[test] skipping Dock restart"
    return 0
  fi
  echo "Restarting Dock for $console_user"
  /usr/bin/sudo -u "$console_user" /usr/bin/killall Dock 2>&1 || echo "killall Dock failed for $console_user" >&2
}

read_attempt_count() {
  if [[ -f "$ATTEMPT_FILE" ]]; then
    /bin/cat "$ATTEMPT_FILE" 2>/dev/null
    return 0
  fi
  printf '%s\n' "0"
}

write_attempt_count() {
  printf '%s\n' "$1" > "$ATTEMPT_FILE"
}

join_by() {
  local delimiter="$1"; shift
  local first=1 item
  for item in "$@"; do
    if [[ "$first" -eq 1 ]]; then
      printf '%s' "$item"; first=0; continue
    fi
    printf '%s%s' "$delimiter" "$item"
  done
}

write_status() {
  local phase="$1"
  local launchdaemon_present="no"
  local retry_pending="" added_apps=""

  [[ -f "$LAUNCHDAEMON_PLIST" ]] && launchdaemon_present="yes"

  if [[ ${#retry_keys[@]} -gt 0 ]]; then
    local -a retry_labels k
    for k in "${retry_keys[@]}"; do retry_labels+=("${app_label[$k]}"); done
    retry_pending=$(join_by "," "${retry_labels[@]}")
  fi
  if [[ ${#added_labels[@]} -gt 0 ]]; then
    added_apps=$(join_by "," "${added_labels[@]}")
  fi

  {
    printf 'timestamp=%s\n' "$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'phase=%s\n' "$phase"
    printf 'console_user=%s\n' "$console_user"
    printf 'attempt_count=%s\n' "$attempt_count"
    printf 'max_attempts=%s\n' "$MAX_ATTEMPTS"
    printf 'changes_made=%s\n' "$changes_made"
    printf 'dock_reset=%s\n' "$dock_reset"
    printf 'added_apps=%s\n' "$added_apps"
    printf 'retry_pending_count=%s\n' "${#retry_keys[@]}"
    printf 'retry_pending=%s\n' "$retry_pending"
    printf 'launchdaemon_present=%s\n' "$launchdaemon_present"
  } > "$STATUS_FILE"
}

cleanup_retry_artifacts() {
  /bin/rm -f "$ATTEMPT_FILE" "$DEFER_FILE"
  if [[ -f "$LAUNCHDAEMON_PLIST" ]]; then
    /bin/rm -f "$LAUNCHDAEMON_PLIST"
    /bin/launchctl bootout system "com.tlc.dock.seed" >/dev/null 2>&1 || true
  fi
}

# dockutil --add, tolerating the "already exists in dock" non-error.
dockutil_add() {
  local output exit_code
  output=$(run_dockutil "$@" 2>&1)
  exit_code=$?
  printf '%s\n' "$output"
  if [[ "$exit_code" -ne 0 ]]; then
    if printf '%s\n' "$output" | /usr/bin/grep -q "already exists in dock"; then
      return 0
    fi
    return "$exit_code"
  fi
  return 0
}

# --- Gate: don't seed until Google Chrome is installed -------------------
# Mosyle doesn't order the bootstrap script against the Chrome app install, so
# this can fire before Chrome (and its PWAs) exist. Wiping to a near-empty Dock
# then would be an ugly first paint and would burn the retry budget waiting on
# Chrome. Hold off — and critically do NOT wipe or spend an attempt — until
# Chrome is present. StartInterval re-runs this every 10 min; PWAs are still
# topped up by the normal retry loop once Chrome is up and the force-list has
# installed them. (We only reach here with a logged-in console user.)
if ! resolve_path chrome >/dev/null; then
  dock_reset="no"
  changes_made=0
  attempt_count=$(read_attempt_count)
  [[ -z "$attempt_count" ]] && attempt_count=0

  defer_count=0
  [[ -f "$DEFER_FILE" ]] && defer_count=$(/bin/cat "$DEFER_FILE" 2>/dev/null)
  [[ -z "$defer_count" ]] && defer_count=0
  defer_count=$((defer_count + 1))
  printf '%s\n' "$defer_count" > "$DEFER_FILE"

  if [[ "$defer_count" -ge "$MAX_DEFERS" ]]; then
    echo "Google Chrome still not installed after $defer_count checks (~$((MAX_DEFERS * 10)) min); giving up" >&2
    write_status "chrome_wait_exceeded"
    cleanup_retry_artifacts
    exit 0
  fi

  echo "Google Chrome not installed yet (defer $defer_count/$MAX_DEFERS); deferring seed (no wipe, no attempt spent)"
  write_status "waiting_for_chrome"
  exit 0
fi

# --- First-run clean slate -----------------------------------------------
# Wipe the Dock to empty exactly once, before the first add pass. Gated on a
# marker (not the attempt counter) so a mid-run failure can't cause a second
# wipe on the next retry. The bootstrap clears this marker on fresh install.
dock_reset="no"
if [[ ! -f "$RESET_MARKER" ]]; then
  echo "First run: clearing Dock to a clean slate"
  if dockutil_add --remove all --no-restart "$dock_plist"; then
    : > "$RESET_MARKER"
    dock_reset="yes"
  else
    echo "Dock reset failed; will retry on next run" >&2
    exit 1
  fi
fi

changes_made=0
attempt_count=$(read_attempt_count)
[[ -z "$attempt_count" ]] && attempt_count=0
attempt_count=$((attempt_count + 1))
write_attempt_count "$attempt_count"
write_status "running"

# --- Add managed apps in order -------------------------------------------
for key in "${managed_order[@]}"; do
  app_path=$(resolve_path "$key") || app_path=""

  if [[ -z "$app_path" ]]; then
    echo "Skipping ${app_label[$key]} (not installed yet)"
    retry_keys+=("$key")
    continue
  fi

  # For Chrome PWAs, make sure the shim is fully baked before docking it, so we
  # never pin a placeholder tile (URL as the label, blank icon). Not-ready =
  # treat like not-installed: skip and retry next pass.
  if [[ "${app_bid[$key]-}" == com.google.Chrome.app.* ]] && ! pwa_ready "$app_path"; then
    echo "Skipping ${app_label[$key]} (shim present but not fully rendered — placeholder name/icon)"
    retry_keys+=("$key")
    continue
  fi

  match_key=$(dock_key_for "$key")
  if dock_has_item "$match_key"; then
    echo "Already in Dock: ${app_label[$key]}"
    continue
  fi

  echo "Adding ${app_label[$key]}"
  if ! dockutil_add --add "$app_path" --no-restart "$dock_plist"; then
    echo "Failed to add ${app_label[$key]}" >&2
    exit 1
  fi
  changes_made=1
  added_labels+=("${app_label[$key]}")
done

# --- Resolve run outcome --------------------------------------------------
if [[ ${#retry_keys[@]} -eq 0 ]]; then
  echo "Dock seeding complete"
  cleanup_retry_artifacts
  write_status "complete"
  [[ "$changes_made" -eq 1 ]] && restart_user_dock
  exit 0
fi

if [[ "$attempt_count" -ge "$MAX_ATTEMPTS" ]]; then
  local -a unresolved k
  for k in "${retry_keys[@]}"; do unresolved+=("${app_label[$k]}"); done
  echo "Reached max attempts with unresolved apps: ${unresolved[*]}"
  cleanup_retry_artifacts
  write_status "max_attempts_reached"
  [[ "$changes_made" -eq 1 ]] && restart_user_dock
  exit 0
fi

write_status "retry_pending"
[[ "$changes_made" -eq 1 ]] && restart_user_dock
exit 0
