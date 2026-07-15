# FFmpeg (static) — Silent Installer

This folder installs a pinned static [FFmpeg](https://ffmpeg.org/) binary on opted-in Life Church Macs via Mosyle. It exists as the **encoder half of the HyperFrames toolchain** (`software/hyperframes/`) — HyperFrames seeks frames in headless Chrome and pipes them through `ffmpeg` to produce MP4s, so `hyperframes/install.sh` treats `ffmpeg` on `PATH` as a hard prerequisite and exits non-zero until this has run. Staff and Claude never `brew install ffmpeg` — this is the IT-managed path: pinned version, per-arch checksum verification, root install.

---

## What It Does

Downloads the pinned per-arch macOS `ffmpeg` **and** `ffprobe` binaries from the [`eugeneware/ffmpeg-static`](https://github.com/eugeneware/ffmpeg-static) GitHub release (`{ffmpeg,ffprobe}-darwin-{arm64,x64}`), verifies each against its matching pinned SHA-256, and installs them to `/usr/local/bin/`.

**Version pinning.** `FFMPEG_VERSION` + two per-arch SHAs are pinned at the top of `install.sh`. `FFMPEG_VERSION` is the `ffmpeg-static` **package** release (the GitHub tag `b<version>`), **not** the ffmpeg version — that project's semver is its own, and `b6.1.1` bundles **ffmpeg 6.0** (fine for HyperFrames' encoding). The binaries are bare, **unsigned** static builds and **upstream publishes no checksums file** — so the pinned SHAs (computed from the release artifacts and reviewed into the script) are the *only* integrity check. Never remove them. Bumps arrive as PRs from the `ffmpeg` job in `bump-pins.yml`.

**Idempotency is by SHA, not version text.** The installed binary's SHA-256 is compared to the pin; a match is a no-op. `ffmpeg -version`'s exact wording (which varies across static builds) is used only as a post-install smoke test that the binary runs — never as the "already installed" gate. This avoids re-downloading 45–80 MB on every recurring run.

**ffprobe is installed alongside ffmpeg.** HyperFrames requires `ffprobe` to probe media assets (durations/dimensions of audio/video inputs) — `hyperframes doctor` lists it as required, not optional. It comes from the same release (`ffprobe-darwin-*`), pinned per-arch like ffmpeg, and installs to `/usr/local/bin/ffprobe`.

**Guarantees:**
- Idempotent — exits 0 fast if the pinned binary (by SHA) is already at `/usr/local/bin/ffmpeg`
- Reinstalls on SHA mismatch (up- or downgrade)
- Checksum-verified before install; refuses on mismatch; fails loudly if the asset isn't a Mach-O binary (upstream layout change)
- Download wrapped in `timeout 600`; work dir cleaned by `trap`
- Logs to `/tmp/ffmpeg-install-<timestamp>.log` — cleaned on success, kept on failure

**Exit codes:**

| Code | Meaning |
|---|---|
| 0 | ffmpeg + ffprobe present at the pinned build (already installed, or now) |
| 1 | Download, checksum, or install failure (or unsupported arch / not root) |

---

## Scope — opt-in only

**Not fleet-wide.** Scope the Mosyle script to the machines that make videos — the creative team and IT-dev — the same group as `software/higgsfield/` and `software/hyperframes/`. This installer is a **prerequisite for HyperFrames**: any Mac in the HyperFrames scope needs this one too. You often don't deploy this separately at all: `software/hyperframes/install.sh` fetches and runs it automatically (from this repo's `main`) when `ffmpeg`/`ffprobe` are missing. Deploy it standalone only for hosts that want ffmpeg without HyperFrames.

---

## Files

- `install.sh` — Mosyle script. Downloads, verifies, and installs the pinned static `ffmpeg` as root.

---

## Deployment

Mosyle → **Custom Scripts → Add Script**

**FFmpeg (static) Install**
- Run as: `root`
- Schedule: Once or recurring (idempotent — recurring picks up version bumps merged to `main`)
- Scope: Creative team / IT-dev opt-in group — **not fleet-wide**. Deploy alongside `software/hyperframes/`.

**Paste into Mosyle's Custom Script box** (the shebang is required — Mosyle writes the body to a file and executes it):
```bash
#!/bin/bash
# TLC FFmpeg (static) — Silent Install
# Installs: ffmpeg + ffprobe static binaries only (pinned per-arch SHAs)
# Usually arrives via the HyperFrames script — deploy alone only when needed without it
# root · once or recurring · scope: creative / IT-dev (opt-in)
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/ffmpeg/install.sh" | bash
```

**Self-Service catalog item (with progress window)** — background/recurring entries keep the silent block above; see [`software/selfservice/`](../selfservice/README.md):
```bash
#!/bin/bash
# TLC Self-Service — FFmpeg (with progress window)
# Runs the same installer with a swiftDialog progress UI — Self-Service items ONLY.
# root · Self-Service · scope: creative / IT-dev
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/selfservice/with-progress.sh" | bash -s -- ffmpeg "FFmpeg"
```

**To test on your own Mac** — the install writes to `/usr/local/bin`, which needs root; pipe to `sudo bash` (no shebang — zsh would try to run `#!/bin/bash` as a command):
```bash
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/ffmpeg/install.sh" | sudo bash
```

**Verify:**
```bash
ffmpeg -version | head -1
ffprobe -version | head -1
```

**Egress note:** downloads come from `github.com` → `objects.githubusercontent.com`. The binary is fully static and talks to nothing at runtime.

---

## Updating the pinned version

Normally automatic: the `ffmpeg` job in `bump-pins.yml` opens a PR with the new version + both per-arch SHAs once a release is ≥14 days old. Because upstream ships no checksums file, that job **downloads each darwin asset and computes the SHA itself** (it can't awk a checksums file like the GitHub-release matrix does). Manual path:

1. Find the latest release at <https://github.com/eugeneware/ffmpeg-static/releases> (tags are `b<version>`, e.g. `b6.1.1`).
2. Download all four `{ffmpeg,ffprobe}-darwin-{arm64,x64}` assets from that release and run `shasum -a 256` on each.
3. Update `FFMPEG_VERSION` and all four SHAs (`FFMPEG_SHA256_ARM64/AMD64`, `FFPROBE_SHA256_ARM64/AMD64`) in `install.sh`, open a PR.
4. Devices converge on their next recurring Mosyle run.

> Note the tag format: the release tag is `b${FFMPEG_VERSION}` (leading `b`), but `FFMPEG_VERSION` in the script is the bare version — the script prepends the `b` when building the download URL.
