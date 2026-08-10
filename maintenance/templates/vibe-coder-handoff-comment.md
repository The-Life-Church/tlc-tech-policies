# Template — telling a non-developer you changed their repo

Use when IT has pushed to a repo whose primary contact builds by prompting Claude
rather than by running commands. See
[`../repo-inventory.md`](../repo-inventory.md) for who that applies to.

Post it as a comment on the PR that made the change, @-mentioning them.

## Why this shape

They do not run `git pull` — they *ask Claude to*. So the deliverable is **a
prompt they can paste**, not a command they'd have to know how to run. Everything
else is context they can skip.

Three things the prompt must do:

1. **Lead with it.** It's the only part with an action; burying it under
   explanation means it gets missed.
2. **Tell Claude how to resolve the lockfile conflict.** Without
   *"keep the version from GitHub, not the local one"*, Claude may helpfully
   resolve in favour of their stale copy and silently undo the fix.
3. **End with a confirmation step** so they get a signal it worked instead of
   having to judge for themselves.

Also worth including, in plain words: that you didn't touch their work, whether
their live site is affected, and why any remaining alerts are deliberate — an
unexplained leftover count reads as "IT left me a mess".

Avoid: "dependencies", "transitive", "lockfile" as bare nouns, severity ratings,
CVE numbers, and anything implying they did something wrong.

---

## Template

> @<their-github-handle> heads up — I made a security update to this project.
> Nothing broken, but **there's one thing to have Claude do before you start
> working again.**
>
> ## Paste this to Claude at the start of your next session
>
> ```
> Before we do anything else: pull the latest changes from GitHub for this
> project, then reinstall the dependencies with <npm ci | pnpm install>.
> Jacob updated <lockfile> with security patches. If there is a conflict in
> <lockfile>, keep the version from GitHub (main), not the local one.
> Then <a verification command, e.g. run npm run check-data> and tell me
> whether it passed.
> ```
>
> That's the whole ask — Claude will know what to do with it.
>
> ## Why
>
> Your project uses a few hundred small pieces of code written by other people —
> the login helper, the thing that draws your diagrams, that kind of thing.
> Nobody writes those from scratch. Every so often someone finds a security bug
> in one and publishes a fixed version.
>
> GitHub had flagged <N> of those here. I moved them to the fixed versions —
> <N> down to <M>, including the most serious one.
>
> **I didn't touch anything you made.** No design, no layout, no wording.
> <And your live site is unaffected because … | Your site already has this and
> I confirmed it's serving normally.>
>
> ## If you skip the prompt above
>
> Your next push will probably hit a confusing conflict on a file called
> `<lockfile>`. Not dangerous, just annoying to untangle. Running the prompt
> first avoids it entirely.
>
> ## So it doesn't look like a loose end
>
> <M> are still showing, on purpose rather than forgotten — those pieces are
> locked to specific versions by <framework> itself, and forcing them would more
> likely break your build than help. They only run while building, never for
> someone visiting the site. They'll clear when <framework> updates.
>
> If anything looks odd after running that prompt, send me what Claude said and
> I'll sort it out — don't spend time fighting it.

---

## Worked examples

- Brandon / `tlc-wall-boxes` — [PR #3 comment](https://github.com/The-Life-Church/tlc-wall-boxes/pull/3#issuecomment-5242443146)
- Nate / `process-wiki` — [PR #5 comment](https://github.com/The-Life-Church/process-wiki/pull/5#issuecomment-5242951072)

The Nate one adds a repo-specific touch worth copying: it calls out that the
diagram library moved, because that's the one change with a plausible visible
effect. Flagging the *specific* thing they might notice beats a generic "let me
know if anything looks off".
