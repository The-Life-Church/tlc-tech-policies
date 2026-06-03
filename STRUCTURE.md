# Repository Structure

A map of this repo and how it relates to the companion private repo. Useful for humans navigating it and for tooling that needs to point at canonical URLs by stable path.

## Two repos, one policy

| Repo | Visibility | Contains |
|---|---|---|
| `tlc-tech-policies` (this repo) | Public | Claude Code policy (`CLAUDE.md`), org-preferences block (`ADMIN.md`), Mosyle deploy scripts, shell restrictions, silent installers, hardware policy |
| [`tlc-claude-plugins`](https://github.com/The-Life-Church/tlc-claude-plugins) | Private | Claude Code plugin marketplace + skills (e.g. `idea`). Syncs into Claude.ai admin console for chat + Cowork. |

Skills moved to the private repo because the Claude.ai admin console only accepts private GitHub sources for skill sync. Everything else stays public so Mosyle's unauthenticated `raw.githubusercontent.com` pulls keep working.

## Layout

```
tlc-tech-policies/
├── README.md                                 ← Repo overview, entry point
├── STRUCTURE.md                              ← This file
├── software/                                 ← Policies organized by software area
│   ├── claude/                               ← Claude policy: Code, chat/Cowork org prefs
│   │   ├── CLAUDE.md                         ← Managed Claude Code policy (→ /etc/claude-code/CLAUDE.md)
│   │   ├── ADMIN.md                          ← Claude.ai org-preferences block (admin console)
│   │   ├── README.md                         ← How the Claude layer works + deploy details
│   │   ├── managed-settings.json             ← Claude Code deny list and bypass mode
│   │   ├── deploy-claude-policy.sh           ← Mosyle script: pull CLAUDE.md to /etc/claude-code/
│   │   ├── deploy-managed-settings.sh        ← Mosyle script: place managed-settings.json
│   │   └── remove-claude-policy.sh           ← Offboarding cleanup
│   ├── shell/                                ← Terminal shell restrictions via /etc/zshrc
│   │   ├── deploy-shell-policy-default.sh    ← Full terminal block (general staff)
│   │   ├── deploy-shell-policy-vibe-coders.sh ← Targeted blocks (vibe coders)
│   │   ├── remove-shell-policy.sh
│   │   └── README.md
│   ├── xcode/                                ← Silent Xcode Command Line Tools installer
│   │   ├── install-clt.sh
│   │   └── README.md
│   ├── homebrew/                             ← Silent Homebrew installer
│   │   ├── install.sh
│   │   └── README.md
│   ├── gh/                                   ← Silent GitHub CLI installer (requires Homebrew)
│   │   ├── install.sh
│   │   └── README.md
│   ├── chrome/                               ← Chrome managed prefs (force-install Google PWAs)
│   │   ├── managed-preferences.plist        ← Mosyle Chrome Per-App Config (PLIST)
│   │   └── README.md
│   └── security/                             ← Ad-hoc read-only threat scans
│       ├── scan-shai-hulud.sh               ← Mini Shai-Hulud npm worm scanner (exit 0/2/3)
│       └── README.md                        ← What it checks, Mosyle run, gh-side checks
└── hardware/                                 ← Mac hardware + device-level policy
    └── dock/                                 ← Dock seeding (curl|bash bootstrap; replaces tlc-dock-seed .pkg)
        ├── install-staff-dock.sh            ← Mosyle bootstrap: install dockutil + scripts, load daemon
        ├── setup-dock.sh                    ← Runtime: first-run clean slate + add managed apps, retry
        ├── report-status.sh                 ← Status reporter (exit 0/1/2/3)
        ├── com.tlc.dock.seed.plist          ← Seeding LaunchDaemon (RunAtLoad + 10-min retry)
        ├── add-gemini-to-dock.sh            ← Standalone: add Gemini to an existing Mac's Dock (append-only; seeder already docks it on new Macs)
        └── README.md                        ← Managed app list, deploy, status, rollback
```

The private companion repo has its own structure — see its README for details.

## Canonical raw URLs (this repo)

For tools and Mosyle scripts that need to fetch the latest version of a file:

| File | Raw URL |
|---|---|
| Claude Code policy | `https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/claude/CLAUDE.md` |
| Managed settings | `https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/claude/managed-settings.json` |

The `tlc-claude-plugins` marketplace is referenced as `The-Life-Church/tlc-claude-plugins` in Claude Code's `/plugin marketplace add` command (requires `gh auth` for private-repo access).

## How the surfaces relate

| Surface | Policy file(s) loaded | Delivery |
|---|---|---|
| Claude Code (CLI on managed Mac) | `software/claude/CLAUDE.md` + `managed-settings.json` (this repo) + `innovation` plugin (private repo) | Mosyle pulls policy from `main` daily; plugin installs via marketplace from `tlc-claude-plugins` |
| Claude.ai chat + Claude desktop app | `software/claude/ADMIN.md` (this repo, org prefs) + `idea` skill (private repo, on intent) | Admin console: paste `ADMIN.md` into Organization preferences; sync skills from `tlc-claude-plugins` |
| Cowork | Same as Claude.ai chat | Same as Claude.ai chat |

`CLAUDE.md` (this repo) mentions the `idea` skill by name so Claude Code sessions know it exists, but doesn't link to it directly since cross-repo deep-links don't resolve cleanly.

---

*Maintained by The Life Church IT/Dev team.*
