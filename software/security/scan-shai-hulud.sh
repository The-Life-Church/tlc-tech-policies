#!/bin/bash

# The Life Church — Mini Shai-Hulud npm Worm Scanner
#
# Read-only detection scan for the "Mini Shai-Hulud" self-spreading npm
# supply-chain attack (StepSecurity, 2026). Checks a machine against the
# published indicators of compromise: persistence artifacts, worm files in
# node_modules, compromised package scopes, C2 domains, the ransom-token
# marker, and injected git/workflow artifacts.
#
# This script ONLY reads — it never deletes, revokes, or modifies anything.
# If it flags the ransom npm token, DO NOT revoke it: isolate the machine and
# image it first (revoking is the wipe trigger).
#
# IOC source:
#   https://www.stepsecurity.io/blog/mini-shai-hulud-is-back-a-self-spreading-supply-chain-attack-hits-the-npm-ecosystem
#
# ===== Mosyle ================================================================
#   Paste-ready block: this folder's README.
#   Name: TLC Security — Mini Shai-Hulud Scan · run as LOGGED-IN USER ($HOME must resolve)
#   On-demand or recurring · scope: dev / vibe-coder Macs
#   Does: read-only scan for Shai-Hulud npm-worm indicators — installs nothing (exit 2 = findings)
# =============================================================================
#
# Usage (local):
#   ./scan-shai-hulud.sh [scan-root ...]      # defaults to $HOME
#
# Exit codes (Mosyle-friendly):
#   0  clean — no indicators found
#   2  INDICATORS FOUND — review the log immediately
#   3  scan error (could not run cleanly)
#
# The GitHub-account side of the worm (marker repos, worm branches, the
# voicproducoes follower) is NOT covered here — that needs an authenticated
# `gh` session per user. See README.md in this directory for the gh commands.

set -uo pipefail

SCAN_ROOTS=("${@:-$HOME}")
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="/tmp/shai-hulud-scan-${TIMESTAMP}.log"
HOSTNAME=$(scutil --get ComputerName 2>/dev/null || hostname)
FINDINGS=0

log() { echo "$@" | tee -a "$LOG_FILE"; }
flag() { FINDINGS=$((FINDINGS + 1)); log "  [!] INDICATOR: $*"; }
ok()   { log "  [ok] $*"; }

log "==================================================================="
log " Mini Shai-Hulud npm worm scan"
log " Host: ${HOSTNAME}   Time: ${TIMESTAMP}"
log " Scan roots: ${SCAN_ROOTS[*]}"
log " Log: ${LOG_FILE}"
log "==================================================================="

# --- 1. Fixed-path persistence artifacts (macOS + cross-platform) -----------
log ""
log "[1/8] Persistence artifacts"
for p in \
  "$HOME/Library/LaunchAgents/com.user.gh-token-monitor.plist" \
  "$HOME/.local/bin/gh-token-monitor.sh" \
  "$HOME/.config/systemd/user/gh-token-monitor.service"
do
  [ -e "$p" ] && flag "persistence file present: $p"
done
# Any LaunchAgent referencing the worm's monitor
if ls "$HOME"/Library/LaunchAgents/ 2>/dev/null | grep -iqE "gh-token-monitor|tanstack"; then
  flag "suspicious LaunchAgent name in ~/Library/LaunchAgents/"
fi
[ "$FINDINGS" -eq 0 ] && ok "no persistence artifacts"

# --- 2. Worm runtime files (find across scan roots) -------------------------
log ""
log "[2/8] Worm runtime files (router_init.js / tanstack_runner.js / *.mjs droppers)"
PRE=$FINDINGS
while IFS= read -r f; do
  [ -n "$f" ] && flag "worm file: $f"
done < <(find "${SCAN_ROOTS[@]}" -type f \
          \( -name "router_init.js" -o -name "tanstack_runner.js" \) 2>/dev/null)
# .claude / .vscode dropper persistence
while IFS= read -r f; do
  [ -n "$f" ] && flag "dropper persistence: $f"
done < <(find "${SCAN_ROOTS[@]}" -type f \
          \( -name "router_runtime.js" -o -name "setup.mjs" \) 2>/dev/null \
          | grep -E "/\.claude/|/\.vscode/")
[ "$FINDINGS" -eq "$PRE" ] && ok "no worm runtime/dropper files"

# --- 3. Marker package @tanstack/setup --------------------------------------
log ""
log "[3/8] Marker package @tanstack/setup"
PRE=$FINDINGS
while IFS= read -r d; do
  [ -n "$d" ] && flag "@tanstack/setup installed at: $d"
done < <(find "${SCAN_ROOTS[@]}" -type d -path "*/node_modules/@tanstack/setup" 2>/dev/null)
[ "$FINDINGS" -eq "$PRE" ] && ok "@tanstack/setup not present"

# --- 4. C2 domains / attacker handle in any project file --------------------
log ""
log "[4/8] C2 domains & attacker infrastructure references"
PRE=$FINDINGS
# Scope to the file types the worm actually writes (JS/JSON/npmrc). This both
# speeds the scan up and avoids matching detection tooling and docs (including
# this script) that legitimately list the IOC strings.
while IFS= read -r f; do
  [ -n "$f" ] && flag "C2/attacker reference in: $f"
done < <(grep -rIl -E "api\.masscan\.cloud|git-tanstack\.com|getsession\.org|voicproducoes|79ac49eedf774dd4b0cfa308722bc463cfe5885c" \
          "${SCAN_ROOTS[@]}" \
          --include='*.js' --include='*.mjs' --include='*.cjs' --include='*.ts' \
          --include='*.json' --include='.npmrc' 2>/dev/null)
[ "$FINDINGS" -eq "$PRE" ] && ok "no C2 domains or attacker references"

# --- 5. github: optionalDependencies injection ------------------------------
log ""
log "[5/8] Injected github: optionalDependencies"
PRE=$FINDINGS
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if grep -A6 '"optionalDependencies"' "$f" 2>/dev/null | grep -q 'github:'; then
    flag "github: optionalDependency in: $f"
  fi
done < <(grep -rIl '"optionalDependencies"' "${SCAN_ROOTS[@]}" --include=package.json 2>/dev/null)
[ "$FINDINGS" -eq "$PRE" ] && ok "no injected github: optionalDependencies"

# --- 6. Ransom npm token marker ---------------------------------------------
log ""
log "[6/8] Ransom npm-token marker (DO NOT revoke if found — isolate first)"
PRE=$FINDINGS
if grep -rIqs "IfYouRevokeThisToken" "$HOME/.npmrc" "$HOME/.config" 2>/dev/null; then
  flag "ransom-token marker present — DO NOT revoke, isolate machine and image it"
fi
[ "$FINDINGS" -eq "$PRE" ] && ok "no ransom-token marker"

# --- 7. Injected GitHub Actions workflow ------------------------------------
log ""
log "[7/8] Injected codeql_analysis.yml workflow"
PRE=$FINDINGS
while IFS= read -r f; do
  [ -n "$f" ] && flag "injected workflow: $f"
done < <(find "${SCAN_ROOTS[@]}" -type f -path "*/.github/workflows/codeql_analysis.yml" 2>/dev/null)
[ "$FINDINGS" -eq "$PRE" ] && ok "no injected codeql_analysis.yml"

# --- 8. Worm git commits / branches in local repos --------------------------
log ""
log "[8/8] Worm git artifacts (commits as claude noreply, dune-word branches)"
PRE=$FINDINGS
while IFS= read -r gitdir; do
  [ -z "$gitdir" ] && continue
  repo=$(dirname "$gitdir")
  if git -C "$repo" log --all --author="claude@users.noreply.github.com" --oneline 2>/dev/null \
       | grep -iq "update dependencies"; then
    flag "worm commit ('chore: update dependencies' as claude) in: $repo"
  fi
  if git -C "$repo" branch -a 2>/dev/null \
       | grep -iqE "fremen|melange|sandworm|harkonnen|atreides|shai-hulud|dependabot/github_actions/format"; then
    flag "worm branch pattern in: $repo"
  fi
done < <(find "${SCAN_ROOTS[@]}" -type d -name .git 2>/dev/null)
[ "$FINDINGS" -eq "$PRE" ] && ok "no worm git artifacts"

# --- Verdict ----------------------------------------------------------------
log ""
log "==================================================================="
if [ "$FINDINGS" -eq 0 ]; then
  log " RESULT: CLEAN — no Mini Shai-Hulud indicators on ${HOSTNAME}"
  log "==================================================================="
  exit 0
else
  log " RESULT: ${FINDINGS} INDICATOR(S) FOUND on ${HOSTNAME} — review ${LOG_FILE}"
  log " If the ransom npm token was flagged, DO NOT revoke it. Isolate first."
  log "==================================================================="
  exit 2
fi
