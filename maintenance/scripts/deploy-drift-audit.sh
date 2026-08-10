#!/bin/bash
# deploy-drift-audit.sh — for every active org repo, report whether the branch a
# deploy workflow ships is actually the branch that was last deployed, plus any
# non-success runs in a recent window.
#
# NOT a Mosyle script. Runs from a maintainer's machine against the GitHub API.
# Requires: gh (authenticated), python3.
#
# Usage:
#   ./deploy-drift-audit.sh                 # all active repos
#   ./deploy-drift-audit.sh --since 2026-08-06
#   ./deploy-drift-audit.sh --repo tlc-resources --repo newsletter-tool
#
# Method and the three ways to misread the output are documented in
# ../runbooks/deploy-drift-audit.md. Short version: compare a deploying branch's
# tip SHA against the headSha of that workflow's last SUCCESSFUL run. Anything
# else (run lists, "latest run green") does not tell you what is live.

set -uo pipefail

ORG="The-Life-Church"
SINCE=""
REPOS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --since) SINCE="${2:-}"; shift 2 ;;
    --repo)  REPOS+=("${2:-}"); shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v gh >/dev/null || { echo "gh not found" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh is not authenticated — run: gh auth login" >&2; exit 1; }

# Workflow names that deploy, per repo. A name containing "deploy" or "release" is
# NOT a reliable signal — MPNext's "Release on main" and "Announce release in
# Google Chat" ship nothing — so the mapping is explicit, and the branch each one
# deploys is recorded with it. Keep in sync with ../repo-inventory.md.
#   format: repo|workflow file or name|branch it deploys
DEPLOYERS='
tlc-resources|deploy.yml|main
newsletter-tool|deploy.yml|main
tlc-checkin-landing|Deploy to Firebase Hosting|main
tlc-wall-boxes|firebase-hosting-merge.yml|main
wp-content|Deploy to WP Engine Production|main
wp-content|Deploy to WP Engine Staging|stage
MPNext|Deploy → prod (main)|main
MPNext|Deploy → test (stage)|stage
'

if [ "${#REPOS[@]}" -eq 0 ]; then
  while IFS= read -r r; do REPOS+=("$r"); done < <(
    gh repo list "$ORG" --limit 200 --json name,isArchived \
      --jq '.[]|select(.isArchived==false)|.name' | sort
  )
fi

in_list() { local needle="$1"; shift; for x in "$@"; do [ "$x" = "$needle" ] && return 0; done; return 1; }

echo "=============================================================================="
echo "A. DEPLOY DRIFT — branch tip vs last SUCCESSFUL deploy"
echo "=============================================================================="
printf '%s\n' "$DEPLOYERS" | while IFS='|' read -r repo wf branch; do
  [ -z "${repo:-}" ] && continue
  in_list "$repo" "${REPOS[@]}" || continue

  tip=$(gh api "repos/$ORG/$repo/branches/$branch" --jq '.commit.sha[0:7]' 2>/dev/null)
  [ -z "$tip" ] && { printf '  %-22s %-26s no such branch: %s\n' "$repo" "$wf" "$branch"; continue; }

  last_ok=$(gh run list --repo "$ORG/$repo" --workflow "$wf" --branch "$branch" --limit 20 \
    --json conclusion,headSha,createdAt \
    --jq 'map(select(.conclusion=="success"))|.[0]|"\(.headSha[0:7]) \(.createdAt[0:16])"' 2>/dev/null)

  if [ -z "$last_ok" ] || [ "$last_ok" = "null null" ]; then
    printf '  %-9s %-22s %-26s tip=%s  (no successful run found)\n' "UNKNOWN" "$repo" "$wf" "$tip"
    continue
  fi

  ok_sha=${last_ok%% *}
  if [ "$ok_sha" = "$tip" ]; then
    printf '  %-9s %-22s %-26s %s @ %s\n' "IN-SYNC" "$repo" "$wf/$branch" "$tip" "${last_ok#* }"
  else
    printf '  %-9s %-22s %-26s tip=%s  last_ok=%s\n' "*DRIFT*" "$repo" "$wf/$branch" "$tip" "$last_ok"
    echo   "             ↳ inspect: gh api repos/$ORG/$repo/compare/$ok_sha...$branch --jq '{ahead:.ahead_by,files:[.files[].filename]}'"
  fi
done

if [ -n "$SINCE" ]; then
  echo
  echo "=============================================================================="
  echo "B. NON-SUCCESS RUNS since $SINCE  (newest run per workflow, at branch tip)"
  echo "=============================================================================="
  for r in "${REPOS[@]}"; do
    tip=$(gh api "repos/$ORG/$r/commits/HEAD" --jq '.sha[0:7]' 2>/dev/null)
    out=$(gh run list --repo "$ORG/$r" --limit 40 \
            --json workflowName,conclusion,status,headSha,headBranch,createdAt,databaseId 2>/dev/null |
      SINCE="$SINCE" TIP="$tip" python3 -c '
import json,os,sys
since=os.environ["SINCE"]; tip=os.environ["TIP"]
try: runs=json.load(sys.stdin)
except Exception: sys.exit()
seen={}
for x in runs:
    if x["createdAt"][:10] < since: continue
    seen.setdefault(x["workflowName"], x)          # newest wins, list is desc
for wf,x in seen.items():
    c = x["conclusion"]
    if c in ("success","skipped","neutral"): continue
    at_tip = " <-- AT TIP" if x["headSha"][:7]==tip else ""
    print(f"     {c or x[\"status\"]:<12} {wf:<26} {x[\"headBranch\"]:<28} {x[\"headSha\"][:7]}  id={x[\"databaseId\"]}{at_tip}")
')
    [ -n "$out" ] && { printf '  %s (tip %s)\n' "$r" "$tip"; printf '%s\n' "$out"; }
  done
  echo
  echo "  Reminders: a cancelled run is not a failed run (check jobs[].steps);"
  echo "  a run queued with zero jobs is a zombie (gh run cancel);"
  echo "  and 'no checks reported' on a PR is worse than a red X, not better."
fi

echo
echo "App Hosting deploys never appear above — check them separately:"
echo "  firebase apphosting:backends:list --project the-life-church-apps"
echo "  (ABIU=Disabled means merging deploys nothing.)"
