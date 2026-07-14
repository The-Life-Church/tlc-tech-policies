# Firebase at TLC — IT Runbook

How Firebase projects, access, and deploys work for staff-built apps. This is the IT-facing operational doc — the **one live copy** of every rule and command. Builder-facing guidance (dev loop, emulators, what-to-do-when) lives in the app template repo's `CLAUDE.md` and travels with each clone.

**The model in one paragraph:** builders develop locally against the Firebase **emulators** (zero cloud IAM, no login, `demo-` project), and **ship by git push** — App Hosting auto-rollouts or a GitHub Action own the deploy credentials, never a human. IT provisions each app once (checklist below); after that, merging a PR is deploying. Humans hold data access scoped to their own app; nobody holds deploy roles or service-account keys.

---

## 1. Where an app lives — the two-tier rule

| The app is… | It lives… |
|---|---|
| Static, no data, no functions, no login beyond the resources gate | The **resources site** (`resource-site` skill) or a Hosting site on the shared project. No new IAM, ever. |
| Anything with Firestore, Functions, Auth needs, or App Hosting | Its **own Firebase project** (`tlc-<app>-prod`) — end state. Until the billing-account project quota is raised (see §7), new apps join the **shared vibe-coder project** using the isolation recipe in §2. |

**Quota note:** the ~5-project cap is the default project-link quota on the billing account, not an architectural limit. File the increase (Billing → quota increase request); migrate data-bearing apps to per-app projects as it lands.

## 2. Shared-project isolation recipe

Inside one project, per-app isolation is real for data and absent for deploy/auth — design around that:

| Surface | Per-app? | How |
|---|---|---|
| Firestore | ✅ | **Named database per app** + IAM condition on every grant: `resource.type == "firestore.googleapis.com/Database" && resource.name == "projects/<PROJECT>/databases/<app-db>"`. Rules are also per-database. |
| Storage | ✅ | Bucket per app (`tlc-<app>-assets`); grants on the bucket, rules per bucket. |
| Hosting / App Hosting | ❌ no per-site/backend IAM | Humans get **no deploy roles**; isolation happens at the CI layer (§4) — each repo can only assume its own deploy identity. |
| Functions | ❌ deploy is project-wide | Per-app **codebases** (`firebase deploy --only functions:<app>`), deployed by CI only. |
| Auth | ❌ one pool per project | Fine for staff tools (everyone is `@thelifechurch.com`). Per-app admin tiers = **custom claims**, set by IT. Nobody gets Auth admin. |

Log visibility and project overview are shared — acceptable within one trust tier; full isolation arrives with per-app projects.

## 3. The builder bundle (per-builder IAM)

What a builder gets on the project their app lives in — nothing more:

```bash
PROJECT=<project-id>; BUILDER=<user>@thelifechurch.com; APP_DB=<app-db>

# Firestore read/write, scoped to their app's named database
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="user:${BUILDER}" --role=roles/datastore.user \
  --condition="title=${APP_DB}-only,expression=resource.type == \"firestore.googleapis.com/Database\" && resource.name == \"projects/${PROJECT}/databases/${APP_DB}\""

# user-credential API calls (this is what the Firebase MCP makes)
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="user:${BUILDER}" --role=roles/serviceusage.serviceUsageConsumer

# console visibility
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="user:${BUILDER}" --role=roles/firebase.viewer

# their app's asset bucket
gcloud storage buckets add-iam-policy-binding "gs://tlc-<app>-assets" \
  --member="user:${BUILDER}" --role=roles/storage.objectAdmin
```

Explicitly **not** granted: any Hosting/App Hosting role, Functions admin, Auth admin, `firebase.developAdmin`, and any `serviceAccountKey*` role. The Firebase MCP runs as the builder's login, so this bundle is also exactly what the MCP can and cannot do against prod. (While an app still uses `(default)`, drop the condition — it becomes meaningful the moment named DBs exist.)

## 4. Deploy paths — the decision table

| App type | Deploy path | Credentials involved |
|---|---|---|
| **App Hosting** (JS/Next.js apps) | **Native auto-rollouts.** Backend connected to the org repo (Developer Connect, IT one-time), live branch = `main`, **branch protection incl. admins** (PR + required checks). Merging is deploying. | None. The repo connection is the auth. |
| **Classic Hosting** (static) | **GitHub Action** running `firebase deploy`, authenticated via **Workload Identity Federation** — per-app deploy SA, WIF provider conditioned to `repository == "The-Life-Church/<repo>"`. | The SA, assumable only by that repo. **No JSON keys.** |
| **Manual CLI** (`firebase deploy`, `apphosting:rollouts:create`) | **IT break-glass only** — e.g. GitHub/Cloud Build outage. Never a builder workflow, never a Claude workflow. | IT's own login. |

Why manual-through-Claude is not a path: it ships whatever is on the laptop (not what's in git — no review, no reproducible build), it requires humans to hold deploy IAM this model deliberately withholds, and it contradicts the fleet policy's provisioning-command guardrail.

The quality gate is **branch protection, not the deploy tool**: only reviewed, checks-passing code can reach `main`, so auto-rollout/CI faithfully shipping `main` is safe by construction. Enforce for admins too — an admin direct-push would deploy unreviewed code.

## 5. Deploy identities

- **App Hosting:** none to manage. Rollback = re-deploy a prior rollout from the console. Runtime config/secrets via `apphosting.yaml` + **Secret Manager** (grant the backend's runtime SA `secretAccessor` per secret) — production apps never use `.env` files.
- **Static Hosting:** one SA per app: `roles/firebasehosting.admin` + `roles/firebase.viewer` (note: `firebasehosting.admin` is project-wide — the WIF repo condition is what scopes it to one app). Migrate any key-based deploy SA (`firebase init hosting:github` mints JSON keys into GitHub secrets) to WIF, then **delete the user-managed keys**.
- **Keys, generally:** nobody needs standing key powers. If a key is truly unavoidable, grant `roles/iam.serviceAccountKeyAdmin` **on that one SA resource** (`gcloud iam service-accounts add-iam-policy-binding …`), never at project level. Once all deploy SAs are on WIF, enable the org policy `constraints/iam.disableServiceAccountKeyCreation` and close the class permanently.

## 6. App onboarding checklist (the project factory)

Run once per new app; afterwards the builder ships by merging.

1. **Repo** — create the org repo from the app template (private, `The-Life-Church`); builder gets write access.
2. **Home** — per-app project (`tlc-<app>-prod`, billing + budget alert, enable APIs) — or, shared-project interim: create the named Firestore DB, the `tlc-<app>-assets` bucket, and the Hosting site / App Hosting backend.
3. **Deploy wiring** — App Hosting: connect the repo, live branch `main`, `apphosting.yaml` present. Static: confirm the template's deploy workflow, create the deploy SA + WIF pool/provider conditioned to the repo.
4. **Branch protection** on `main` — PR required, checks required, include admins.
5. **Builder bundle** (§3) for each builder on the app.
6. **Secrets** — into Secret Manager, wired via `apphosting.yaml` / workflow env; runtime SA granted per-secret access.
7. **GOLIVE ledger** — seed `GOLIVE.md` rows for everything provisioned (`Active`), per the fleet policy.
8. Confirm the loop: builder merges a trivial PR → rollout/Action fires → site updates. Done.

## 7. Tooling and the MCP

- **firebase-tools** is installed globally and pinned (`software/firebase-tools/` — same pattern as hyperframes: npm global, bump-pins, Mosyle). It carries the CLI, the **emulators**, and the **MCP server** in one binary. The Firestore emulator needs Java (`software/java/`, bootstrapped automatically). **Project repos carry no CLI version of their own** — `.mcp.json` and scripts reference the bare `firebase` command, so forks never go stale and one bump PR updates the entire fleet.
- **MCP config** (ships in the template's `.mcp.json`): point at the **global binary**, never the docs' `npx -y firebase-tools …` form — MCP server spawning bypasses the Bash `npx` deny rule AND `npx -y` fetches latest, silently skipping the reviewed pin.
- **MCP reach = the login's IAM.** Builders aren't logged into the CLI → MCP against prod fails closed; against the emulators (`demo-` project, no login) it's fully capable. IT machines are logged in → same config manages real projects.

## 8. Related decisions

- Provisioning-command deny rules (`firebase deploy`/`init`, `gcloud init`, `vercel`, `heroku create`) — parked; CI-only deploys make fleet-wide denial simpler (never deny `firebase emulators:*`). Decide alongside the org key policy in §5.
- **Vercel** — evaluated and declined as the builder platform (per-seat cost, loses integrated Auth+Firestore+rules, policy/skill churn); remains the `web-stack` carve-out for SQL-heavy IT builds.
- **App-level dependency staleness** — projects fork off the template and never pull from it again, so their own `package.json` deps (the `firebase` web SDK etc.) rot per-repo; template bumps reach nobody. Future answer: org-wide Renovate with a `minimumReleaseAge` cooldown opening governed bump PRs per repo. Parked — revisit when the fleet of app repos is big enough to hurt.
- Builder-facing counterpart of this doc: the app template repo (`CLAUDE.md` there carries the verbiage→requirements table, emulator loop, MCP boundaries, seed scripts).

---

*Managed by The Life Church IT/Dev team — questions to IT.*
