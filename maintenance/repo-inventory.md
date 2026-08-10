# Repo inventory — what deploys, what gates it, who owns it

**Read this before merging a PR in any org repo.** Whether a merge reaches
production is not visible from the PR, and it differs per repo.

Verified 2026-08-10 against the GitHub and Firebase APIs. Re-verify with
[`scripts/deploy-drift-audit.sh`](scripts/deploy-drift-audit.sh) rather than
trusting this table's age.

## Repos with a deploy path

| Repo | Firebase project | Merge → prod? | How it deploys | Functions codebase | CI gate on PRs |
|---|---|---|---|---|---|
| `tlc-resources` | `the-life-church-apps` | **yes** | Actions → `firebase deploy` (hosting + functions + rules + storage) | `resources` | `Check` (node --check, eslint, 167 tests) |
| `newsletter-tool` | `the-life-church-apps` | **yes** | Actions → `firebase deploy` (hosting + function) | `newsletter` | none |
| `process-wiki` | `the-life-church-apps` | **yes** | App Hosting auto-rollout on push to `main` | — | none |
| `tlc-wall-boxes` | `tlc-production-apps` | **yes** (static only) | Actions → Firebase Hosting | — | none |
| `tlc-checkin-landing` | `the-life-church-apps` | **yes** (static) | Actions → Firebase Hosting | — | none |
| `wp-content` | — | **yes** | Actions → WP Engine (`main` → production, `stage` → staging) | — | none |
| `MPNext` | `mp-app-hub` | **yes** | Actions → prod on `main`, test on `stage` | — | `Tests`, `Security Lint` (both required) |
| `Signature-Manager` | `the-life-church-apps` | **no** | App Hosting backend exists but auto-rollout is **Disabled**; `ui.html`/`backend/` reach users via `clasp push` to Apps Script | — | `Repo Activity` only (trivial); vitest exists in `web/` but isn't wired to CI |
| `four-quadrants` (Four Pillars) | `the-life-church-apps` | **no** | Manual `firebase deploy` from a maintainer's machine — **no CI at all** | `four-pillars` | none |
| `tlc-new-loc-tracker` | `the-life-church-apps` | **no** | Manual; no deploy workflow | — | none |

Repos with no deploy path at all (safe to merge freely, nothing ships):
`tlc-claude-plugins`, `tlc-app-template`, `tlc-pco-mcp`, `axis-conference-app`,
`axis-conf-games`, `team-care-tracker`, `llbs-video-translation`,
`god-and-race`, `tlc-it-support-agent`, `tlc-process-alignment-agent`,
`ministryplatform-help-center`.

## Shared Firebase project: `the-life-church-apps`

Several unrelated repos deploy Cloud Functions into this one project, which is
why every one of them must name a `codebase` in `firebase.json`. See
`software/firebase/README.md` §2 — *The orphan-deletion trap* — for the full
mechanism and the 2026-08-05 incident that produced the rule.

| Function | Region / gen | Codebase | Owning repo |
|---|---|---|---|
| `gatekeeper` | us-central1 · v1 | `resources` | `tlc-resources` |
| `signupgate` | us-east1 · v2 `beforeUserCreated` | `resources` | `tlc-resources` |
| `app` | us-central1 · v1 | `newsletter` | `newsletter-tool` |
| `chat` | us-central1 · v2 | `it-agent` | `~/TLC_Dev/local_dev/Internal IT Support/agent` (not an org repo) |
| `fourQuadrantsGate` | us-central1 · v2 | `four-pillars` | `four-quadrants` |

`signupgate` is a **project-wide** Auth blocking function: if it is missing or
misconfigured, first-time sign-in fails for every app on the project while
existing users are unaffected — which presents as "intermittent" login problems.

## Who maintains what

**This repo is public, so no individual names appear here.** The current
person-to-repo mapping is the repo's collaborator list on GitHub, which is
access-controlled and can't go stale. What matters for this runbook isn't *who*
owns a repo but *how they work*, which changes how you hand a change back.

| Repo | Maintained by | Hand changes back via |
|---|---|---|
| `tlc-wall-boxes`, `four-quadrants`, `process-wiki`, `newsletter-tool` | ministry / creative staff | a handoff comment with a paste-ready prompt |
| `tlc-resources`, `Signature-Manager`, `tlc-tech-policies`, `MPNext` | IT / Dev | normal PR review |

For the first group, use
[`templates/vibe-coder-handoff-comment.md`](templates/vibe-coder-handoff-comment.md).
They drive their projects by prompting Claude rather than running commands, so a
comment full of shell invocations doesn't land — a prompt they can paste does.

Check the collaborator list before assuming a repo falls in either group:

```bash
gh api repos/The-Life-Church/<repo>/collaborators --jq '.[].login'
```

## Gotchas worth knowing before you touch these

- **`newsletter-tool` and `tlc-resources` have no `concurrency` group** on their
  deploy workflows. Merging two PRs in quick succession fires two parallel
  `firebase deploy` runs against the same function. Merge one, wait, then the next.
- **`four-quadrants` has no CI**, so nothing catches a bad change before a manual
  deploy. Its README carries the scoped deploy command; a bare `firebase deploy`
  from there is what caused the 2026-08-05 incident.
- **`tlc-wall-boxes` serves its repo root** (`"public": "."`) and only ignores
  `nextjs-template/**`, `*.md`, dotfiles and `node_modules` — so the Next.js
  scaffold's `package.json`, `pnpm-lock.yaml`, `tsconfig.json` and `app/*.tsx`
  are publicly readable on the live site. `.env` files are correctly excluded by
  the dotfile rule. Worth fixing before Phase 2 adds server-side logic.
- **`Signature-Manager` has two renderers.** `web/lib/signature/render.ts` and
  `backend/Utils.gs` implement the same escaping, and the Apps Script half is the
  one that actually writes signatures to Gmail. CodeQL cannot see `.gs` files, so
  a finding in the TypeScript copy usually means the same bug is unreported in the
  more important one.
- **`Signature-Manager`'s App Hosting URL returns 404** with `Runtime: N/A` and no
  rollout since 2026-06-11 — it reads as never-deployed rather than broken.
  Confirmed intentional as of 2026-08-10.

---

*Managed by The Life Church IT/Dev team.*
