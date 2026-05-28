# .claude-plugin

This directory makes the `tlc-tech-policies` repo function as both a **Claude Code marketplace** and a **plugin** at the same time:

| File | Role |
|---|---|
| `marketplace.json` | Declares this repo as the `tlc-tech-policies` marketplace. Lists the plugins it ships. |
| `plugin.json` | Manifest for the `tlc-skills` plugin (whose root is the repo root, source `"./"`). |

Both files live in the same directory because the marketplace root and the plugin root are the same path — the repo root. Claude Code's plugin/marketplace machinery handles this co-location pattern (see [plugins-reference#relative-paths](https://code.claude.com/docs/en/plugin-marketplaces#relative-paths)).

## Why the entire repo is "the plugin"

Plugin sources are paths to plugin directories. The plugin source declared in `marketplace.json` is `"./"`, meaning the plugin directory is the marketplace root. That works because:

- Skills already live at the default `skills/<name>/SKILL.md` location at the repo root — no path overrides needed in `plugin.json`
- Other files in the repo (`software/`, `hardware/`, deploy scripts) are ignored by the plugin system — only files referenced by `plugin.json` or in default component locations are loaded
- Keeping everything at root means raw GitHub URLs used by Mosyle scripts (e.g. `https://raw.githubusercontent.com/.../main/software/claude/CLAUDE.md`) stay valid

## How users install it

**Manual (per user):**
```
/plugin marketplace add The-Life-Church/tlc-tech-policies
/plugin install tlc-skills@tlc-tech-policies
```

**Org-wide (via managed settings):** add `extraKnownMarketplaces` and `enabledPlugins` entries to `software/claude/managed-settings.json` (see [`skills/README.md`](../skills/README.md) for the proposed snippet — needs verification in a test environment before deploying broadly because the `enabledPlugins` schema isn't fully documented yet).

## How skill namespacing works

Skills from this plugin appear as `tlc-skills:<skill-name>` in Claude Code. So `skills/new-idea/SKILL.md` becomes `/tlc-skills:new-idea`. The plugin namespace also means TLC-managed skills can't collide with users' personal skills at the same name.

## Versioning

Bump `version` in `plugin.json` when shipping a meaningful change. Claude Code uses the version to track updates — users on auto-update will pick up changes; users on manual update need `/plugin marketplace update tlc-tech-policies` followed by `/reload-plugins`.

If `version` is omitted, Claude Code falls back to the git commit SHA. That works but provides no semantic signal about what changed between updates.
