#!/bin/zsh

# The Life Church — Dock seed status reporter
# Human-readable summary + exit code reflecting seeding state.
#   0 OK | 1 PENDING | 2 FAILED | 3 ERROR

set -u

STATUS_FILE="${STATUS_FILE:-/var/tmp/tlc-dock-status.txt}"
LOG_FILE="${LOG_FILE:-/var/log/tlc-dock-seed.log}"
LAUNCHDAEMON_PLIST="${LAUNCHDAEMON_PLIST:-/Library/LaunchDaemons/com.tlc.dock.seed.plist}"
ATTEMPT_FILE="${ATTEMPT_FILE:-/var/tmp/tlc-dock-attempt-count.txt}"
MAX_ATTEMPTS_DEFAULT="${MAX_ATTEMPTS_DEFAULT:-6}"
DEFER_FILE="${DEFER_FILE:-/var/tmp/tlc-dock-defer-count.txt}"
MAX_DEFERS_DEFAULT="${MAX_DEFERS_DEFAULT:-24}"

typeset -gA dock_status

load_status() {
  if [[ ! -f "$STATUS_FILE" ]]; then
    return 1
  fi

  local line key value
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    dock_status[$key]="$value"
  done < "$STATUS_FILE"

  return 0
}

latest_log_error() {
  if [[ ! -f "$LOG_FILE" ]]; then
    return 1
  fi

  /usr/bin/awk '
    /dockutil not found|No logged-in console user found|Unable to resolve home directory|Unable to resolve uid|Dock plist not found|Dock reset failed|Failed to add/ { last=$0 }
    END {
      if (last != "") {
        print last
        exit 0
      }
      exit 1
    }
  ' "$LOG_FILE"
}

attempt_count="${MAX_ATTEMPTS_DEFAULT}"
if [[ -f "$ATTEMPT_FILE" ]]; then
  attempt_count="$(/bin/cat "$ATTEMPT_FILE" 2>/dev/null)"
fi

if ! load_status; then
  if error_line="$(latest_log_error)"; then
    printf 'ERROR: status file missing; log_error=%s\n' "$error_line"
    exit 3
  fi

  printf 'ERROR: status file missing\n'
  exit 3
fi

phase="${dock_status[phase]-unknown}"
attempt_count="${dock_status[attempt_count]-$attempt_count}"
max_attempts="${dock_status[max_attempts]-$MAX_ATTEMPTS_DEFAULT}"
retry_pending="${dock_status[retry_pending]-}"
retry_pending_count="${dock_status[retry_pending_count]-0}"
added_apps="${dock_status[added_apps]-}"
dock_reset="${dock_status[dock_reset]-unknown}"
launchdaemon_present="${dock_status[launchdaemon_present]-unknown}"

if [[ "$phase" == "complete" ]]; then
  printf 'OK: complete after %s attempts; dock_reset=%s; added_apps=%s; launchdaemon_present=%s\n' "$attempt_count" "$dock_reset" "${added_apps:-none}" "$launchdaemon_present"
  exit 0
fi

if [[ "$phase" == "waiting_for_chrome" ]]; then
  defer_count="?"
  [[ -f "$DEFER_FILE" ]] && defer_count="$(/bin/cat "$DEFER_FILE" 2>/dev/null)"
  printf 'PENDING: waiting for Google Chrome to install before seeding (defer %s/%s); launchdaemon_present=%s\n' "$defer_count" "$MAX_DEFERS_DEFAULT" "$launchdaemon_present"
  exit 1
fi

if [[ "$phase" == "chrome_wait_exceeded" ]]; then
  printf 'FAILED: Google Chrome never installed within the wait window (~%s min) — check the Chrome app push; launchdaemon_present=%s\n' "$((MAX_DEFERS_DEFAULT * 10))" "$launchdaemon_present"
  exit 2
fi

if [[ "$phase" == "retry_pending" || "$phase" == "running" ]]; then
  printf 'PENDING: attempt %s of %s; waiting_on=%s; launchdaemon_present=%s\n' "$attempt_count" "$max_attempts" "${retry_pending:-none}" "$launchdaemon_present"
  exit 1
fi

if [[ "$phase" == "max_attempts_reached" ]]; then
  printf 'FAILED: max attempts reached at %s; unresolved=%s; launchdaemon_present=%s\n' "$attempt_count" "${retry_pending:-none}" "$launchdaemon_present"
  exit 2
fi

if error_line="$(latest_log_error)"; then
  printf 'ERROR: %s; phase=%s; attempts=%s/%s\n' "$error_line" "$phase" "$attempt_count" "$max_attempts"
  exit 3
fi

printf 'ERROR: unrecognized state; phase=%s; attempts=%s/%s; retry_pending_count=%s\n' "$phase" "$attempt_count" "$max_attempts" "$retry_pending_count"
exit 3
