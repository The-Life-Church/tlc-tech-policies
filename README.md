# TLC Tech Policies

**The Life Church — Managed IT Policies for Staff Devices**

This repo contains policies, configuration files, and deployment scripts that IT manages across Life Church Macs via Mosyle and the Claude admin console. It is organized by area so policies can be found, reviewed, and updated independently.

---

## Structure

```
tlc-tech-policies/
├── software/
│   ├── claude/       ← Claude Code behavioral policy and permission settings
│   ├── shell/        ← Terminal shell restrictions deployed via Mosyle
│   └── xcode/        ← Xcode Command Line Tools silent installer
└── hardware/         ← Mac hardware and device configuration (coming soon)
```

---

## software/claude

Controls how Claude Code behaves on managed Macs. Three complementary layers:

| Layer | File | Where it goes | Enforces |
|---|---|---|---|
| **Mosyle Script** | `deploy-managed-settings.sh` | Mosyle → Custom Script (daily) | Deny list + bypass mode via `managed-settings.json` |
| **Claude Admin Console** | `managed-settings.json` | claude.ai org admin settings | Deny list + bypass mode + announcement (org account layer) |
| **Mosyle Shell Script** | `deploy-claude-policy.sh` | Mosyle → Custom Script (daily) | CLAUDE.md behavioral policy |

### Deployment

**Mosyle Managed Settings Script**
1. Mosyle → Custom Scripts → Add Script
2. Upload `deploy-managed-settings.sh`, run as root, daily schedule
3. Scope to the Default group
4. Restart Claude Code on the test Mac

Verify on a test machine: `cat "/Library/Application Support/ClaudeCode/managed-settings.json"` and then `/status` inside Claude Code

**Claude Admin Console**
1. claude.ai → Admin → Settings
2. Paste contents of `managed-settings.json`
3. Save

Verify in Claude Code: `/status` should show `Enterprise managed settings (remote)`

**Mosyle Shell Script**
1. Mosyle → Custom Scripts → Add Script
2. Upload `deploy-claude-policy.sh`, run as root, daily schedule

---

## software/shell

Restricts dangerous terminal commands on managed Macs via `/etc/zshrc`. Two policies for two device groups:

| File | Group | Blocks |
|---|---|---|
| `deploy-shell-policy-vibe-coders.sh` | Vibe coders (limited terminal) | `sudo`, `brew install`, package installs (`npm install <pkg>`, `pip install <pkg>`) — dependency restores allowed |
| `deploy-shell-policy-default.sh` | General staff (no terminal) | Full terminal block — session exits immediately with IT contact message |

### Deployment

**Mosyle → Custom Scripts → Add Script** (once per group)
- Scope `deploy-shell-policy-vibe-coders.sh` to vibe coder group
- Scope `deploy-shell-policy-default.sh` to general staff group
- Both run as root on a recurring schedule

When a policy changes: update the deploy script and merge to `main`. Mosyle picks it up on the next scheduled run.

---

## software/xcode

Silent installer for Xcode Command Line Tools, deployed via Mosyle. Runs headless using the `softwareupdate` trick (no GUI prompt). Skips if CLT is already installed. Logs to `/tmp/clt-install-<timestamp>.log` — cleaned up on success, kept on failure.

| File | Purpose |
|---|---|
| `install-clt.sh` | CLT silent install script |

### Deployment

Mosyle → Custom Scripts → paste:
```bash
# TLC Xcode Command Line Tools — Silent Install
# Installs CLT via softwareupdate (headless, no GUI prompt).
# Skips if already installed. Logs to /tmp/clt-install-<timestamp>.log.
# Log file is cleaned up on success, kept on failure for troubleshooting.
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/xcode/install-clt.sh" | bash
```

Scope to any device group that needs CLT (e.g., vibe coders, developers). Can run as a one-time or recurring script.

---

## hardware

Coming soon — Mac provisioning, dock configuration, and device-level policy.

---

## Contributing

- Never push directly to `main` — all changes require a PR with at least one reviewer
- Scripts deploy to managed Macs automatically after merge — review carefully before approving
- Questions? Reach out to IT.
