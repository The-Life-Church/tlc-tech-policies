# Skills

Anthropic Skills authored by TLC IT. These are intent-triggered behaviors that surface in Claude.ai chat, the Claude desktop app, Cowork, and Claude Code when the user's message matches the skill's description.

## What's here

| Skill | What it does | Where it fires |
|---|---|---|
| [`new-idea`](./new-idea/SKILL.md) | Cross-surface kickoff flow for new ideas at TLC — warm welcome, brain-dump prompt, doing-vs-building check, six-option next-move menu. Canonical reference for kickoff thinking across every Claude surface. | Claude.ai chat, Claude desktop app, Cowork, Claude Code. (In Claude Code, the managed `CLAUDE.md` already covers the same thinking — the skill is for explicit invocation or reference.) |

## How skills relate to the managed CLAUDE.md and ADMIN.md

The three pieces of TLC's Claude policy each have a clear role:

| File | Surface | Delivery | Length |
|---|---|---|---|
| [`software/claude/CLAUDE.md`](../software/claude/CLAUDE.md) | Claude Code (CLI on managed Macs) | Mosyle → `/etc/claude-code/CLAUDE.md`, daily refresh from `main` | Long. Full build-stage policy. |
| [`software/claude/ADMIN.md`](../software/claude/ADMIN.md) | Claude.ai chat + Cowork (org level) | Manually pasted into Claude admin console → Organization preferences (3000-char cap) | Short. Tone and routing only. |
| [`skills/new-idea/SKILL.md`](./new-idea/SKILL.md) | Claude.ai chat, desktop app, Cowork, Claude Code — when a new idea comes in | Plugin marketplace (see below) or admin-console upload | Medium. Full kickoff flow. |

When the kickoff flow needs to change, edit `SKILL.md`. Check that `CLAUDE.md`'s "Right Tool First" section still agrees on the overall shape. `ADMIN.md` rarely needs changes — it's tone and routing, not flow.

## How skills deploy

Skills deploy two ways depending on the surface.

### Claude Code — plugin marketplace

This repo is a Claude Code marketplace (see [`.claude-plugin/marketplace.json`](../.claude-plugin/marketplace.json)) that ships one plugin: `tlc-skills`. The plugin contains every skill under this `skills/` folder, namespaced as `tlc-skills:<skill-name>` when invoked.

**Per-user install** (works today, no managed-settings changes needed):

```
/plugin marketplace add The-Life-Church/tlc-tech-policies
/plugin install tlc-skills@tlc-tech-policies
```

After installing, skills appear as `tlc-skills:new-idea` and fire on intent.

**Org-wide auto-install** via managed settings (proposed — needs verification before deploying broadly):

The following keys would be added to [`software/claude/managed-settings.json`](../software/claude/managed-settings.json):

```jsonc
{
  "extraKnownMarketplaces": {
    "tlc-tech-policies": {
      "source": { "source": "github", "repo": "The-Life-Church/tlc-tech-policies" },
      "autoUpdate": true
    }
  },
  "strictKnownMarketplaces": [
    { "source": "github", "repo": "The-Life-Church/tlc-tech-policies" }
  ],
  "enabledPlugins": {
    "tlc-skills@tlc-tech-policies": true
  }
}
```

`extraKnownMarketplaces` registers the marketplace; `strictKnownMarketplaces` locks the org to only this marketplace (and the official Anthropic one) for plugin installs; `enabledPlugins` force-enables the plugin for every user.

> ⚠️ The exact `enabledPlugins` schema (object-keyed vs array) isn't fully documented in Anthropic's public docs at time of writing. Test on a single device before deploying to all groups. The other three keys are documented.

### Claude.ai chat + Cowork — admin console

For chat and Cowork, skills deploy through the Claude admin console (the plugin marketplace path is Claude Code-only):

1. Edit the `SKILL.md` file in this repo
2. Open a PR and merge to `main`
3. An admin opens the Claude admin console → Skills, uploads the skill, and enables it for the org
4. The skill becomes available in every Claude.ai chat, Claude desktop app session, and Cowork agent run

## Authoring conventions

- **Description matters more than the body.** Anthropic's Skills system uses the `description` field in frontmatter to decide when to fire. List concrete trigger phrases.
- **Write for the surface, not the codebase.** Most users invoking these skills are not developers. Plain language, warm tone, no jargon.
- **Don't duplicate `CLAUDE.md` build-stage mechanics.** Skills are for cross-surface thinking, not for code-level conventions.
- **Link the canonical source.** Skills should link back to this repo's URL (`https://github.com/The-Life-Church/tlc-tech-policies`) so the user can read the latest version if curious.
- **Bump `plugin.json`'s `version` when shipping a meaningful change** so users on auto-update get a clean update signal.

---

*Maintained by The Life Church IT/Dev team. Questions? Reach out to IT.*
