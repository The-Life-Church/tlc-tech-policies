# hardware/dock — Dock Seeding

Seeds a clean, standard Dock on managed Macs at setup. Replaces the old standalone
`tlc-dock-seed` `.pkg` (formerly the `mosyle-dock-seed` repo) with a `curl | bash`
bootstrap that fits the rest of this repo's delivery model — no vendored binary, no
versioned package filenames, no Mosyle CDN/MD5 cache dance.

## What it does

It waits for a logged-in user **and for Google Chrome to be installed** before doing
anything — Mosyle doesn't order the bootstrap against the Chrome app install, so until
Chrome is present the run defers (status `waiting_for_chrome`) without wiping the Dock or
spending a retry attempt. If Chrome never installs (e.g. a failed app push) it gives up
after `MAX_DEFERS` checks (default 24 ≈ 4h) and reports `FAILED` instead of waiting
forever. Once Chrome is present, on first run it **wipes the Dock to a
clean slate** (`dockutil --remove all`) and adds the managed app set in order. A
short-lived LaunchDaemon (`com.tlc.dock.seed`) retries every 10 minutes (up to 6 attempts)
to catch apps — including Chrome PWAs — that hadn't finished installing yet. Once the set
is complete it removes itself.

It seeds **once** and does not enforce: after the first reset, retries only top up
missing managed apps and never re-wipe, so anything the user adds afterward is preserved.

## Managed Dock (in order)

Finder is pinned first by macOS; Trash is always last.

| # | App | Type |
|---|---|---|
| 1 | Google Chrome | native (`/Applications`) |
| 2 | Gemini | native |
| 3 | Gmail | Chrome PWA |
| 4 | Google Chat | Chrome PWA |
| 5 | Google Calendar | Chrome PWA |
| 6 | Google Meet | Chrome PWA |
| 7 | Google Drive (web) | Chrome PWA |
| 8 | ClickUp | native |
| 9 | System Settings | native |
| 10 | Self Service | native |

Gemini **is** in this set — new enrollments get it docked at slot 2. The standalone
`add-gemini-to-dock.sh` (see *Adding Gemini to an existing Mac* below) is just a separate way
to add Gemini to a Mac that didn't go through the enrollment seed.

**Docs, Sheets, and Slides are force-installed via Chrome but intentionally not docked**
(dock clutter) — they still install and are available in Launchpad / Chrome apps. To dock
them, add `gdocs gsheets gslides` back to `managed_order` and uncomment their entries in
`setup-dock.sh` (the entries are kept, commented, for exactly this).

**PWAs are best-effort.** The docked PWAs — Gmail, Chat, Calendar, Meet, Drive (web) —
live in the user's home (`~/Applications/Chrome Apps.localized/`) and only exist once
Chrome has installed them for that user. If they're absent through all retries, they're
skipped — the native apps still seed. Reliable PWA seeding depends on those PWAs being
present early (Chrome profile sync / managed policy). A shim that exists but isn't fully
rendered yet — a Chrome placeholder whose name is the raw start_url and whose icon is blank
— is treated as not-ready and skipped until it resolves, so the Dock never gets a
URL-labeled tile. (This is why the Chat force-install uses `https://chat.google.com/`, which
installs a clean named app, rather than `https://mail.google.com/chat/`, which force-installs
as a placeholder.)

To change the set or order, edit `managed_order` and the `app_label` / `app_bid` /
`app_paths` maps in `setup-dock.sh`. PWA bundle ids are the deterministic Chrome app ids.

## dockutil

Pulled from its signed upstream release (`kcrawford/dockutil`, Developer ID-signed,
installs `/usr/local/bin/dockutil`) — not vendored here. The version is pinned in
`install-staff-dock.sh` (`DOCKUTIL_VERSION`). Bump that string to move it.

## Deploy

> ⚠️ **Scope to new-enrollment Macs ONLY.** The first run wipes the Dock
> (`dockutil --remove all`) before seeding. A Mac that has never run this has no
> reset marker, so its first run **will erase the user's customized Dock** —
> including someone who's had their Mac for a year. **Never scope this to existing
> in-use Macs.** They still get the apps via the Chrome force-list (Admin console /
> Mosyle); their Dock is intentionally left untouched. The marker only prevents a
> *second* wipe on a Mac that's already been seeded — it does not protect a
> first-time run on an existing Mac.

**Mosyle → Custom Scripts → paste, scope to the provisioning (new-enrollment) group, run ONE-TIME:**

```bash
#!/bin/bash
# TLC Staff Dock — seed
# Installs: pinned dockutil + seeds the 13-app staff Dock (self-cleaning LaunchDaemon retries until apps land)
# root · ONE-TIME · scope: provisioning (new-enrollment) group
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/hardware/dock/install-staff-dock.sh" | bash
```

Run it **one-time**, not recurring — the LaunchDaemon owns the retry loop. Re-running the
bootstrap on an **already-seeded** Mac is safe (it tops up missing apps, won't re-wipe) —
but that safety comes from the marker, which a brand-new target won't have (see warning above).

## Adding Gemini to an existing Mac

New enrollments already get Gemini via the seeder (slot 2). This standalone script is for
adding Gemini to a Mac that **didn't** go through enrollment — e.g. an existing user — without
the destructive wipe. Deploy it as its own Mosyle Custom Script scoped to those Macs:

```bash
#!/bin/bash
# TLC Dock — add Gemini (existing Macs)
# Does: adds Gemini to the current user's Dock, non-destructive — installs nothing
# root · one-time · scope: existing Macs that didn't run enrollment
curl -fsSL "https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/hardware/dock/add-gemini-to-dock.sh" | bash
```

It's a one-shot, not a daemon: idempotent (does nothing if Gemini's already docked), and
**append-only** — it adds Gemini to the end of the current Dock without wiping or reordering
(safe on a customized Dock). Fully standalone: it installs dockutil from the signed upstream
release if missing, so it doesn't depend on the staff-dock bootstrap having run. The Gemini
app must already be pushed from Mosyle. (There's no managed-preferences profile for the Gemini
Mac app — its enterprise controls live in the Workspace Admin console GenAI settings, not a
local plist.)

## Checking status on a device

```bash
/usr/local/lib/tlc/dock/report-status.sh   # human-readable summary + exit code
cat /var/tmp/tlc-dock-status.txt            # raw status snapshot
cat /var/log/tlc-dock-seed.log              # full run log
```

Exit codes: `0` OK · `1` PENDING (still retrying, or `waiting_for_chrome`) · `2` FAILED
(retry cap hit with unresolved apps, or Chrome never installed within the wait window) ·
`3` ERROR (hard failure — check the log).

## Forcing a retry

```bash
sudo launchctl kickstart -k system/com.tlc.dock.seed
# if "Could not find service":
sudo launchctl bootstrap system /Library/LaunchDaemons/com.tlc.dock.seed.plist
```

## Forcing a full re-wipe

Re-running only tops up missing apps. To make it wipe and rebuild the Dock from scratch,
clear the reset marker first, then re-run the bootstrap (or kickstart the daemon):

```bash
sudo rm -f /var/tmp/tlc-dock-reset-done.txt \
           /var/tmp/tlc-dock-attempt-count.txt \
           /var/tmp/tlc-dock-defer-count.txt \
           /var/tmp/tlc-dock-status.txt
sudo launchctl kickstart -k system/com.tlc.dock.seed
```

## Rollback

```bash
sudo launchctl bootout system com.tlc.dock.seed 2>/dev/null || true
sudo rm -f /Library/LaunchDaemons/com.tlc.dock.seed.plist
sudo rm -rf /usr/local/lib/tlc/dock
sudo rm -f /usr/local/bin/dockutil
sudo rm -f /var/tmp/tlc-dock-attempt-count.txt \
           /var/tmp/tlc-dock-defer-count.txt \
           /var/tmp/tlc-dock-status.txt \
           /var/tmp/tlc-dock-reset-done.txt \
           /var/log/tlc-dock-seed.log
```

The Dock is not reverted on rollback — apps already seeded stay where they are. There's no
package receipt to forget (this is the trade for dropping the `.pkg`): inventory visibility
in Mosyle is lost, acceptable for a self-cleaning one-shot seeder.
