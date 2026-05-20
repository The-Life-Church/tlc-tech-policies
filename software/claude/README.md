# Claude Code — Policy Files

This folder contains the managed Claude Code policies deployed to Life Church Macs. Two layers: a behavioral policy file and a managed settings file.

---

## Files

### `CLAUDE.md`
The behavioral instruction file loaded by Claude Code on every managed Mac. It shapes how Claude behaves across all projects — slowing down before making changes, asking questions before building, knowing when to loop in IT, and keeping work local until it's ready to go further.

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

### `managed-settings.json`
A JSON settings file deployed to `/Library/Application Support/ClaudeCode/managed-settings.json`. This is the Claude Code managed settings layer — it enforces permission rules that prevent Claude from automatically running high-risk commands on a user's behalf.

**What it blocks Claude from doing automatically:**
- Running `sudo` or privilege escalation
- `rm -rf` — recursive force deletion
- `curl ... | bash` or `wget ... | bash` — piping remote scripts directly into execution
- `chmod` / `chown` — changing file permissions or ownership
- `brew install` — installing software packages
- `npm install -g` — installing global Node packages
- `pip install --system` — installing Python packages system-wide
- `launchctl` / `systemctl` — managing system services
- `git push --force` — force-pushing to a git repo
- Reading `.env` files, `*.pem`, `*.key`, or anything in a `secrets/` folder

Users can still run any of these themselves in Terminal — this only prevents Claude from doing it automatically.

---

### Deploy scripts

- `deploy-claude-policy.sh` — Mosyle script that pulls the latest `CLAUDE.md` from GitHub to `/etc/claude-code/CLAUDE.md` and wires the import block into the user's `~/.claude/CLAUDE.md`. Runs daily as root.
- `deploy-managed-settings.sh` — Mosyle script that pulls the latest `managed-settings.json` from GitHub and places it at `/Library/Application Support/ClaudeCode/managed-settings.json`. Runs daily as root.
- `remove-claude-policy.sh` — Removes the managed policy file and cleans up the import block from the user's `~/.claude/CLAUDE.md`. Run manually as root to offboard a device.

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
