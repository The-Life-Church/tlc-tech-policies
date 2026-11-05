# Runbook — clearing a Dependabot backlog

Written from the 2026-08-10 sweep, which took the org from **98 open alerts to
17** across six repos. Read the whole thing before starting; the order matters
and two steps are counterintuitive.

## 0. Why a backlog exists at all

Check this first, because it's usually the whole answer:

```bash
for r in <repos>; do
  printf "%-24s " "$r"
  gh api repos/The-Life-Church/$r/automated-security-fixes --jq '.enabled'
done
```

In August 2026 this was `false` on **four of six** affected repos. Vulnerability
*alerts* were on — which is why the dashboard filled up — but *security updates*
were off, so nothing ever opened a PR. Ninety-eight alerts sat there for months
waiting on a switch.

```bash
gh api -X PUT repos/The-Life-Church/<repo>/automated-security-fixes
```

**You do not need a `.github/dependabot.yml`.** Dependabot already groups these
("…in the npm_and_yarn group across 1 directory"), so enabling it produces one
grouped PR per manifest, not a flood.

## 1. Inventory before touching anything

```bash
gh api "/orgs/The-Life-Church/dependabot/alerts?state=open&per_page=100" --paginate
```

Sort by `dependency.scope` (`runtime` vs `development`) and by
`security_vulnerability.first_patched_version`. Two things fall out immediately:

- **`development` scope in a static site or a build toolchain is not urgent.**
  `brace-expansion`, `js-yaml`, dev `postcss` are build-time DoS — real, but they
  run on your laptop and in CI, never for a visitor.
- **`runtime` scope inside a Cloud Function is.** Anything under the
  Firestore/gRPC stack (`protobufjs`, `form-data`) is in the deployed path.

## 2. Let Dependabot take the direct dependencies

Merge its PRs. Consult [`../repo-inventory.md`](../repo-inventory.md) first —
several of these repos deploy on merge, and **merging multiple PRs quickly in the
same repo fires parallel deploys against the same function.** Merge one, wait for
the deploy, then the next. Across different repos is fine.

Expect lockfile conflicts after the first merge in a repo: the others go
`UNKNOWN`/`CONFLICTING` while Dependabot rebases them. Loop with a short sleep;
comment `@dependabot rebase` if one is genuinely stuck.

## 3. The step everyone misses: transitive-only fixes

**Dependabot never opens a PR for a vulnerability that is fixable purely in the
lockfile**, because there is no manifest edit for it to propose. Those alerts sit
open forever no matter how long you wait. They were most of the long tail.

You have to do this pass by hand — and these commands **are permitted** under the
fleet's managed settings even though `npm install` is blocked, because they only
rewrite the lockfile:

```bash
# npm
npm audit                                   # triage, read-only
npm audit fix --package-lock-only           # lockfile only, no node_modules churn

# pnpm
pnpm audit
pnpm update <pkgs> --depth Infinity --lockfile-only
```

Then commit **the lockfile alone** — no `package.json` change — and open a PR.

> **Do not edit `package.json` by hand and commit without regenerating the
> lockfile.** CI runs `npm ci`, which fails when the two disagree. That breaks the
> deploy of every repo in the table.

## 4. Know when to stop: parent-pinned dependencies

Some advisories cannot be reached by a transitive update because a parent pins the
range. As of 2026-08 that was `postcss` and `sharp` under `next`,
`brace-expansion` under `eslint-config-next → … → minimatch`, and `uuid` under
`firebase-admin → @google-cloud/firestore → google-gax → google-auth-library →
gaxios`. Confirm with `pnpm why <pkg>` or by reading the `Paths` in `pnpm audit`.

The only way to force them is a `pnpm.overrides` entry. **Default to not doing
that.** Overriding a native image library or a build CSS pipeline underneath Next,
or forcing a major version into the Google auth stack, trades a real breakage risk
— on every machine and every rollout — against an advisory whose exposure is
usually build-time or hostile-input-only. Hold, and say so in the PR body so the
next person doesn't re-litigate it.

Record the reasoning in the PR that fixes everything else. Do not aggregate a list
of live unpatched advisories into this public repo — see the note in
[`../README.md`](../README.md).

## 5. Local clones are now stale

`--package-lock-only` deliberately skips installing, so production is correct (CI
runs `npm ci` from the lockfile) while every local `node_modules` is behind. Check
with:

```bash
python3 -c "import json;print(json.load(open('node_modules/<pkg>/package.json'))['version'])"
```

Fix with `npm ci` (**not** `npm install` — that can re-resolve and undo the pin) or
`pnpm install`. For repos owned by non-developers, don't send commands: leave a
[handoff comment](../templates/vibe-coder-handoff-comment.md) with a paste-ready
prompt instead.

## 6. Verify, don't assume

- Re-run `npm audit` / `pnpm audit` in the repo — expect `0 vulnerabilities` where
  you didn't intentionally hold.
- Re-query the org alert count; the dashboard is the source of truth.
- Smoke-test anything that deployed. For the shared Firebase project:
  `resources.thelifechurch.com/api/me` → `401`, `tlc-newsletter.web.app/` → `302`.
- Confirm CI actually deployed what you think. See
  [`deploy-drift-audit.md`](deploy-drift-audit.md).

## 7. The weekly sweep routine (automation of steps 2–4)

A scheduled Claude Code cloud routine runs this runbook every **Monday at 8:00
Central**. It finds what Dependabot didn't handle, opens PRs for what it can fix,
and posts one report to the **Dep Updates** webhook in IT's GitHub Alerts Google
Chat space. Its prompt lives in
[`../routines/dep-sweep-prompt.md`](../routines/dep-sweep-prompt.md), and it reads
this runbook and [`../repo-inventory.md`](../repo-inventory.md) at the start of
every run. **Editing those two files changes how the routine behaves.**

What it will and won't do:

- **Never** merges, deploys, dismisses alerts, or pushes to a default branch. A
  person merges, and checks `repo-inventory.md` for what that merge ships.
- Lockfile-only fixes and overrides that already exist in another org repo are
  opened as ready PRs. Code migrations are opened as **drafts**, after it has
  built them, and include what a human must test after deploy.
- A lockfile fix that downgrades a runtime package is reverted and reported,
  not opened. `npm audit fix` will do this to dodge an advisory (seen 2026-11).
- Parent-pinned findings with no override precedent go into the report's
  *Holding* count. They don't need you unless they're critical.
- Quiet weeks post a single ✅ line, so silence means it didn't run.

### Why it runs `pnpm audit` / `npm audit` instead of reading Dependabot alerts

Cloud routine sessions reach `api.github.com` only through Anthropic's session
proxy. The proxy uses the `claude` GitHub App's token, scoped to the repos
attached to the routine. Org-level endpoints are refused ("sessions are bound to
their configured repositories"). Repo-level Dependabot alert endpoints return
403, because that app has no Dependabot-alerts permission. Custom header secrets
for `api.github.com` are **not** applied, so a PAT or your own GitHub App can't
work around it. The package-manager audits query the same GitHub Advisory
Database and need no token. Repo-scoped calls (listing PRs, opening PRs) work.

Side effect: alerts dismissed in GitHub (e.g. the held `@grpc/grpc-js`) still
show up in audits. The routine classifies them as parent-pinned and counts them
under *Holding*.

### Configuration (rebuild under your own account if the owner leaves)

A routine belongs to the claude.ai account that created it and stops if that
account goes away. To rebuild it, create a new routine at claude.ai/code with:

| Setting | Value |
|---|---|
| Schedule | `0 14 * * 1` (UTC) = Mondays 8:00 CST |
| Model | Opus (code-migration drafts need it) |
| Repositories | every active org repo **except MPNext**. A new repo is invisible until attached, so the report's last line, "Audited *n* repos", is the check. |
| Environment | a dedicated one, network *Limited* with `api.github.com` and `chat.googleapis.com` plus *Allow package managers* |
| Environment variable | `CHAT_WEBHOOK_URL` = the Dep Updates incoming webhook. It's a credential: set it in the environment, never in the prompt or this repo. |
| Secrets | none needed |
| Connectors | none |
| Auto-fix PRs | off until trusted (it may chase bot review comments) |
| Prompt | paste [`../routines/dep-sweep-prompt.md`](../routines/dep-sweep-prompt.md) |

Debug a bad run from the routine's run log ("list runs" → open the session),
not by re-running blind.
