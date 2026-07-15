# Security scans

Ad-hoc, read-only detection scripts for known supply-chain / endpoint threats.
These **only read** — they never delete, revoke, quarantine, or modify
anything. Remediation is always a deliberate human step.

## `scan-shai-hulud.sh` — Mini Shai-Hulud npm worm scanner

Checks a Mac against the published indicators of compromise for the
**"Mini Shai-Hulud"** self-spreading npm supply-chain attack
([StepSecurity writeup](https://www.stepsecurity.io/blog/mini-shai-hulud-is-back-a-self-spreading-supply-chain-attack-hits-the-npm-ecosystem)).

### What it checks (8 passes)

1. **Persistence** — `gh-token-monitor` LaunchAgent / script / systemd unit
2. **Worm runtime files** — `router_init.js`, `tanstack_runner.js`, and `.claude/`/`.vscode/` `*.mjs` droppers
3. **Marker package** — `@tanstack/setup` in any `node_modules`
4. **C2 / attacker infra** — `api.masscan.cloud`, `git-tanstack.com`, `getsession.org`, the `voicproducoes` handle, the fork commit hash (scoped to `.js`/`.json`/`.npmrc`)
5. **Injected deps** — `github:` URLs in `optionalDependencies`
6. **Ransom token** — the `IfYouRevokeThisToken…` npm-token marker
7. **Injected workflow** — `.github/workflows/codeql_analysis.yml`
8. **Git artifacts** — worm commits (`chore: update dependencies` as `claude@users.noreply.github.com`) and dune-word branches (`fremen`, `melange`, `sandworm`, …)

### Run it

```bash
# Scan $HOME (default)
curl -fsSL https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/security/scan-shai-hulud.sh | bash

# Or scan specific roots locally
./scan-shai-hulud.sh ~/TLC_Dev /some/other/path
```

**Exit codes:** `0` clean · `2` indicators found · `3` scan error.
Full log is written to `/tmp/shai-hulud-scan-<timestamp>.log`.

### Mosyle

Scripts → Custom Command, run **as the logged-in user** (so `$HOME` resolves),
scoped to dev / vibe-coder Macs. Mosyle surfaces the non-zero exit so a `2`
flags the machine for follow-up.

```bash
#!/bin/bash
# TLC Security — Mini Shai-Hulud Scan
# Does: read-only scan for Shai-Hulud npm-worm indicators — installs nothing (exit 2 = findings)
# run as LOGGED-IN USER ($HOME must resolve) · on-demand or recurring · scope: dev / vibe-coder Macs
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/security/scan-shai-hulud.sh" | bash
```

### ⚠️ If it flags the ransom token

**Do not revoke it.** Revoking the `IfYouRevokeThisToken…` npm token is the
worm's wipe trigger. Isolate the machine from the network and image it before
touching any credential.

### Not covered: the GitHub-account side

The worm also exfiltrates by creating public repos and pushing branches under
the victim's GitHub account. That needs an authenticated `gh` session per user,
so it's out of scope for an unattended Mosyle run. Check it by hand:

```bash
# Marker repos under the org / your account
gh api "orgs/The-Life-Church/repos?per_page=100&sort=created&direction=desc" \
  --jq '.[] | "\(.created_at[0:10])  \(.visibility)  \(.name)"'
gh api "user/repos?per_page=100&sort=created&affiliation=owner" \
  --jq '.[].full_name'

# Worm branches across all org repos
for r in $(gh api "orgs/The-Life-Church/repos?per_page=100" --jq '.[].name'); do
  gh api "repos/The-Life-Church/$r/branches?per_page=100" --jq '.[].name' 2>/dev/null \
    | grep -iE "fremen|melange|sandworm|harkonnen|atreides|shai|hulud|dependabot/github_actions/format" \
    | sed "s#^#$r: #"
done

# Attacker following you?
gh api users/<your-login>/followers --jq '.[].login' | grep -i voicproducoes
```

Look for repos named *"Shai-Hulud"*, *"Mini Shai-Hulud has Appeared"*, or
*"…Migration"*, any unexpected new public repo, and the `voicproducoes` account.

---

*Maintained by The Life Church IT/Dev team.*
