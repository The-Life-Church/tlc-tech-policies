# Shell Restrictions — Policy Files

This folder contains the managed shell restriction policies deployed to Life Church Macs via Mosyle. There are two tiers — one for general staff and one for people using Claude Code.

---

## Policies

### Default — General Staff
Blocks terminal access entirely. When someone opens Terminal, they see a message explaining that it's managed by IT and directing them to submit a Systems Request if they need something.

**Deployed by:** `deploy-shell-policy-default.sh`
**Mosyle scope:** Default device group

### Vibe Coders — Claude Code Users
Allows normal terminal and development work, but blocks specific system-level commands. The terminal opens normally — restrictions only kick in if someone tries to run something that's managed.

**What it blocks:**
- `sudo` — privilege escalation
- `brew install` — installing software packages
- `npm install <package>` / `pnpm add` / `yarn add` / `bun add` — installing new Node packages
- `npx` / `npm exec` / `pnpm dlx` / `yarn dlx` / `bunx` / `bun x` — package runners that download *and execute* registry code in one step (same supply-chain surface as an install)
- `pip install <package>` / `pip3 install <package>` — installing new Python packages

**What still works:** dependency restores (`npm install` with no args, `pnpm install`, `yarn`, `bun install`, `pip install -r requirements.txt`), `npm run` scripts, git, local servers, and all normal project work. The wrappers only apply to interactive Terminal sessions — npm scripts and git hooks run non-interactively and are unaffected.

**Deployed by:** `deploy-shell-policy-vibe-coders.sh`
**Mosyle scope:** Vibe Coders/Claude Users device group

---

## Files

- `deploy-shell-policy-default.sh` — Mosyle script that writes the default (full block) policy to `/etc/tlc-shell-policy.zsh` and wires it into `/etc/zshrc`. Runs daily as root.
- `deploy-shell-policy-vibe-coders.sh` — Mosyle script that writes the vibe coders (selective block) policy to `/etc/tlc-shell-policy.zsh` and wires it into `/etc/zshrc`. Runs daily as root.
- `remove-shell-policy.sh` — Removes the policy file and cleans up the source line from `/etc/zshrc`. Run manually as root to offboard a device or switch policy tiers.

---

## Deployment

Policies are embedded directly in the deploy scripts. Mosyle runs each script on a daily schedule — merge a PR to `main` and devices pick it up automatically on the next run.

Mosyle → **Custom Scripts → Add Script** — one per group.

**Vibe Coders/Claude Users group**
- Run as: `root`
- Schedule: Daily
- Scope: Vibe Coders/Claude Users group

**Paste into Mosyle's Custom Script box** (shebang required — Mosyle writes the body to a file and executes it):
```bash
#!/bin/bash
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/shell/deploy-shell-policy-vibe-coders.sh" | bash
```

**Default group**
- Run as: `root`
- Schedule: Daily
- Scope: Default group

**Paste into Mosyle's Custom Script box** (shebang required — Mosyle writes the body to a file and executes it):
```bash
#!/bin/bash
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/shell/deploy-shell-policy-default.sh" | bash
```

**To test either on your own Mac** — open Terminal and paste just the `curl` line (drop the shebang — zsh will treat `#!/bin/bash` as a command and error out). Pipe to `sudo bash` since the script writes `/etc/tlc-shell-policy.zsh` and edits `/etc/zshrc`:
```bash
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/shell/deploy-shell-policy-vibe-coders.sh" | sudo bash
```

**Verify:**
```bash
cat /etc/tlc-shell-policy.zsh
cat /etc/zshrc
```

---

## Updating a Policy

1. Create a branch and make your changes inside the relevant deploy script
2. Open a PR and get at least one reviewer to approve
3. Merge to `main`
4. Mosyle picks up the change on the next scheduled run (up to 24 hours)
