# software/chrome — Google Chrome managed preferences

Force-installs the standard Google web apps (PWAs) on managed Macs so users never have to
install them by hand — **force-installed at the top-level org in Google Workspace** (Admin
console → Chrome Enterprise Core), so every enrolled Chrome browser gets them fleet-wide.
Pairs with `hardware/dock` — once Chrome installs these PWAs, the dock seeder finds them in
`~/Applications/Chrome Apps.localized/` and docks them.

## What's here

- `managed-preferences.plist` — the `WebAppInstallForceList` dict; the source of record for
  the 8 app URLs. Primary delivery is the Admin console (top-level org); this file is the
  paste body for the **Mosyle Per-App Configuration** fallback route.

## Deploy

**Primary (in use): Google Workspace Admin console — Chrome Enterprise Core.** Force-installed
at the **top-level org**, so every enrolled Chrome browser gets them fleet-wide.

**admin.google.com → Devices → Chrome → Apps & extensions → Users & browsers →** select the
**top-level org → "+" → Add by URL.** Add each URL below, set **Installation policy: Force
install** and **Open in a separate window**:

    https://mail.google.com/
    https://calendar.google.com/
    https://meet.google.com/
    https://chat.google.com/
    https://drive.google.com/
    https://docs.google.com/document/
    https://docs.google.com/spreadsheets/
    https://docs.google.com/presentation/

Use `https://chat.google.com/` for Chat — `mail.google.com/chat/` force-installs as a
URL-named placeholder. Don't pick "Force install **+ pin**": pin targets the ChromeOS shelf,
not the macOS Dock (docking is the `hardware/dock` seeder's job).

**Alternative: Mosyle Chrome Per-App Configuration (PLIST).** Same effect via Mosyle instead —
paste `managed-preferences.plist` into the Chrome app's Per-App Config (Configure App PLIST →
Activate → type PLIST → select all, paste). **Pick one source, not both** — running it in the
Admin console *and* Mosyle makes the cloud and platform policy layers fight over precedence.

> **Mosyle paste gotcha (PLIST route only):** Mosyle's PLIST field wants the `<dict>…</dict>`
> block **only** — it rejects a full plist document (`<?xml … ?>` / `<!DOCTYPE …>` / `<plist>`
> wrapper) as "The XML inserted is not valid." So `managed-preferences.plist` is stored as
> exactly that bare `<dict>` fragment, comment-free — open it, select all, paste. It is
> intentionally **not** a standalone plist (`plutil -lint` won't pass it — expected).

`WebAppInstallForceList` installs the apps silently; users can't remove them, and they open in
standalone windows. Admin-console pushes apply on the next policy refresh; the Mosyle PLIST
route needs one Chrome restart to take effect.

## Sequencing with the dock seed

Chrome installs → this config applies → user opens Chrome (one restart) → PWAs install →
the `hardware/dock` retry loop finds them and docks them. The dock seeder's 10-min retry
window is what absorbs the gap between provisioning and the PWAs appearing.

## Verify on a test Mac before fleet rollout

1. `chrome://policy` → **Reload policies** → `WebAppInstallForceList` status = **OK**, values match.
2. Confirm each generated bundle id matches what the dock seeder hardcodes
   (`hardware/dock/setup-dock.sh`, the `app_bid[...]` map):
   ```bash
   mdls -name kMDItemCFBundleIdentifier -raw ~/Applications/Chrome\ Apps.localized/Gmail.app
   ```
   | App | start_url here | expected id |
   |---|---|---|
   | Gmail | `https://mail.google.com/` | `com.google.Chrome.app.fmgjjmmmlfnkbppncabfkddbjimcfncm` |
   | Calendar | `https://calendar.google.com/` | `…kjbdgfilnfhdoflbpgamdcdgpehopbep` |
   | Meet | `https://meet.google.com/` | `…kjgfgldnnfoeklkmfkjfagphfepbbdan` |
   | Chat | `https://chat.google.com/` | `…pommaclcbfghclhalboakcipcmmndhcj` |
   | Drive | `https://drive.google.com/` | `…aghbiahbpaijignceidepookljebhfak` |
   | Docs | `https://docs.google.com/document/` | `…mpnpojknpmmopombnjdcgaaiekajbnjb` |
   | Sheets | `https://docs.google.com/spreadsheets/` | `…fhihpiojkbmbpdjeoajapmgkhlnakfjf` |
   | Slides | `https://docs.google.com/presentation/` | `…kefjledonklijopmnomlcbpllchaibag` |

   The app id is a hash of the install `start_url`. If a URL here produces a different id
   than the seeder expects, reconcile: tweak the URL until ids match, or update the
   seeder's `app_bid` to the id Chrome actually generated. **This is the one thing that
   must be confirmed before rollout** — a mismatch means the dock seeder won't recognize
   the installed PWA.

3. Confirm the `.app` **shims are actually on disk** (not just present in Chrome's
   `chrome://web-app-internals` registry) — the dock seeder finds apps by disk path:
   ```bash
   ls ~/Applications/Chrome\ Apps.localized/
   ```
   All 8 should appear as `<Name>.app`. **This is a required pilot acceptance check** (see
   below) — a registry entry without an on-disk shim won't dock.

## Multi-profile & shim reliability

`WebAppInstallForceList` is delivered **machine-scoped** (`scope: machine` in
`chrome://policy`), so it force-installs the 7 web apps into **every** Chrome profile on
the device. Two consequences:

- **Profile picker on multi-profile machines.** When a PWA is installed in 2+ profiles,
  Chrome collapses to a single `.app` shim that opens a profile chooser on launch. It
  still lives at the same path and docks normally — but staff who run multiple work
  profiles get a picker when they click it. Single-profile Macs (the common provisioning
  case) don't.

- **Stale OS-integration can suppress shim creation.** On a machine where a user had
  *previously* hand-installed one of these PWAs (sources include `Sync` / `UserInstalled`
  in `web-app-internals`) and the `.app` was later removed, Chrome may re-sync the
  *registry* entry from the force-list without rewriting the on-disk shim — so the app
  reads as installed but has no `.app`, and the seeder skips it. A clean, `Policy`-only
  install (a freshly provisioned Mac with no prior copy) writes the shim normally. To
  force a missing shim on an affected machine, launch the app once from `chrome://apps`;
  Chrome reconciles and writes the `.app`.

**Pilot requirement:** the reasoning says a fresh provisioning Mac installs all 8
`Policy`-clean and gets shims — but verify it, don't assume. On the pilot Mac, after Chrome
settles, confirm `ls ~/Applications/Chrome Apps.localized/` shows all 8 before trusting the
dock seed. `hardware/dock/report-status.sh` surfaces any PWAs left unresolved after the
retry cap.

## Opening links in the app (per-user, not enforceable)

`default_launch_container: window` makes each PWA open in its own window **when launched**
(from the Dock or `chrome://apps`). It does **not** make clicked links route into the app —
e.g. a Chat link opening in the Chat window. That's Chrome's *navigation capturing*
(Chrome 139+), and **there is no MDM policy to force it**: the only policy that configures
installed-app behavior, `WebAppSettings`, exposes just `manifest_id`, `run_on_os_login`,
`prevent_close_after_run_on_os_login`, and `force_unregister_os_integration` — no
link-capturing field. Don't add one to the plist; an unknown key is silently ignored.

It's a **per-user toggle** instead. Staff who want links to open in the app:

1. Open the app (e.g. Chat) as a window, or go to `chrome://apps`.
2. In the app's settings (kebab menu → **"Open supported links in this app"**, or the
   `…` menu in the app title bar), enable it.

After that, in-scope links open in the app window. Google controls whether a given app is
eligible (via its web manifest); we can't change that from Mosyle.

## Optional: sign-in enforcement

Force-install doesn't require sign-in (it's browser-level), so the apps appear regardless.
There's no supported way to silently hand Chrome the Mosyle/ABM Google identity. To make
the user sign in once via Workspace SSO (so Gmail etc. open to their account), add these
keys to the dict:

```xml
<key>BrowserSignin</key>
<integer>2</integer>                       <!-- 2 = force sign-in -->
<key>RestrictSigninToPattern</key>
<string>.*@thelifechurch\.com</string>     <!-- only TLC Workspace accounts -->
```

Left out of the default plist — enable deliberately, it changes the first-run experience.
