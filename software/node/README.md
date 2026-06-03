# Node.js — Silent Installer

This folder contains the silent installer for Node.js, deployed to Life Church Macs via Mosyle. It installs the official Node LTS universal `.pkg` from nodejs.org — signed and notarized by the Node.js Foundation.

---

## What It Does

Downloads the pinned `node-<ver>.pkg` (universal — arm64 + x64 in one artifact) from nodejs.org, verifies its SHA-256 against a hash pinned in the script, and installs it with `installer -pkg -target /` as root. Lands `node`, `npm`, and `npx` in `/usr/local/bin`, system-wide — visible to user shells and root/MDM contexts alike.

**Version pinning.** `NODE_VERSION` and `NODE_SHA256` are pinned at the top of `install.sh`. Bumping Node (e.g. for a security release) is a two-line PR; devices converge on the next recurring run. Pinning the SHA in the script (instead of fetching `SHASUMS256.txt` at runtime) means a compromised download can't pass silently — a hash change has to come through a reviewed PR. No silent drift, no "whatever latest was that day."

**Guarantees:**
- Idempotent — exits 0 immediately if the pinned version is already installed
- Reinstalls if the installed version differs from the pin (up- or downgrade)
- Checksum-verified before `installer` runs; refuses on mismatch
- Download and install each wrapped in `timeout 900` (15 min)
- Warns if a Homebrew node exists at `/opt/homebrew/bin/node` (it would shadow `/usr/local/bin/node` in brew-managed user shells)
- Logs to `/tmp/node-install-<timestamp>.log` — cleaned up on success, kept on failure

**Exit codes:**

| Code | Meaning |
|---|---|
| 0 | Node present at the pinned version (already installed, or installed now) |
| 1 | Download, checksum, or install failure |

---

## Scope — who actually needs this

**Not fleet-wide.** The Claude Code desktop app and native installer are self-contained binaries — they do not need Node. Node's consumers at TLC are:

- **IT-dev machines** — general dev tooling
- **Vibe coder machines** — repo tooling (husky, prettier, eslint) and `npx`

Scope the Mosyle script to those groups only. If a broader need appears later, the script doesn't change — just the scope.

### Things to know before widening scope

- **`npx` runs arbitrary registry code.** Claude Code's `managed-settings.json` denies `npx` (and the pnpm/yarn/bun equivalents), but the vibe-coder *shell* policy blocks only `npm install <pkg>` — a user typing `npx <pkg>` in Terminal still downloads *and executes* packages on the fly. Decide whether that's acceptable for the group before deploying Node to it.
- **Supply-chain surface grows with every Node machine.** Schedule `software/security/scan-shai-hulud.sh` recurring on the same Mosyle group that gets this script.
- **`npm install -g` won't work for users by design.** The pkg installs `/usr/local/lib/node_modules` root-owned; global installs need sudo, which is blocked for vibe coders. `npx` is unaffected (per-user cache). Expect the occasional EACCES question — it's intentional.

---

## Files

- `install.sh` — Mosyle script. Downloads, verifies, and installs the pinned Node LTS release as root.

---

## Deployment

Mosyle → **Custom Scripts → Add Script**

**Node Install**
- Run as: `root`
- Schedule: **Recurring, weekly — required.** Recurring runs are the entire update path: merged pin bumps from `bump-pins.yml` only reach a device when this script re-runs. A one-time install freezes that machine at install-day Node forever. Weekly runs are effectively free — current devices exit 0 in ~1 second, no download.
- Scope: **Just the users who need it.** Not fleet-wide, and not even necessarily a whole device group — if only one or two people run node tooling or `npx`, scope to exactly those machines and let the recurring schedule handle the rest. No reason to put Node (and its npm supply-chain surface) on 150 Macs for two users. Widen the scope when someone new needs it; the script doesn't change.

**Paste into Mosyle's Custom Script box** (the shebang is required — Mosyle writes the body to a file and executes it):
```bash
#!/bin/bash
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/node/install.sh" | bash
```

**To test on your own Mac** — open Terminal and paste just the `curl` line (no shebang — zsh will try to run `#!/bin/bash` as a command and error out):
```bash
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/node/install.sh" | bash
```

**No prerequisites.** Node doesn't need CLT or a logged-in user.

**Verify:**
```bash
node --version && npx --version
```

If the install fails, the log at `/tmp/node-install-*.log` is kept for diagnosis.

**Egress note:** the download comes from `nodejs.org`. Anything `npx` fetches at runtime also needs `registry.npmjs.org`. Both must be reachable through any web filtering.

**PATH note for Mosyle scripts:** `/usr/local/bin` is on the default PATH for user shells (via `/etc/paths`) but not guaranteed in Mosyle's stripped root-shell context. Any Mosyle script that calls Node should use absolute paths: `/usr/local/bin/node`, `/usr/local/bin/npx`.

---

## Updating the pinned version

1. Find the current LTS at <https://nodejs.org/dist/> (or `https://nodejs.org/dist/index.json`, first entry with `"lts"`)
2. Copy the `node-<ver>.pkg` line from `https://nodejs.org/dist/<ver>/SHASUMS256.txt`
3. Branch, update `NODE_VERSION` and `NODE_SHA256` in `install.sh`, open a PR
4. Get one reviewer to approve, merge to `main`
5. Devices reinstall to the new pin on their next scheduled run

Node LTS lines get security releases a few times a year — watch the [nodejs.org blog](https://nodejs.org/en/blog) or the security mailing list for release announcements.

---

## Why the official pkg and not Homebrew / nvm?

- **Homebrew** is per-user, refuses to run as root, and upgrades on a rolling cadence — invisible to the root MDM context and version-churny. IT-dev machines that have brew can use it for themselves; the fleet baseline comes from this script.
- **nvm** installs into a user home directory — also invisible to root/MDM, and per-user by design.
- **The official pkg** is system-wide, root-friendly, universal (one artifact for both architectures), signed and notarized by the Node.js Foundation, and version-pinnable. It's the only one of the three built for this job.
