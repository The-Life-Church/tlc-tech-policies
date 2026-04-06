# TLC Tech Policies

**The Life Church — Managed IT Policies for Staff Devices**

This repo contains policies, configuration files, and deployment scripts that IT manages across Life Church Macs via Mosyle MDM and Claude admin console. It is organized by area so policies can be found, reviewed, and updated independently.

---

## Structure

```
tlc-tech-policies/
├── software/
│   ├── claude/       ← Claude Code behavioral policy and permission settings
│   └── shell/        ← Terminal shell restrictions deployed via Mosyle
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

**Mosyle Shell Script**
1. Mosyle → Custom Scripts → Add Script
2. Upload `deploy-claude-policy.sh`, run as root, daily schedule

---

## software/shell

Restricts dangerous terminal commands on managed Macs via `/etc/zshrc`. Two policies for two device groups:

| File | Group | Blocks |
|---|---|---|
| `shell-policy-vibe-coders.zsh` | General staff (no terminal) | Package installs only — safety net for VS Code terminal |
| `shell-policy-default.zsh` | Claude Code users (terminal access) | Full deny list — all restricted commands |

### Deployment

**Mosyle → Custom Scripts → Add Script** (once per group)
- Upload `deploy-shell-policy-vibe-coders.sh`, scope to vibe coder group
- Upload `deploy-shell-policy-default.sh`, scope to Claude Code users group
- Both run as root on a recurring schedule

When a policy changes: update the `.zsh` file and merge to `main`. Mosyle picks it up on the next scheduled run.

---

## hardware

Coming soon — Mac provisioning, dock configuration, and device-level policy.

---

## Contributing

- Never push directly to `main` — all changes require a PR with at least one reviewer
- Scripts deploy to managed Macs automatically after merge — review carefully before approving
- Questions? Reach out to IT.
