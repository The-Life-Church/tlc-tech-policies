# HyperFrames CLI — Silent Installer

This folder installs the [HyperFrames](https://github.com/heygen-com/hyperframes) CLI (the npm package `hyperframes`) on opted-in Life Church Macs via Mosyle. HyperFrames is HeyGen's open-source (Apache-2.0) "write HTML, render video" toolchain: agents author HTML compositions, the CLI renders them to MP4 locally with headless Chrome + FFmpeg. Staff and Claude never run upstream's `npx hyperframes` / `npx skills add` — those are blocked on TLC machines. This is the IT-managed path: pinned version, system-wide global install; the CLI provisions its own headless browser.

---

## What It Does

Installs the pinned `hyperframes` npm package into the fleet Node's **global** prefix (`/usr/local/lib/node_modules`, binary at `/usr/local/bin/hyperframes`), so the CLI is on `PATH` for every user and the on-device skills can call `hyperframes` directly instead of `npx`.

**Version pinning.** `HYPERFRAMES_VERSION` is pinned at the top of `install.sh`. Unlike the Higgsfield CLI (a single unsigned binary pinned by SHA), HyperFrames ships as an **npm package** — integrity is the exact-version pin + the npm registry, not a per-arch checksum. Bumps arrive as PRs from the npm job in `bump-pins.yml` (14-day cooldown).

**Headless browser is self-managed — we do NOT reuse the fleet Chrome.** HyperFrames renders by seeking frames in headless Chrome (Puppeteer) and encoding with FFmpeg. The CLI provisions its own browser: on first render it downloads the Puppeteer-matched `chrome-headless-shell` into the invoking user's `~/.cache/puppeteer`. We deliberately leave it that way rather than pointing it at the installed Google Chrome — reusing fleet Chrome would only save a one-time, cached, per-user download (and only on machines that already have working npm egress, or the install itself wouldn't have succeeded), while adding version skew against Puppeteer's known-good build and an unverified render path. The version-matched self-download is the more reliable default. If per-user download/disk ever becomes measured pain, the clean fix is pre-seeding one shared `chrome-headless-shell` (`@puppeteer/browsers` + a shared `PUPPETEER_CACHE_DIR`), not a per-user Chrome wrapper.

**Node ≥ 22, FFmpeg + ffprobe, and the GitHub CLI are bootstrapped automatically.** The CLI's runtime is Node ≥ 22; renders shell out to system `ffmpeg` (encode) and `ffprobe` (media probing). None are bundled. Node is bootstrapped via `software/node/install.sh` when missing or too old; `software/ffmpeg/install.sh` and `software/gh/install.sh` run **unconditionally on every run** — both are idempotent at their pins (SHA / version), so hosts with a brew or manual copy still converge to the reviewed pinned binaries, and gh pin bumps reach machines that only get this script (the standalone gh script is a manual-run deploy; gh itself isn't a render need — it's how staff clone org repos and reach the private plugin marketplace). So a single Mosyle script stands up the whole chain, and all three stay independently deployable for hosts that want them without HyperFrames.

**The CLI's self-updater is disabled.** Upstream hyperframes schedules its own `npm install -g hyperframes@latest` from inside the CLI, which would bypass the 14-day reviewed pin (or fail noisily where the global prefix isn't user-writable). The installer replaces npm's bin symlink with a tiny wrapper that sets `HYPERFRAMES_NO_UPDATE_CHECK` + `HYPERFRAMES_NO_AUTO_INSTALL` and execs the real entry point. npm recreates the symlink on every (re)install, so the installer re-wraps right after — updates arrive only as reviewed pin-bump PRs.

**Auth ships nothing.** Local rendering needs no key and no account. (The hosted HyperFrames MCP — cloud render on HeyGen credits — is a different product; see "The MCP alternative" below.)

**Guarantees:**
- Idempotent — skips the CLI reinstall if the pinned version is present, and skips the skills install if they're already in the user's dir; the ffmpeg and gh bootstraps always run but no-op at their pins once converged
- Skills success is verified, not assumed — requires Xcode CLT (git) up front, and checks `~/.claude/skills/hyperframes` actually exists after the install (the upstream skills step can exit 0 while skipping internally)
- Reinstalls the CLI on version mismatch (up- or downgrade)
- Fails loudly if Node is older than the required major, if the ffmpeg bootstrap fails, or if the CLI won't run after install; the **skills** step is best-effort (WARN + retry next run, never fatal)
- `npm install -g` wrapped in `timeout 600`; per-run log at `/tmp/hyperframes-install-<timestamp>.log` (removed on success, kept on failure)

**Exit codes:**

| Code | Meaning |
|---|---|
| 0 | `hyperframes` present at the pinned version; ffmpeg + ffprobe satisfied |
| 1 | Install failure, or a hard prerequisite unmet (Node too old, or the ffmpeg bootstrap failed) |

---

## The toolchain — what a machine actually needs

| Layer | Provided by | Notes |
|---|---|---|
| **Node ≥ 22** | `software/node/` (fleet-wide) | The CLI's runtime + global install target. Auto-bootstrapped by this installer if missing or too old |
| **FFmpeg + ffprobe** | `software/ffmpeg/` (pinned static build) | Encode + media probe — shelled out, not bundled. Auto-bootstrapped by this installer if missing |
| **Headless browser** | the `hyperframes` CLI (self-provisioned) | `chrome-headless-shell` downloaded per-user into `~/.cache/puppeteer` on first render — Puppeteer-version-matched, not the fleet Chrome |
| **`hyperframes` CLI** | this installer | Global npm package, pinned |
| **The ~20 skills** | this installer (`hyperframes skills`, dropped to the console user) | Installed into the user's `~/.claude/skills` (+ other AI-tool dirs) after the CLI lands. **Live-latest — no cooldown**: the CLI force-refreshes them at runtime (upstream neutered `--skip-skills`), so only the CLI *version* is cooldown-pinned |

We deliberately do **not** ship HyperFrames as a `tlc-claude-plugins` marketplace plugin: the skills are inert without this local toolchain, and the CLI force-updates them at runtime anyway, so vendoring them with a cooldown (the Higgsfield model) doesn't hold here.

---

## Scope — opt-in only

**Not fleet-wide.** Scope the Mosyle script to machines that actually make videos: the creative team and IT-dev. Same posture as the Higgsfield CLI.

---

## Deployment

Mosyle → **Custom Scripts → Add Script**

**HyperFrames CLI Install**
- Run as: `root`
- Schedule: Once or recurring (idempotent — recurring picks up version bumps merged to `main`)
- Scope: Creative team / IT-dev opt-in group — **not fleet-wide**
- Depends on: **nothing external** — Node and ffmpeg/ffprobe both self-bootstrap from the repo if missing, and the skills + routing rule install for the logged-in user. This is the **one** script Mosyle needs for the whole toolchain.

**Paste into Mosyle's Custom Script box** (the shebang is required — Mosyle writes the body to a file and executes it):
```bash
#!/bin/bash
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/hyperframes/install.sh" | bash
```

**To test on your own Mac** — the install writes to the global npm prefix (needs root):
```bash
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/hyperframes/install.sh" | sudo bash
```

**Verify:**
```bash
hyperframes --version
ffmpeg -version | head -1
ffprobe -version | head -1
hyperframes skills check          # skills installed + current
```

**Egress note:** `npm install -g` pulls from `registry.npmjs.org` plus prebuilt-binary hosts for the native deps (`sharp`, `onnxruntime-node`, `puppeteer-core`). The CLI talks to no HeyGen service for local renders.

---

## Making the skills call the CLI, not `npx`

The installed skills call `npx hyperframes …` throughout (~340 references), and `npx` is blocked on TLC machines. The skills defer to a project/user `CLAUDE.md` or `AGENTS.md` describing the workflow, so the fix is a one-line directive: **"call the global `hyperframes` binary directly; drop the `npx ` prefix — `npx` is blocked here."** (With `hyperframes` on `PATH`, `npx hyperframes` would just run the global binary anyway — the only problem is `npx` itself being denied, so dropping the prefix is all it takes.) **Where this directive is delivered fleet-wide is the remaining decision** (see below): the managed policy (`software/claude/CLAUDE.md`, loaded every session) is the simplest always-loaded home; a per-user `~/.claude/CLAUDE.md` drop is the alternative.

---

## The MCP alternative (why you might not need any of this)

HyperFrames also ships a **hosted MCP connector** (`https://mcp.heygen.com/mcp/hyperframes`, the "HyperFrames by HeyGen" entry in the Claude connector catalog): zero local install, renders in HeyGen's cloud, OAuth to a HeyGen account, consumes render credits. Upstream's own framing: *"The CLI gives you full control of rendering and runtime; the MCP gives you instant authoring with cloud rendering."*

This installer is the **local** path — chosen for no per-render cost, offline rendering, and data staying on the machine. If those don't matter for a given use case, the connector does the same authoring with nothing installed.

---

## Updating the pinned version

Intended to be automatic once the npm job is added to `bump-pins.yml`: it opens a PR bumping `HYPERFRAMES_VERSION` once a newer npm release is ≥14 days old. Manual path meanwhile:

1. `npm view hyperframes version` (and skim the [releases](https://github.com/heygen-com/hyperframes/releases))
2. Update `HYPERFRAMES_VERSION` in `install.sh`, open a PR
3. Devices converge on their next recurring Mosyle run

> Note: the *skills* the CLI pulls are not pinned by this bump — they self-update at runtime (see the toolchain table). Only the CLI binary version is under cooldown control.

---

## Still to build

- **Routing directive delivery** — the "call `hyperframes`, not `npx`" instruction (above) needs a fleet home: a line in the managed policy (`software/claude/CLAUDE.md`), or a per-user `~/.claude/CLAUDE.md` drop from this installer. Until then the installed skills fire `npx` and hit the deny. (On the dev box it's set user-global by hand.)

_Landed:_ `software/ffmpeg/` (ffmpeg + ffprobe, pinned); this installer now **bootstraps ffmpeg and installs the skills** (console-user drop) — one Mosyle script for the whole toolchain; dedicated `hyperframes` (npm) + `ffmpeg` (download-and-hash) `bump-pins.yml` jobs. Verified end-to-end with a real render.
