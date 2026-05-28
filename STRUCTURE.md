# Repository Structure

A map of this repo. Useful for humans navigating it and for skills that need to point at canonical URLs by stable path.

```
tlc-tech-policies/
├── README.md                                 ← Repo overview, entry point
├── STRUCTURE.md                              ← This file
├── .claude-plugin/                           ← Marketplace + plugin manifests (Claude Code)
│   ├── marketplace.json                      ← Declares this repo as the tlc-tech-policies marketplace
│   ├── plugin.json                           ← Manifest for the tlc-skills plugin (source: "./")
│   └── README.md                             ← How marketplace + plugin co-locate at repo root
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
│   └── gh/                                   ← Silent GitHub CLI installer (requires Homebrew)
│       ├── install.sh
│       └── README.md
├── skills/                                   ← Anthropic Skills authored by TLC
│   ├── README.md                             ← How skills deploy + relate to CLAUDE.md/ADMIN.md
│   └── new-idea/
│       └── SKILL.md                          ← Canonical cross-surface kickoff flow
└── hardware/                                 ← Mac hardware policies (coming soon)
```

## Canonical raw URLs

For tools and skills that need to fetch the latest version of a file:

| File | Raw URL |
|---|---|
| Claude Code policy | `https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/claude/CLAUDE.md` |
| New-idea skill | `https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/skills/new-idea/SKILL.md` |
| Managed settings | `https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/claude/managed-settings.json` |
| Marketplace manifest | `https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/.claude-plugin/marketplace.json` |
| Plugin manifest | `https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/.claude-plugin/plugin.json` |

The marketplace itself is referenced as `The-Life-Church/tlc-tech-policies` in Claude Code's `/plugin marketplace add` command — no raw URL needed.

## How the surfaces relate

| Surface | Policy file(s) loaded | Delivery |
|---|---|---|
| Claude Code (CLI on managed Mac) | `software/claude/CLAUDE.md` + `managed-settings.json` + `tlc-skills` plugin (every skill under `skills/`) | Mosyle pulls policy from `main` daily; plugin installs via marketplace (manual or via managed `enabledPlugins`) |
| Claude.ai chat + Claude desktop app | `software/claude/ADMIN.md` (org prefs) + `skills/new-idea/SKILL.md` (on intent) | Admin console (manual paste) + Skills (admin upload) |
| Cowork | Same as Claude.ai chat | Same as Claude.ai chat |

`CLAUDE.md` links to `SKILL.md` for the cross-surface kickoff flow so Claude Code sessions can read the full version when relevant. The skill doesn't load `CLAUDE.md` — Claude Code mechanics aren't useful in chat/Cowork.

The `tlc-skills` plugin uses the marketplace + plugin manifests in `.claude-plugin/` to deliver skills natively to Claude Code via Anthropic's plugin system — no Mosyle script needed for skills.

---

*Maintained by The Life Church IT/Dev team.*
