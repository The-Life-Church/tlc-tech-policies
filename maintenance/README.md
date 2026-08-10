# Maintenance — cross-repo upkeep of TLC org repos

Recurring procedures IT runs **across** the org's GitHub repos: dependency
advisories, code-scanning triage, and working out what is actually deployed.

This area is the odd one out in this repo, so it's worth stating why it lives
here. `software/` and `hardware/` describe things installed **on devices**;
`mosyle/` is the **delivery mechanism** for those. This folder acts on
**repositories** instead. It follows the same conventions — one folder per
concern, each README the source of truth for its own details — and it has the
same precedent as `software/firebase/`, which is docs-only with no installer.

**Nothing in here is Mosyle-facing.** No script in `maintenance/scripts/` should
ever be wired to a Mosyle Custom Script. Everything here runs from a maintainer's
own machine against the GitHub and Google Cloud APIs. Merging to `main` deploys
the *fleet* surfaces in `software/` and `hardware/`; it must stay inert for this
folder.

## What's here

| File | Use it when |
|---|---|
| [`repo-inventory.md`](repo-inventory.md) | **Read this before merging anything.** Which repos deploy to production on merge, what gates exist, which Firebase project and functions codebase each one owns. |
| [`runbooks/dependabot-sweep.md`](runbooks/dependabot-sweep.md) | Dependabot alerts have piled up and you want them actually cleared. |
| [`runbooks/codeql-triage.md`](runbooks/codeql-triage.md) | Code-scanning alerts need sorting into fix / dismiss / decide, and dismissals need defensible reasons. |
| [`runbooks/deploy-drift-audit.md`](runbooks/deploy-drift-audit.md) | After an outage or a confusing week: is every repo's `main` actually live? |
| [`templates/vibe-coder-handoff-comment.md`](templates/vibe-coder-handoff-comment.md) | You changed someone's repo and they need to pull before their next session. |
| [`scripts/deploy-drift-audit.sh`](scripts/deploy-drift-audit.sh) | The audit in executable form. |

## The one rule that matters most

**Merging is deploying in several of these repos**, and which ones is not
guessable from the outside — `tlc-resources` and `newsletter-tool` ship to
production through CI on merge to `main`, `process-wiki` auto-rollouts through
App Hosting, and `Signature-Manager` deploys nothing because its rollout is
switched off. Check `repo-inventory.md` first. Merging several PRs quickly in the
*same* repo fires parallel deploys against the same resources; sequence them.

## Deliberately not here: a register of unfixed vulnerabilities

**This repo is public.** A tidy list of "these production apps carry known
unpatched high-severity advisories, and here is why we are not fixing them" is a
useful document for the wrong reader.

The runbooks therefore record **criteria** — how to decide when to hold, and what
a hold means — while the current state of any hold stays in the GitHub Security
tab, which is access-controlled and always accurate. Dismissed code-scanning
alerts carry their reasoning in the dismissal comment; held dependency advisories
carry theirs in the PR that fixed the rest. Both are the right place: attached to
the thing itself, visible to people who can already see the alert.

---

*Managed by The Life Church IT/Dev team.*
