# Self-Service Progress Wrapper

Wraps any fleet installer with a native progress window (via [swiftDialog](../dialog/)) for **Mosyle Self-Service** catalog items. Without it, "Install Now" runs the Custom Script silently — a multi-minute install looks like a dead button. With it: a window appears immediately, streams the installer's own step lines as progress text, and ends with an unambiguous ✓ installed / ⚠ needs-IT state.

## The rule that keeps background runs silent

**The dialog is triggered by the entry point, never by the installers.** The tool installers are unchanged and never gain UI — recurring schedules, remote pushes, and provisioning keep calling `software/<tool>/install.sh` directly and stay silent forever. Only Self-Service catalog items call this wrapper, which downloads and runs the *same* installer underneath and streams its output. Two Mosyle bodies per tool, one per context — see each tool's README.

## How it behaves

- **Degrades to silent, never blocks:** no console user, or swiftDialog missing and its bootstrap fails → the install proceeds with no window. Presentation only.
- **Exit code passes through** — Mosyle's success/failure indicator for the Self-Service item reflects the real installer result.
- **Failure UX:** friendly message, the kept log path, and a pointer to staff.thelifechurch.com — no more silent failures.
- **Allowlist only:** the wrapper maps known tool slugs to repo paths and refuses anything else.
- Progress bar advances per step line (capped at 90% until actually done — it never fakes completion). Command files live at `/var/tmp/tlc-dialog-<tool>.cmd`, truncated per run.

## Self-Service catalog blocks

`<tool>` slugs: `firebase-tools`, `hyperframes`, `gh`, `xcode`, `staff-dock`, `node`, `java`, `ffmpeg`, `higgsfield`. Pattern (swap slug + display name):

```bash
#!/bin/bash
# TLC Self-Service — Firebase Tools (with progress window)
# Runs software/firebase-tools/install.sh with a swiftDialog progress UI.
# Self-Service catalog items ONLY — background/recurring entries use the silent block instead.
# root · Self-Service · scope: vibe coders / IT-dev
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/selfservice/with-progress.sh" | bash -s -- firebase-tools "Firebase Tools"
```

The per-tool Self-Service blocks are also in each tool's README next to its silent block.

## Test-Mac checklist (before relying on it)

1. Click a wrapped item while logged in → window appears within ~2s, step text streams, ends in ✓ with an enabled Done button.
2. Force a failure (e.g. briefly wrong URL) → ⚠ state with log path; Mosyle shows the item failed.
3. Run the same wrapped item via a scheduled push with **nobody logged in** → fully silent, installer still runs.
4. Machine without swiftDialog → first Self-Service click bootstraps it, then proceeds.

Root-launched dialogs rendering in the user's session (`launchctl asuser` + `sudo -u`) is the one platform-sensitive piece — verify on the current macOS before scoping widely.
