# Claude — Policy Files

This folder contains TLC's Claude policy across every surface: Claude Code (CLI), Claude.ai chat, the Claude desktop app, and Cowork. Three docs, each with a clear role.

| File | Surface | Delivery |
|---|---|---|
| `CLAUDE.md` | Claude Code (CLI on managed Macs) | Mosyle → `/etc/claude-code/CLAUDE.md`, daily refresh |
| `ADMIN.md` | Claude.ai chat, Claude desktop app, Cowork (org-level framing) | Manually pasted into Claude admin console → Organization preferences (3000-char cap) |
| `idea` skill in the `innovation` plugin at [`tlc-claude-plugins`](https://github.com/The-Life-Church/tlc-claude-plugins) (private repo) | Claude.ai chat, Claude desktop app, Cowork, Claude Code (intent-triggered kickoff flow) | Claude Code: plugin marketplace install. Chat + Cowork: admin-console GitHub sync from the private repo. |

`CLAUDE.md` is long-form build-stage policy. `ADMIN.md` is short tone/routing framing that fits the admin console's character cap. The `innovation` plugin's `idea` skill fills the gap: long-form kickoff content that fires on intent in chat/Cowork/Claude Code, complementing the short admin-console block. It lives in a private repo because the Claude.ai admin console only syncs skills from private GitHub sources.

`CLAUDE.md` and `managed-settings.json` deploy via Mosyle scripts in this folder. `ADMIN.md` deploys via manual paste into the admin console. The plugin deploys via the marketplace in `tlc-claude-plugins` (Claude Code) and admin-console GitHub sync (chat + Cowork).

---

## Files

### `CLAUDE.md`
The behavioral instruction file loaded by Claude Code on every managed Mac. It shapes how Claude behaves across all projects — slowing down before making changes, asking questions before building, knowing when to loop in IT, and keeping work local until it's ready to go further. Links to `SKILL.md` for the cross-surface kickoff flow.

**To view the live file:** [software/claude/CLAUDE.md](./CLAUDE.md)

#### How the global CLAUDE.md works

Claude Code natively supports a global instruction file at `~/.claude/CLAUDE.md` on each user's machine. When Claude Code starts, it automatically reads this file and loads it as persistent context — no project setup required. Users can put personal preferences there and Claude will carry them across every project they work in.

Anthropic documents this as part of Claude Code's memory system: [docs.anthropic.com/en/docs/claude-code/memory](https://docs.anthropic.com/en/docs/claude-code/memory)

Our managed policy takes advantage of this. The deploy script writes our policy file to `/etc/claude-code/CLAUDE.md` on the device, then appends an import line to the user's `~/.claude/CLAUDE.md`:

```
@/etc/claude-code/CLAUDE.md
```

Claude Code follows that `@`-style import and loads our managed file as part of the global context. The user's own content stays above it and is never overwritten — our policy just gets added to the bottom. If we update `CLAUDE.md` in GitHub and merge to `main`, Mosyle refreshes `/etc/claude-code/CLAUDE.md` on the next daily run and the user picks it up automatically.

---

### `ADMIN.md`
The Claude.ai organization-preferences block. Short framing (tone, data handling, IT routing) that applies to every Claude.ai chat session and Cowork agent run across the org. Capped at 3000 characters by the admin console. Does *not* apply to Claude Code — that uses `CLAUDE.md` above.

**To deploy:** open the Claude admin console → Settings → Organization preferences → paste the contents of `ADMIN.md`. See [`ADMIN.md`](./ADMIN.md) for the block itself and full notes.

---

### `managed-settings.json`
A JSON settings file deployed to `/Library/Application Support/ClaudeCode/managed-settings.json`. This is the Claude Code managed settings layer — it enforces permission rules that prevent Claude from automatically running high-risk commands on a user's behalf.

**What it blocks Claude from doing automatically:**
- Running `sudo` or privilege escalation
- `rm -rf` — recursive force deletion
- `curl ... | bash` or `wget ... | bash` (and `| sh` / `| zsh`) — piping remote scripts directly into execution
- `chmod` / `chown` — changing file permissions or ownership
- `brew install` — installing software packages
- `npm install` — installing Node packages (including bare restores)
- npm-ecosystem package runners and installers — `npx`, `npm exec`, `pnpm install/add/dlx`, `yarn add/dlx`, `bun install/add`, `bunx` (these download and execute registry code in one step)
- `pip install` / `pip3 install` — including the bypasses `python -m pip install`, `uv pip install`, and `uvx`
- `killall` / `pkill`, `crontab`, `launchctl` / `systemctl` — process and service management
- `git push --force` — force-pushing to a git repo
- Reading `.env` files, `*.pem`, `*.key`, or anything in a `secrets/` folder

Users can still run any of these themselves in Terminal (subject to the shell policy on vibe-coder devices) — this only prevents Claude from doing it automatically. When a deny rule changes here, sync the human-readable lists in `CLAUDE.md` ("When a Command Is Blocked") and `software/shell/README.md`.

**Version floor (`minimumVersion`)** — Claude Code installs per-user and self-updates (see `install-claude-code.sh` below), so the fleet rides latest by default. `minimumVersion` is a *soft floor*: auto-update won't leave a machine below it, but Claude still starts on anything at-or-above — so it can't lock anyone out. Bump it occasionally to retire ancient builds. Two stronger keys exist but we deliberately **don't** use them: `requiredMinimumVersion` / `requiredMaximumVersion` make Claude Code *refuse to start* outside a range — set the ceiling too low and a fast-updating Mac is bricked fleet-wide. Use the soft floor unless there's a specific reason to hard-gate.

**Plugins** — the file also registers the private `tlc-claude-plugins` marketplace (`extraKnownMarketplaces`, with `autoUpdate: true`) and force-enables org-wide plugins via `enabledPlugins`:

- **Force-enabled (everyone):** `innovation` — the cross-surface kickoff flow. Add a plugin here only if most staff should have it; every enabled skill adds its trigger description to every session and can auto-fire on loosely matching requests.
- **Opt-in (install yourself):** anything else published in the marketplace. Because the marketplace is already known on every device, any user can run `/plugin install <name>@tlc-claude-plugins` — no settings change, auto-updates included. Example: the `higgsfield` plugin (vendored Higgsfield generation skills) — intended for creatives who actually use Higgsfield, not the whole org. On the chat/Cowork side the same skills arrive via the admin-console sync of the repo, where users toggle them in their own settings.

---

### Deploy scripts

- `deploy-claude-policy.sh` — Mosyle script that pulls the latest `CLAUDE.md` from GitHub to `/etc/claude-code/CLAUDE.md` and wires the import block into the user's `~/.claude/CLAUDE.md`. Runs daily as root.
- `deploy-managed-settings.sh` — Mosyle script that pulls the latest `managed-settings.json` from GitHub and places it at `/Library/Application Support/ClaudeCode/managed-settings.json`. Runs daily as root.
- `remove-claude-policy.sh` — Removes the managed policy file and cleans up the import block from the user's `~/.claude/CLAUDE.md`. Run manually as root to offboard a device.

### Installing Claude Code itself (the binary)

- `install-claude-code.sh` — Mosyle script that installs the Claude Code CLI for the logged-in console user via the official native installer. **Per-user, not root-global, and not version-pinned** — the native install lands in the user's `~/.local/bin/claude` and **self-updates in the background**, so this only bootstraps it (a recurring schedule just heals machines where it's missing; it skips when already present). Run as root; the script drops to the console user. Not in `bump-pins.yml` — there's no pin to bump. If you ever need version bounds fleet-wide, use `minimumVersion` / `requiredMaximumVersion` in `managed-settings.json`, not a pin here.
- `statusline/install.sh` — Mosyle script that installs the [custom status line](./statusline/) for the console user: places `statusline.js` in their `~/.claude/` and merges the `statusLine` key into their `~/.claude/settings.json` (preserving other keys; refuses rather than clobber an unparseable file). **Requires Node** (the status line runs `node`), so scope it to the same machines as `software/node/`.

**Dependency order for a full Claude Code dev setup:** `software/node/` (Node) → `install-claude-code.sh` (the CLI) → `statusline/install.sh` (the status line). All three are per-user and idempotent; the policy/managed-settings scripts above are separate and machine-level.

---

## Deployment

Policies are pulled directly from `The-Life-Church/tlc-tech-policies` on GitHub. Mosyle runs each script on a daily schedule — merge a PR to `main` and devices pick it up automatically on the next run.

### Behavioral Policy (CLAUDE.md)

Mosyle → **Custom Scripts → Add Script**
- Run as: `root`
- Schedule: Daily
- Scope: Default group

**Paste into Mosyle's Custom Script box** (shebang required — Mosyle writes the body to a file and executes it):
```bash
#!/bin/zsh
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/claude/CLAUDE.md" -o /etc/claude-code/CLAUDE.md
```

**To test on your own Mac** — open Terminal and paste just the `curl` line (drop the shebang — zsh will treat `#!/bin/zsh` as a command and error out). Writing to `/etc/` requires sudo:
```bash
sudo curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/claude/CLAUDE.md" -o /etc/claude-code/CLAUDE.md
```

**Verify:**
```bash
cat /etc/claude-code/CLAUDE.md
```

### Managed Settings (`managed-settings.json`)

Mosyle → **Custom Scripts → Add Script**
- Run as: `root`
- Schedule: Daily
- Scope: Default group
- Upload `deploy-managed-settings.sh`

**Verify on a test Mac:**
```bash
cat "/Library/Application Support/ClaudeCode/managed-settings.json"
```

Then restart Claude Code and run `/status`. Expected result: `Setting sources` includes the local managed settings source.

### Admin Console Settings

1. Open [claude.ai](https://claude.ai) → Admin → Settings
2. Paste the contents of `managed-settings.json`
3. Save

> Manual step — no Mosyle involvement. Same settings file, different delivery path.

Verify in Claude Code with `/status`. Expected result: `Setting sources` includes `Enterprise managed settings (remote)`.

---

## Updating a Policy

1. Create a branch and make your changes
2. Open a PR and get at least one reviewer to approve
3. Merge to `main`
4. Mosyle picks up the change on the next scheduled run (up to 24 hours)

For the admin console settings, update them manually after merging.
