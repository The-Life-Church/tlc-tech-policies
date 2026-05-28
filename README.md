# TLC Tech Policies

**The Life Church — Managed IT Policies for Staff Devices**

Policies, configuration files, deployment scripts, and Anthropic Skills that IT manages across Life Church Macs and Claude surfaces. Delivered via Mosyle (managed Macs) and the Claude admin console (Claude.ai chat, Cowork, Skills). Organized by area so each piece can be found, reviewed, and updated independently.

See [`STRUCTURE.md`](./STRUCTURE.md) for the full repo map and canonical raw URLs.

---

## Structure

```
tlc-tech-policies/
├── software/
│   ├── claude/       ← Claude Code policy, Claude.ai org-preferences block, managed settings
│   ├── shell/        ← Terminal shell restrictions deployed via Mosyle
│   ├── xcode/        ← Xcode Command Line Tools silent installer
│   ├── homebrew/     ← Homebrew silent installer
│   └── gh/           ← GitHub CLI silent installer (requires homebrew)
├── skills/           ← Anthropic Skills authored by TLC (Claude.ai chat + Cowork)
└── hardware/         ← Mac hardware and device configuration (coming soon)
```

Each folder has its own `README.md` covering what's inside and how it deploys. Start there for details.

---

## How TLC's Claude policy spans every surface

TLC staff use Claude across three surfaces. Each has its own policy file in this repo:

| Surface | Policy | Delivery |
|---|---|---|
| **Claude Code** (CLI on managed Mac) | [`software/claude/CLAUDE.md`](./software/claude/CLAUDE.md) | Mosyle → `/etc/claude-code/CLAUDE.md`, daily refresh |
| **Claude.ai chat + Claude desktop app + Cowork** (org-level framing) | [`software/claude/ADMIN.md`](./software/claude/ADMIN.md) | Pasted into Claude admin console → Organization preferences (3000-char limit) |
| **Claude.ai chat + Claude desktop app + Cowork** (intent-triggered kickoff flow) | [`skills/new-idea/SKILL.md`](./skills/new-idea/SKILL.md) | Anthropic Skill uploaded to the Claude admin console |

The three docs each have a clear role. `CLAUDE.md` is long and covers full build-stage Claude Code behavior. `ADMIN.md` is short and covers tone and routing at the org level. The `new-idea` skill is the canonical cross-surface kickoff flow that fires when someone brings a new idea to Claude — covers the warm welcome, brain-dump prompt, doing-vs-building check, and six-option next-move menu (keep going here, set up a Claude Project, use Cowork, organize a folder, share with IT, graduate to Claude Code).

See [`skills/README.md`](./skills/README.md) for more on how the three pieces relate and how to keep them in sync.

---

## software/claude

Controls how Claude Code behaves on managed Macs. Two layers:

| Layer | What it is | Delivery |
|---|---|---|
| **Behavioral policy** | `CLAUDE.md` — instructions loaded into every Claude Code session | Mosyle (`deploy-claude-policy.sh`) |
| **Managed settings** | `managed-settings.json` — deny list and bypass mode | Mosyle (`deploy-managed-settings.sh`) + Claude admin console |

See [`software/claude/README.md`](./software/claude/README.md) for the full rundown.

---

## software/shell

Restricts dangerous terminal commands on managed Macs via `/etc/zshrc`. Two policies, two device groups:

| File | Group | Blocks |
|---|---|---|
| `deploy-shell-policy-vibe-coders.sh` | Vibe coders (limited terminal) | `sudo`, `brew install`, package installs (`npm install <pkg>`, `pip install <pkg>`) — dependency restores allowed |
| `deploy-shell-policy-default.sh` | General staff (no terminal) | Full terminal block — session exits immediately with IT contact message |

See [`software/shell/README.md`](./software/shell/README.md) for deployment.

---

## software/xcode

Silent installer for Xcode Command Line Tools, deployed via Mosyle. Runs headless using the `softwareupdate` trick (no GUI prompt). Skips if CLT is already installed. Wrapped in `timeout 1800` so a stuck Apple CDN can't hang the device. Logs to `/tmp/clt-install-<timestamp>.log` — cleaned up on success, kept on failure.

**Mosyle → Custom Scripts → paste:**
```bash
# TLC Xcode Command Line Tools — Silent Install
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/xcode/install-clt.sh" | bash
```

Scope to any device group that needs CLT (e.g., vibe coders, developers). Can run as a one-time or recurring script. See [`software/xcode/README.md`](./software/xcode/README.md) for details.

---

## software/homebrew

Silent installer for Homebrew, deployed via Mosyle. Mosyle runs it as root for deploy consistency; the script drops to the console user internally because Homebrew refuses to install as root, and grants temporary NOPASSWD sudo via `/etc/sudoers.d` (auto-removed via `trap` on every exit path) so the installer's internal `sudo` calls succeed without prompting. Requires CLT — fails fast if `xcode-select -p` returns nothing. Idempotent.

**Mosyle → Custom Scripts → paste:**
```bash
# TLC Homebrew — Silent Install (run as root; script drops to console user)
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/homebrew/install.sh" | bash
```

Scope to vibe coders / IT-dev group. Deploy after the CLT installer. See [`software/homebrew/README.md`](./software/homebrew/README.md) for details.

---

## software/gh

Silent installer for the GitHub CLI (`gh`), deployed via Mosyle. Runs `brew install gh` (or `brew upgrade gh` on recurring runs) as the console user — no sudo dance needed since brew's prefix is already user-owned after install. Requires Homebrew. Idempotent.

**Mosyle → Custom Scripts → paste:**
```bash
# TLC gh — Silent Install (run as root; script drops to console user)
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/gh/install.sh" | bash
```

Scope to vibe coders / IT-dev group. Deploy after the Homebrew installer. See [`software/gh/README.md`](./software/gh/README.md) for details.

---

## skills + plugin marketplace

This repo is a [Claude Code plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces) (see [`.claude-plugin/marketplace.json`](./.claude-plugin/marketplace.json)) that ships one plugin, `tlc-skills`, containing every skill under [`skills/`](./skills/).

| Skill | What it does |
|---|---|
| [`new-idea`](./skills/new-idea/SKILL.md) | Cross-surface kickoff flow for new ideas at TLC — warm welcome, brain-dump prompt, doing-vs-building check, six-option next-move menu. |

**Install per user** (works today):
```
/plugin marketplace add The-Life-Church/tlc-tech-policies
/plugin install tlc-skills@tlc-tech-policies
```

For Claude.ai chat + Cowork, skills deploy through the Claude admin console (manual upload) — the plugin path is Claude Code-only.

See [`skills/README.md`](./skills/README.md) for deployment details (per-user, org-wide via managed settings, admin console for chat/Cowork) and authoring conventions.

---

## hardware

Coming soon — Mac provisioning, dock configuration, and device-level policy.

---

## Contributing

- Never push directly to `main` — all changes require a PR with at least one reviewer
- Scripts deploy to managed Macs automatically after merge — review carefully before approving
- Questions? Reach out to IT.
