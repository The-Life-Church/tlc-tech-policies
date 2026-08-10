# Runbook — triaging code-scanning alerts

Written from the 2026-08-10 pass, which took the org from **19 open alerts to 5**.
Unlike dependency bumps these need judgement: some are real bugs, some are correct
code the rule can't understand, and "fixing" the latter breaks working features.

## Inventory

```bash
gh api "/orgs/The-Life-Church/code-scanning/alerts?state=open&per_page=100" --paginate
```

Group by `rule.id` and `most_recent_instance.location.path`. Then sort into three
tiers before writing any code — the tiers have completely different economics.

## Tier 1 — mechanical, no judgement needed

`actions/missing-workflow-permissions`, `actions/unpinned-tag`. Do these first;
they're a few lines, zero risk, and they shrink the list so the real work is
visible.

- **Missing permissions:** add a workflow-level `permissions:` block with the
  least the job needs. Usually `contents: read`. A deploy job that authenticates
  with a service-account secret never uses `GITHUB_TOKEN` at all, so the default
  write access is pure exposure.
- **Unpinned tag:** only *third-party* actions are flagged; GitHub's own
  `actions/*` are not. Pin to the tag's commit SHA with the version in a trailing
  comment:
  `uses: google-github-actions/auth@7c6bc770dae815cd3e89ee6cdf493a5fab2cc093 # v3`.
  Resolve with `gh api repos/<owner>/<repo>/git/ref/tags/<tag> --jq '.object.sha'`.

Prefer a pin another repo already runs green rather than a fresh SHA — it's
pre-validated and it converges the fleet. `tlc-resources` is the reference for
both patterns.

## Tier 2 — real findings; read the code first

These are worth fixing, but only after you understand the call sites. Two lessons
from the last pass:

**Check for a mirror the scanner can't see.** `escapeHtml` in
`Signature-Manager/web/lib/signature/render.ts` escaped only `& < >`, missing
quotes — genuinely exploitable, since templates place placeholders inside
attributes (`<a href="{siteUrl}">`). But `esc_` in `backend/Utils.gs` was the same
function character-for-character, and **that** is the half that writes signatures
to Gmail. **CodeQL does not scan `.gs`**, so the alert pointed at the less
important copy. Always grep for a sibling implementation before calling one fixed.

**A passing test can encode the bug.** That repo had
`expect(escapeHtml('… "e"')).toBe('… "e"')` — an assertion that quotes stay raw.
The gap was codified as correct behaviour. Fixing the code broke the test, which
is the correct outcome; update the test and add one that proves the exploit is
closed.

**Fix the class, not the instance.** Five `js/incomplete-sanitization` alerts in
`ui.html` were all
`onclick="fn('" + name.replace(/'/g,"\\'") + "')"` — quotes escaped, backslashes
not, so `a\');alert(1);//` closed the string and executed. Rather than patch the
regex five times, a single `jsArg()` helper (`JSON.stringify` for a valid JS
literal, then `escapeAttr` for the HTML attribute) fixed all five and prevents the
sixth.

**When a file has no test harness, verify out-of-band.** `ui.html` is served by
Apps Script and can't be unit-tested. Extract the helper *verbatim from the file*
with `new Function(...)`, run it against hostile inputs, and assert the properties
that matter — output contains no raw `"` or `<>`, and
`JSON.parse(decodeEntities(out)) === input` so the handler still receives the real
value. Cite that in the PR. Verification you can point at beats a claim.

## Tier 3 — needs a decision, not a patch

`js/missing-rate-limiting` fires on essentially every Express route in a Cloud
Function. It is not pure noise — `tlc-resources` genuinely exposes public
endpoints like `/api/requestAccess` — but the answer is a design conversation
about whether these endpoints want rate limiting at all, not a lint fix. Leave
them open until that's decided; an open alert honestly describing an undecided
question is better than a dismissal that closes the conversation.

## Dismissing correctly

Some alerts should never be "fixed" because the flagged behaviour is the feature.
`ref.current.innerHTML = initialHtml` inside a contenteditable WYSIWYG editor is
the editor working; escaping it would render markup as literal text.

```bash
gh api -X PATCH /repos/The-Life-Church/<repo>/code-scanning/alerts/<n> \
  -f state=dismissed \
  -f dismissed_reason="won't fix" \
  -f dismissed_comment="…"
```

- Valid reasons: `false positive`, `won't fix`, `used in tests`.
- **`dismissed_comment` is capped at 280 characters** — the API rejects longer with
  a 422. Write the short version there and put the full reasoning in the PR that
  handled the rest of the batch.
- Prefer `used in tests` for local probe and dev scripts; it's more accurate than
  `false positive`, which asserts the rule itself is wrong.
- Say *why it isn't reachable*, not just "not a problem". A future maintainer
  should be able to tell whether your reasoning still holds after the code moves.

## Alerts close on the next scan, not on merge

Default-setup CodeQL runs on push to `main` and weekly. After merging a fix the
alert stays open until that scan finishes, so don't report a number until you've
watched the run and re-queried:

```bash
gh run list --repo The-Life-Church/<repo> --workflow CodeQL --branch main --limit 1
```

Also note **default-setup CodeQL runs cannot be re-run** — `gh run rerun` returns
`This workflow run cannot be retried`. A red CodeQL X on `main` clears on the next
push or the weekly schedule, and there is no way to force it sooner.
