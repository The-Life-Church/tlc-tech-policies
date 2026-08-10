# Runbook — is every repo's `main` actually deployed?

Written during the 2026-08-06 GitHub Actions outage, when roughly a dozen runs
across the org were cancelled, failed at `Set up job`, or sat queued forever, and
it was genuinely unclear what had shipped.

## The method

**A run list cannot tell you what is live.** Green runs scroll away, cancelled
runs look like failures, and a queued run that never started looks the same as one
that's about to. The only reliable comparison is:

> the tip SHA of the deploying branch  **vs**  the `headSha` of that workflow's
> last **successful** run

Equal → live. Different → there are undeployed commits, and you then look at
*what* those commits touch before deciding it matters.

Run [`../scripts/deploy-drift-audit.sh`](../scripts/deploy-drift-audit.sh).

## Reading the output honestly

Three traps, all of which produced wrong answers on the first pass:

**Match the branch, not always `main`.** Staging workflows deploy `stage`.
Comparing a stage deploy's SHA against `main`'s tip reports drift that doesn't
exist. `MPNext` and `wp-content` both have this shape.

**Not every workflow with "deploy" or "release" in the name deploys.** MPNext has
`Release on main`, `Close in-stage on release` and `Announce release in Google
Chat`; none of them ship code. Keyword matching flagged all three as drift.

**Drift is not automatically a problem.** After the outage, `newsletter-tool` was
one commit ahead of its last successful deploy — but that commit touched only
`firebase.json`, `deploy.yml` and `WORKLOG.md`. No site content, no function
source, and the function had already been relabeled by hand. Nothing to ship.
Always check *what* the delta contains:

```bash
gh api repos/The-Life-Church/<repo>/compare/<last-ok-sha>...main \
  --jq '{ahead:.ahead_by, files:[.files[].filename]}'
```

## Non-Actions deploy paths

App Hosting rollouts don't appear in Actions at all. Compare the backend's state
to the repo tip:

```bash
firebase apphosting:backends:list --project the-life-church-apps
```

`ABIU` = auto-rollout. **`Disabled` means merging deploys nothing** — true for
`Signature-Manager` and `axis-conference-app`. `Runtime: N/A` alongside an old
`Updated Date` suggests the backend was never successfully rolled out.

(`apphosting:rollouts:list` is **not** a firebase CLI command; don't reach for it.)

## Outage-specific findings worth remembering

- **A cancelled run is not a failed run.** `newsletter-tool`'s deploy showed
  `failure` at the run level with zero failed steps — the job was cancelled by the
  platform. Check `jobs[].steps` before diagnosing a real break.
- **Zombie runs exist.** One `Check` run sat `queued` with **zero jobs ever
  allocated** and would never have started. `gh run cancel` clears it; it can't be
  re-run (`This workflow is already running`).
- **Webhooks throttled means merged ≠ deployed.** During the outage GitHub
  processed ~15% of webhook triggers, so pushes silently failed to start any
  workflow. Two MPNext PR branches had **no checks at all** at their head SHA —
  not red, *absent*, which is easier to miss and worse. Re-running old runs
  re-tests dead SHAs; trigger fresh ones instead (`gh workflow run <wf> --ref
  <branch>` where `workflow_dispatch` exists).
- **Absent checks read as "fine" in a PR list.** `gh pr checks <n>` saying
  "no checks reported" deserves the same alarm as a failure.

## What to do with the result

If prod is correct, **do nothing** — resist re-deploying to feel better. A
redundant deploy of unchanged content is noise at best, and on a repo with no CI
gate it's a chance to ship something unreviewed.

If there is real drift, prefer re-running the deploy workflow over pushing an
empty commit, so history stays clean. Note that a manual `firebase deploy` fixes
production but **does not** clear a red X in Actions — those are two separate
facts, and conflating them is how a repo ends up looking permanently broken while
being perfectly live.
