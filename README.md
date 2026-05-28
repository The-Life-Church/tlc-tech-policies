# TLC Tech Policies

**The Life Church — Managed IT Policies for Staff Devices**

Policies, configuration files, and deployment scripts that IT manages across Life Church Macs and Claude surfaces. Delivered via Mosyle (managed Macs) and the Claude admin console (Claude.ai chat, Cowork). Organized by area so each piece can be found, reviewed, and updated independently.

Skills and the Claude Code plugin marketplace live in the companion private repo [`tlc-claude-plugins`](https://github.com/The-Life-Church/tlc-claude-plugins) — see *How TLC's Claude policy spans every surface* below for how the two repos fit together.

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
└── hardware/         ← Mac hardware and device configuration (coming soon)
```

Each folder has its own `README.md` covering what's inside and how it deploys. Start there for details.

---

## How TLC's Claude policy spans every surface

TLC staff use Claude across three surfaces. The policy is split across two repos:

| Surface | Policy | Repo | Delivery |
|---|---|---|---|
| **Claude Code** (CLI on managed Mac) | `software/claude/CLAUDE.md` | `tlc-tech-policies` (this repo, public) | Mosyle → `/etc/claude-code/CLAUDE.md`, daily refresh |
| **Claude.ai chat + Claude desktop app + Cowork** (org-level framing) | `software/claude/ADMIN.md` | `tlc-tech-policies` (this repo, public) | Pasted into Claude admin console → Organization preferences (3000-char limit) |
| **All surfaces** (intent-triggered kickoff flow + plugin marketplace) | `innovation/skills/idea/SKILL.md` + `.claude-plugin/marketplace.json` | [`tlc-claude-plugins`](https://github.com/The-Life-Church/tlc-claude-plugins) (private) | Claude Code: plugin marketplace install. Chat + Cowork: admin-console GitHub sync (requires private repo). |

The `idea` skill is the canonical cross-surface kickoff flow that fires when someone brings a new idea to Claude — covers the warm welcome, brain-dump prompt, doing-vs-building check, and six-option next-move menu (keep going here, set up a Claude Project, use Cowork, organize a folder, share with IT, graduate to Claude Code).

Skills live in the private companion repo because the Claude.ai admin console only accepts private GitHub repos as skill sync sources. Everything else stays public so Mosyle's unauthenticated `raw.githubusercontent.com` pulls keep working.

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

Skills live in the private [`tlc-claude-plugins`](https://github.com/The-Life-Church/tlc-claude-plugins) repo, not here. That repo ships the `innovation` plugin (containing the `idea` skill) via a Claude Code marketplace and syncs into the Claude.ai admin console for chat + Cowork. See its README for the install commands and how it relates to this repo.

---

## hardware

Coming soon — Mac provisioning, dock configuration, and device-level policy.

---

## Contributing

- Never push directly to `main` — all changes require a PR with at least one reviewer
- Scripts deploy to managed Macs automatically after merge — review carefully before approving
- Questions? Reach out to IT.
