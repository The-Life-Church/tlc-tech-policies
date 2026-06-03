# Higgsfield CLI — Silent Installer

This folder contains the silent installer for the [Higgsfield CLI](https://github.com/higgsfield-ai/cli), deployed to opted-in Life Church Macs via Mosyle. Staff and Claude never run upstream's `curl | sh` — this is the IT-managed path: pinned version, per-arch checksum verification, root install.

---

## What It Does

Downloads the pinned per-arch release tarball (`hf_<ver>_darwin_{arm64,amd64}.tar.gz`) from the official GitHub release, verifies its SHA-256 against the matching pinned hash, and installs the binary as `/usr/local/bin/higgsfield` with a `higgs` symlink.

**Deliberately does NOT install upstream's `hf` shortcut** — it collides with the Hugging Face CLI.

**Version pinning.** `HIGGSFIELD_VERSION` + two per-arch SHAs are pinned at the top of `install.sh`. The release ships bare **unsigned** binaries, so the pinned SHAs are the only integrity check — never remove them. Bumps arrive as PRs from `bump-pins.yml` (this is the first tool using its two-SHA matrix support).

**Auth ships separately.** The binary is fleet-installed; each user signs in themselves with `higgsfield auth login` (interactive device flow against the org Higgsfield workspace). No keys or secrets in the script.

**Guarantees:**
- Idempotent — exits 0 if the pinned version is installed (version output format verified against the real binary)
- Reinstalls on version mismatch (up- or downgrade)
- Checksum-verified before install; refuses on mismatch; fails loudly if the tarball layout changes
- Download wrapped in `timeout 600`; work dir cleaned by `trap`
- Logs to `/tmp/higgsfield-install-<timestamp>.log` — cleaned on success, kept on failure

**Exit codes:**

| Code | Meaning |
|---|---|
| 0 | higgsfield present at the pinned version (already installed, or installed now) |
| 1 | Download, checksum, or install failure |

---

## Scope — opt-in only

**Not fleet-wide.** Scope the Mosyle script to machines that actually use Higgsfield: the creative team and IT-dev. The consuming side is the `higgsfield` plugin in the private `tlc-claude-plugins` repo (also opt-in, via `/plugin install higgsfield@tlc-claude-plugins`) — its skill preamble prefers this CLI when it's on `$PATH` and falls back to the org's Higgsfield MCP connector otherwise. The CLI unlocks the CLI-only enhancers (product-photoshoot, marketplace-cards).

---

## Files

- `install.sh` — Mosyle script. Downloads, verifies, and installs the pinned Higgsfield CLI release as root.

---

## Deployment

Mosyle → **Custom Scripts → Add Script**

**Higgsfield CLI Install**
- Run as: `root`
- Schedule: Once or recurring (idempotent — recurring picks up version bumps merged to `main`)
- Scope: Creative team / IT-dev opt-in group — **not fleet-wide**

**Paste into Mosyle's Custom Script box** (the shebang is required — Mosyle writes the body to a file and executes it):
```bash
#!/bin/bash
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/higgsfield/install.sh" | bash
```

**To test on your own Mac** — open Terminal and paste just the `curl` line (no shebang — zsh will try to run `#!/bin/bash` as a command and error out):
```bash
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/higgsfield/install.sh" | bash
```

**Verify:**
```bash
higgsfield --version   # higgsfield 0.1.40 (<commit>) built <timestamp>
```

Then each user runs `higgsfield auth login` once.

**Egress note:** downloads come from `github.com` → `objects.githubusercontent.com`; the CLI itself talks to Higgsfield's API at runtime.

---

## Updating the pinned version

Normally automatic: `bump-pins.yml` opens a PR with the new version + both per-arch SHAs once a release is ≥14 days old. Manual path:

1. Find the release at <https://github.com/higgsfield-ai/cli/releases>
2. Copy both `hf_<ver>_darwin_*.tar.gz` lines from that release's `checksums.txt`
3. Update `HIGGSFIELD_VERSION`, `HIGGSFIELD_SHA256_ARM64`, `HIGGSFIELD_SHA256_AMD64` in `install.sh`, open a PR
4. Devices converge on their next recurring Mosyle run
