# TLC Tech Policies

**The Life Church — Managed IT Policies for Staff Devices**

Policies, configuration files, and deployment scripts that IT manages across Life Church Macs and Claude surfaces. Delivered via Mosyle (managed Macs) and the Claude admin console (Claude.ai chat, Cowork). Organized by area so each piece can be found, reviewed, and updated independently.

Skills and the Claude Code plugin marketplace live in the companion private repo [`tlc-claude-plugins`](https://github.com/The-Life-Church/tlc-claude-plugins) — see *How TLC's Claude policy spans every surface* below for how the two repos fit together. (Skills moved there because the Claude.ai admin console only accepts private GitHub skill sources; everything else stays public so Mosyle's unauthenticated `raw.githubusercontent.com` pulls keep working.)

---

## Structure

```
tlc-tech-policies/
├── .github/workflows/
│   └── bump-pins.yml ← Watches upstream releases, opens PRs bumping installer version pins
├── software/
│   ├── claude/       ← Claude Code policy, managed settings, org prefs, + per-user installers (Claude Code CLI, status line)
│   ├── shell/        ← Terminal shell restrictions deployed via Mosyle
│   ├── xcode/        ← Xcode Command Line Tools silent installer
│   ├── homebrew/     ← Homebrew silent installer (IT-dev only — not in the standard chain)
│   ├── gh/           ← GitHub CLI silent installer (official pkg, pinned version + SHA)
│   ├── node/         ← Node.js LTS silent installer (official pkg, pinned version + SHA)
│   ├── higgsfield/   ← Higgsfield CLI silent installer (release tarball, pinned version + per-arch SHAs)
│   ├── hyperframes/  ← HyperFrames CLI silent installer (npm global, pinned; self-bootstraps Node + ffmpeg)
│   ├── ffmpeg/       ← FFmpeg + ffprobe static binaries (pinned per-arch SHAs; encoder half of HyperFrames)
│   ├── firebase/     ← Firebase runbook — project model, IAM bundles, deploy paths (docs, no installer)
│   ├── firebase-tools/ ← Firebase CLI silent installer (npm global, pinned; CLI + emulators + MCP; bootstraps Node + Java)
│   ├── java/         ← Temurin JRE silent installer (pinned pkg + per-arch SHAs; Firestore emulator runtime)
│   ├── security/     ← Ad-hoc read-only threat scans (Shai-Hulud npm worm scanner)
│   └── chrome/       ← Chrome managed prefs: force-install Google PWAs (Mosyle Per-App Config)
└── hardware/
    └── dock/         ← Staff Dock seeding (curl|bash bootstrap; + selective Gemini add)
```

Each folder has its own `README.md` — the source of truth for what's inside, how it deploys, scope, and exit codes. Start there for details; this file is just the map.

**Adding a tool installer?** Follow the four-step checklist in [`CLAUDE.md`](./CLAUDE.md) — especially step 3, adding the tool to `bump-pins.yml`, or its version pin silently goes stale.

---

## How TLC's Claude policy spans every surface

TLC staff use Claude across three surfaces. The policy is split across two repos:

| Surface | Policy | Repo | Delivery |
|---|---|---|---|
| **Claude Code** (CLI on managed Mac) | `software/claude/CLAUDE.md` | `tlc-tech-policies` (this repo, public) | Mosyle → `/etc/claude-code/CLAUDE.md`, daily refresh |
| **Claude.ai chat + Claude desktop app + Cowork** (org-level framing) | `software/claude/ADMIN.md` | `tlc-tech-policies` (this repo, public) | Pasted into Claude admin console → Organization preferences (3000-char limit) |
| **All surfaces** (intent-triggered skills + plugin marketplace) | `coding/skills/` (`idea`, `going-live`, `command-blocked`, `github-repo-setup`, `resource-site`) + `.claude-plugin/marketplace.json` | [`tlc-claude-plugins`](https://github.com/The-Life-Church/tlc-claude-plugins) (private) | Claude Code: plugin marketplace install, force-enabled via `managed-settings.json`. Chat + Cowork: admin-console GitHub sync (requires private repo). |

The `coding` plugin carries the intent-triggered depth: `idea` is the canonical cross-surface kickoff flow (warm welcome, brain dump, doing-vs-building check, six-option next-move menu); the others are the build-stage skills the fleet `CLAUDE.md` points at — see [`software/claude/README.md`](./software/claude/README.md#skills-referenced-by-claudemd) for the pointer table.

Skills live in the private companion repo because the Claude.ai admin console only accepts private GitHub repos as skill sync sources. Everything else stays public so Mosyle's unauthenticated `raw.githubusercontent.com` pulls keep working.

---

## Areas

| Area | What it is | Scope |
|---|---|---|
| [`software/claude`](./software/claude/README.md) | Claude Code fleet policy (`CLAUDE.md`), deny list (`managed-settings.json`), Claude.ai org prefs (`ADMIN.md`), per-user installers (Claude Code CLI, status line) | All managed Macs + admin console |
| [`software/shell`](./software/shell/README.md) | Terminal restrictions via `/etc/zshrc` — full block (general staff) or selective block of installs/package runners (vibe coders) | Per device group |
| [`software/xcode`](./software/xcode/README.md) | Headless CLT installer with `git --version` health check (self-heals after macOS upgrades) | Anyone needing git, incl. Claude Code desktop app users |
| [`software/gh`](./software/gh/README.md) | GitHub CLI from official pkg — pinned version + SHA | Vibe coders / IT-dev, recurring |
| [`software/node`](./software/node/README.md) | Node.js LTS from official pkg — pinned version + SHA. **Not fleet-wide** (desktop app doesn't need Node) | IT-dev / vibe coders, recurring; pair with Shai-Hulud scan |
| [`software/higgsfield`](./software/higgsfield/README.md) | Higgsfield CLI from release tarball — pinned version + per-arch SHAs (unsigned binary). **Opt-in only**; pairs with the `higgsfield` plugin in `tlc-claude-plugins` | Creative team / IT-dev opt-in |
| [`software/hyperframes`](./software/hyperframes/README.md) | HyperFrames CLI ("write HTML, render video") — pinned npm global install; self-bootstraps Node + ffmpeg from this repo so one Mosyle script stands up the whole render chain | Creative team / IT-dev opt-in |
| [`software/ffmpeg`](./software/ffmpeg/README.md) | FFmpeg + ffprobe static binaries — pinned per-arch SHAs are the only integrity check (upstream is unsigned). Encoder half of HyperFrames; independently deployable | Opt-in (HyperFrames hosts) |
| [`software/firebase`](./software/firebase/README.md) | Firebase runbook (docs, no installer) — two-tier project rule, builder IAM bundles, deploy paths (auto-rollouts / WIF Actions / no manual), app onboarding checklist | IT reference |
| [`software/firebase-tools`](./software/firebase-tools/README.md) | Firebase CLI (npm global, pinned) — CLI + emulator suite + MCP server in one binary; bootstraps Node + Java so one Mosyle script stands up the chain | Vibe coders / IT-dev opt-in, recurring |
| [`software/java`](./software/java/README.md) | Temurin JRE from official Adoptium pkg — pinned version + build + per-arch SHAs; required by the Firestore emulator. Bootstrapped by firebase-tools; independently deployable | Firebase-emulator hosts |
| [`software/homebrew`](./software/homebrew/README.md) | Homebrew installer — **IT-dev only**, not in the standard chain | IT-dev |
| [`software/security`](./software/security/README.md) | Ad-hoc read-only threat scans (Shai-Hulud npm worm scanner) | Node-bearing machines |
| [`software/chrome`](./software/chrome/README.md) | Force-install Google PWAs via Chrome Enterprise Core | Top-level org |
| [`hardware/dock`](./hardware/dock/README.md) | Dock seeding at enrollment via pinned dockutil | Provisioning group, one-time |

**How pinned installers stay current:** [`bump-pins.yml`](./.github/workflows/bump-pins.yml) checks upstream weekly and opens a PR bumping version + SHA once a release is ≥14 days old (supply-chain cooldown; manual dispatch overrides for urgent security fixes). Merging the PR is the deploy — devices converge on their next recurring Mosyle run.

Skills + the plugin marketplace live in the private [`tlc-claude-plugins`](https://github.com/The-Life-Church/tlc-claude-plugins) repo.

---

## Canonical raw URLs

For tools and Mosyle scripts that need to fetch the latest version of a file:

| File | Raw URL |
|---|---|
| Claude Code policy | `https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/claude/CLAUDE.md` |
| Managed settings | `https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/claude/managed-settings.json` |
| TLC `.gitignore` template (fetched at runtime by `coding:github-repo-setup`) | `https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/claude/templates/gitignore` |

The `tlc-claude-plugins` marketplace is referenced as `The-Life-Church/tlc-claude-plugins` in Claude Code's `/plugin marketplace add` command (requires `gh auth` for private-repo access).

---

## Contributing

- Scripts deploy to managed Macs automatically after merge — review carefully before approving
- Questions? Reach out to IT.
