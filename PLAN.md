# BootCaptain — Research & Plan

*A consumer-friendly, exhaustive macOS startup manager: see everything that
launches at boot/login, understand what each item is and which app it belongs
to, disable what you don't need safely and reversibly, and get told plainly
when a startup item is broken.*

**Status:** research + architecture plan. **Target OS:** macOS 13 Ventura →
macOS 26 Tahoe, with explicit handling of legacy mechanisms that linger on
upgraded Macs. **Founding pain point:** at login a Mac fires off a crowd of
helpers, and when one fails it throws a useless dialog like *"Could not open
file"* that names nothing. macOS scatters startup items across a dozen opaque
locations with no clear line back to a recognizable application. BootCaptain's
job is to make that legible and controllable.

> **A note on confidence.** This plan is built from a verified research pass
> (primary sources: Apple developer docs and man pages, the Apple Platform
> Security guide, Howard Oakley/eclecticlight.co, Objective-See, Csaba
> Fitzl/theevilbit, Der Flounder/Rich Trouton, and the osquery schema). Where a
> behavior is Apple-documented it is treated as stable; where it relies on
> undocumented tools (`sfltool`), private stores (the BTM database), or
> unstable output (`launchctl print`), that is called out. A consolidated list
> of things that still need confirmation on real 13/14/15/26 hardware is in
> [§12](#12-open-questions--must-verify-on-hardware).

---

## Table of contents

1. [Why this is hard](#1-why-this-is-hard)
2. [Where macOS stores things that launch at startup/login](#2-where-macos-stores-things-that-launch-at-startuplogin)
3. [Exhaustive collection strategy](#3-exhaustive-collection-strategy)
4. [System vs. third-party: telling needed from unneeded](#4-system-vs-third-party-telling-needed-from-unneeded)
5. [Attribution: associating an item with a recognizable app](#5-attribution-associating-an-item-with-a-recognizable-app)
6. [Safe disabling and the privilege model](#6-safe-disabling-and-the-privilege-model)
7. [Diagnosing startup failures — the founding feature](#7-diagnosing-startup-failures--the-founding-feature)
8. [Out-of-the-box ideas, honestly rated](#8-out-of-the-box-ideas-honestly-rated)
9. [Prior art and where BootCaptain fits](#9-prior-art-and-where-bootcaptain-fits)
10. [Proposed architecture](#10-proposed-architecture)
11. [Phased roadmap](#11-phased-roadmap)
12. [Open questions — must verify on hardware](#12-open-questions--must-verify-on-hardware)
13. [Sources](#13-sources)

---

## 1. Why this is hard

Three structural facts make macOS startup items uniquely opaque, and each one
is a design constraint for BootCaptain:

1. **There is no single list.** "Runs at login" is spread across launchd
   (four+ directories × three domains), the Ventura Background Task Management
   database, and a long tail of legacy and plugin-host mechanisms (cron,
   periodic, login hooks, audio plugins, Finder Sync extensions, config
   profiles…). Apple's own System Settings pane shows only the subset that
   Background Task Management knows about.
2. **The system is silent about failures.** launchd is a daemon; it never draws
   UI. When a job's executable is missing it writes one line to the unified log
   and moves on. The scary dialogs users actually see are drawn by *the launched
   program itself* (an updater, a Java stub, an AppleScript applet) — which is
   exactly why the text is generic and unattributed.
3. **Items don't announce who they belong to.** A file called
   `com.foo.helperd.plist` running `/bin/bash` gives the user nothing. The
   signals that *do* identify a vendor (code-signing Team ID, package receipts,
   the Ventura `AssociatedBundleIdentifiers` key, Apple's own attribution table)
   have to be actively gathered and cross-checked.

BootCaptain therefore has to (a) enumerate every mechanism and reconcile
on-disk state against live state, (b) resolve identity from multiple
independent signals, (c) disable through the mechanisms macOS actually honors
while never touching what would break the machine, and (d) reconstruct the
failure story from logs and crash reports because the OS won't hand it over.

---

## 2. Where macOS stores things that launch at startup/login

### 2.1 launchd — the core (LaunchAgents & LaunchDaemons)

`launchd` (PID 1) is the primary startup mechanism. Jobs are property lists
(XML or binary) in these directories:

| Path | Domain | Owner | Writable | Notes |
|---|---|---|---|---|
| `/System/Library/LaunchDaemons` | system | Apple | No (sealed SSV) | Hundreds of Apple daemons; read-only even to root. |
| `/System/Library/LaunchAgents` | per-user (gui) | Apple | No (sealed SSV) | Apple per-user agents, loaded at every login. |
| `/Library/LaunchDaemons` | system | third-party | root | The standard third-party daemon location. Must be `root:wheel`, not world-writable, or launchd refuses it. |
| `/Library/LaunchAgents` | per-user | third-party | root | Loaded into **every** user's session at login. |
| `~/Library/LaunchAgents` | that user | user | user | Per-user agents; folder often absent on a fresh account. |
| `/Library/Apple/System/Library/Launch{Daemons,Agents}` | system / per-user | Apple | No (SIP-restricted) | Apple software updated outside the SSV — e.g. XProtect Remediator, Rosetta's `oahd`. Readable, not modifiable. |
| `<App>.app/Contents/Library/Launch{Daemons,Agents}/*.plist` | via SMAppService | third-party | (bundle) | **Ventura+**: SMAppService-registered items live *inside the app bundle* and never appear under `/Library`. Must be found via BTM or by scanning app bundles. |
| `<App>.app/Contents/Library/LoginItems/*.app` | gui | third-party | (bundle) | Legacy `SMLoginItemSetEnabled` helper apps. |
| `/Library/PrivilegedHelperTools/<label>` + generated `/Library/LaunchDaemons/<label>.plist` | system | third-party | root | Legacy `SMJobBless` privileged helpers; common on real systems, orphans are prime cleanup targets. |

Jobs can also be bootstrapped from **arbitrary paths** (`launchctl bootstrap`
accepts any path), so a loaded job whose origin plist is outside the canonical
directories is a signal worth surfacing.

**Domains and timing:** `system` (boot, runs as root), `user/<uid>` (background
agents, present for any session including SSH), `gui/<uid>` (the GUI login
session — where `LaunchAgents` load). `pid/<pid>` hosts embedded XPC services
and is *not* a startup surface. "Runs at login" for an agent means it is
bootstrapped into `gui/<uid>` at login and started then if configured to.

**The classification core — does it actually run at startup?** The plist keys
determine this, and BootCaptain must present the difference:

- **Auto-runs at boot/login:** `RunAtLoad == true`, or `KeepAlive == true`, or
  `KeepAlive` dict with `SuccessfulExit` (which itself implies RunAtLoad). Other
  `KeepAlive` conditions (`Crashed`, `PathState`, `OtherJobEnabled`) are
  restart-on-condition rules and do **not** by themselves imply a load-time
  launch — classify them by whether `RunAtLoad`/`SuccessfulExit` is also set.
- **Scheduled:** `StartInterval` / `StartCalendarInterval`.
- **Event-triggered:** `WatchPaths`, `QueueDirectories`, `StartOnMount`,
  `LaunchEvents`.
- **On-demand only:** `MachServices` / `Sockets` and none of the above — the
  job is *registered* at boot but **no process runs** until a client asks for
  it. Disabling these breaks app features rather than saving boot time; they
  should be down-ranked as disable candidates and clearly labeled.

Other keys BootCaptain reads: `Label` (the primary key — jobs are keyed by the
`Label` inside the file, *not* the filename), `Program`/`ProgramArguments`,
`BundleProgram` (bundle-relative, SMAppService), `AssociatedBundleIdentifiers`
(Ventura+, attribution), `LimitLoadToSessionType`, `Disabled` (a *default* only
— the override database wins), and the standard-out/error paths (useful UI
info). Unknown keys are silently ignored by launchd.

### 2.2 Background Task Management — the Ventura 13 watershed

macOS 13 unified all third-party persistence (login items, launchd
agents/daemons, embedded helpers) under **Background Task Management (BTM)**,
surfaced in **System Settings › General › Login Items** (renamed **Login Items
& Extensions** in macOS 15, unchanged in 26).

- **Daemon:** `backgroundtaskmanagementd`, inside
  `/System/Library/PrivateFrameworks/BackgroundTaskManagement.framework`
  (there is a `backgroundtaskmanagementd(8)` man page; note the common claim
  that it lives in `/usr/libexec` is wrong for 13+). A per-user
  `BackgroundTaskManagementAgent` posts the "Login Items Added" notifications.
- **Database:** `/private/var/db/com.apple.backgroundtaskmanagement/BackgroundItems-v<N>.btm`
  (root-only). It is an **NSKeyedArchiver binary plist, not SQLite**. The schema
  version churns aggressively across releases — **v4** (13.0), **v7** (13.1),
  **v8** (Sonoma 14), **v13** (Sequoia 15.2), **v16** (Tahoe 26, early 2026).
  **Never hard-code the version — glob `BackgroundItems-v*.btm` and take the
  newest**, exactly as Objective-See's open-source **DumpBTM** parser does.
- **Record fields** (per DumpBTM's reverse-engineered schema): `uuid`, `name`,
  `developerName` (from the signing certificate), `teamIdentifier`, `type`,
  `disposition`, `identifier`, `url`, `executablePath`, `bundleIdentifier`,
  `associatedBundleIdentifiers`, `container`/parent, `embeddedItems`, `bookmark`
  (for login items), `lightweightRequirement`. Type is a bit-flag: app `0x2`,
  login item `0x4`, agent `0x8`, daemon `0x10`, developer-grouping `0x20`,
  legacy `0x10000`, curated `0x80000`. **Disposition** is a bitmask: enabled
  `0x1`, allowed `0x2`, hidden `0x4`, notified `0x8`. A subtle but important
  point: disabling in System Settings may clear the **allowed** bit rather than
  the **enabled** bit, so BootCaptain must compute "will it run" as
  **enabled AND allowed**, not from one bit.
- **Reading it:** `sudo sfltool dumpbtm` (root; likely Full Disk Access too for
  the store directory) dumps it as undocumented text; parsing the archive
  directly (DumpBTM approach) is more robust. `sfltool` has no man page and its
  output format drifts between releases — parse defensively.
- **Managed items:** the BTM `Storage` object carries `mdmPayloadsByIdentifier`,
  so an MDM `com.apple.servicemanagement` rule that force-enables and user-locks
  an item ("managed by your organization") is readable straight from the DB.
- **Eventual consistency:** the BTM/System Settings list is not updated
  synchronously — changes may not surface until a Service Management maintenance
  pass runs (reported as "overnight"), so the Settings view can lag on-disk and
  launchd truth by **up to a day**. BootCaptain must treat BTM/Settings state as
  eventually-consistent (see §6.3), never as an immediate confirmation that an
  action "took."

### 2.3 loginwindow "reopen windows" — the great confuser

Apps can relaunch at login **without being login items at all**, via the
"Reopen windows when logging back in" checkbox (Transparent App Lifecycle):

- List: `~/Library/Preferences/ByHost/com.apple.loginwindow.<HardwareUUID>.plist`,
  key `TALAppsToRelaunchAtLogin` (array of dicts with `BundleID`, `Path`,
  `Hide`, `BackgroundState`). Read with `defaults -currentHost read
  com.apple.loginwindow TALAppsToRelaunchAtLogin`.
- Per-app window state: `~/Library/Saved Application State/<bundle-id>.savedState/`.

This is the classic source of *"why does X launch at login when it's not in
Login Items?"* — BootCaptain should surface it as a distinct "reopened windows"
category with one-click clear.

### 2.4 The legacy & obscure long tail (the completeness census)

To honestly claim "we show you everything," BootCaptain must census these too.
Alive-on-current-macOS status and disable method per mechanism:

| Mechanism | Path(s) | Alive now? | Enumerate | Disable |
|---|---|---|---|---|
| StartupItems (SystemStarter) | `/Library/StartupItems/` | **Dead** — SystemStarter removed in 10.10 | `ls` | delete folder (inert cruft) |
| `/etc/rc.*`, `/etc/launchd.conf` | `/etc/…` | **Dead** since 10.10 | read files | remove (inert) |
| cron | `/usr/lib/cron/tabs/<user>` | **Alive** (deprecated) | `crontab -l`, `sudo ls /usr/lib/cron/tabs/` | comment lines, rewrite via `crontab` |
| at / atrun | `/var/at/jobs/` | Alive but **off by default** | `atq` | `atrm`; keep atrun disabled |
| periodic | `/etc/periodic/{daily,weekly,monthly}/`, `/usr/local/etc/periodic/` | **Alive** | `ls`, `cat /etc/periodic.conf` | remove dropped script |
| Login/Logout hooks | `com.apple.loginwindow` `LoginHook` | **Zombie** — fires ≤13, not on 14+ | `sudo defaults read com.apple.loginwindow LoginHook` | `sudo defaults delete …` |
| emond | `/etc/emond.d/rules/*.plist` | **Removed in 13.0** | `ls` | remove (inert; red flag if present) |
| Kernel extensions | `/Library/Extensions/` | Alive, heavily gated | `kmutil showloaded` | remove + rebuild collection; revoke approval |
| System Extensions (Network/Endpoint Security/DriverKit) | `<App>/Contents/Library/SystemExtensions/`, staged in `/Library/SystemExtensions/` | **Alive — the modern kext** | `systemextensionsctl list` | app-initiated deactivation / delete app; `systemextensionsctl uninstall` needs **SIP disabled** |
| Audio HAL plugins | `/Library/Audio/Plug-Ins/HAL/*.driver` | **Alive** — loaded by `coreaudiod` at boot | `ls` | remove `.driver`, `killall coreaudiod` |
| Authorization plugins | `/Library/Security/SecurityAgentPlugins/*.bundle` | **Alive** — run at login window via `system.login.console` | `security authorizationdb read system.login.console` | rewrite rule + remove bundle (lockout risk) |
| Finder Sync / File Provider / Widget extensions | inside app bundles (`pluginkit`) | **Alive** — run ~login | `pluginkit -mAvvv` | `pluginkit -e ignore -i <id>`, System Settings |
| Dock tile plugins | `NSDockTilePlugIn` in a Docked app | Alive (obscure) | scan Dock apps' Info.plist | remove plugin / remove from Dock |
| Configuration profiles / MDM | `/var/db/ConfigurationProfiles/` | **Alive** | `sudo profiles show -type configuration` | `sudo profiles remove -identifier <id>` (removable only) |
| Cryptex-provided launchd jobs (Apple) | `/System/Cryptexes/`, `/System/Volumes/Preboot/Cryptexes/` | Alive (Apple only) | enumerate **live** launchd domain, not just folders | N/A |
| Shell rc files | `/etc/zshenv`, `~/.zshenv`, `~/.zprofile`, `~/.zshrc`, bash equivalents, `~/.ssh/rc` | Alive — **shell start, not GUI login** | read files | edit files (advanced view) |
| DYLD insertion / `launchctl setenv` | launchd job env, `DYLD_INSERT_LIBRARIES` | Alive but constrained (dyld strips for hardened/SIP) | inspect job env | remove the setting/launch item |

Two design implications fall out of this table. First, **enumerate the live
launchd domain, not just directories** (`launchctl print system` + BTM) —
otherwise cryptex- and profile-injected jobs are invisible and the
exhaustiveness claim is false. Second, **tier the UI by "does it actually run
at login"**: shell rc, PATH helpers, PAM, and on-demand plugin hosts belong in
an advanced/forensic view clearly labeled *when* they run, not in the core
list.

---

## 3. Exhaustive collection strategy

No single source is complete or trustworthy alone, so BootCaptain collects from
several and **reconciles**:

1. **Scan disk.** Walk every §2.1 directory plus app-bundle-embedded plists
   (`*.app/Contents/Library/{LaunchDaemons,LaunchAgents,LoginItems}`) across
   `/Applications`, `~/Applications`, Setapp, Homebrew casks, and other app
   locations. Parse each plist (`PropertyListSerialization` handles binary +
   XML). Record path, mtime, `Label`, trigger classification (§2.1), program
   path.
2. **Snapshot loaded state.** `launchctl print system` and, per logged-in user,
   `launchctl print gui/<uid>` / `user/<uid>`; `launchctl print <domain>/<label>`
   yields the origin plist `path` for each label — the reconciliation hook.
   Treat all `launchctl print` output as **unstable** (the man page says it's
   "not API") — pin parsers per OS version behind integration tests.
3. **Snapshot BTM.** Parse `BackgroundItems-v*.btm` (DumpBTM-style) or fall back
   to `sudo sfltool dumpbtm` text. This is the closest thing macOS ships to
   BootCaptain's own data model and the only source that includes
   SMAppService-in-bundle items.
4. **Snapshot disabled state.** `launchctl print-disabled` per domain, plus the
   override plists `/private/var/db/com.apple.xpc.launchd/disabled.plist` and
   `disabled.<uid>.plist`.
5. **Census the long tail** (§2.4): cron, periodic, at, system extensions
   (`systemextensionsctl list`), audio HAL, authorization plugins, `pluginkit`,
   dock tiles, config profiles, loginwindow relaunch list.
6. **Diff and reconcile.** on-disk + loaded = normal; on-disk + not loaded =
   disabled/malformed/wrong-session; loaded + not in canonical dirs = surfaced
   prominently (dev tooling or something worth a look); override entry with no
   plist = stale override to offer for cleanup; BTM record whose file is gone =
   ghost item.

**Supported read shortcuts.** `SMAppService.statusForLegacyPlist(at:)` (13+)
returns the enable/registration status for a given legacy plist path and —
confirmed by community tooling that sweeps `/Library/LaunchDaemons` and
`/Library/LaunchAgents` — answers for arbitrary third-party plists, not just
the caller's own. It is the one **supported** per-item BTM read. But treat it as
a *cross-check, not ground truth*: it reportedly regressed in the Sonoma 14.5
betas and has since returned `.notFound` even for installed, running services
(see §12). **`launchctl print-disabled` (plus the BTM parse) is the source of
truth for enable/disable state**; use `statusForLegacyPlist` to corroborate and
to catch registration nuances the launchd layer doesn't express, and never
center status logic on it alone.

---

## 4. System vs. third-party: telling needed from unneeded

Users must never be nudged toward disabling something that bricks their Mac.
BootCaptain classifies every item with **three independent signals** and
requires agreement before applying the "macOS system" badge:

1. **Signature / platform binary.** `kSecCodeInfoPlatformIdentifier` present and
   nonzero (via `SecCodeCopySigningInformation`) means an OS-shipped platform
   binary. Corroborate with the requirement check
   `SecRequirementCreateWithString("anchor apple", …)` — this passes **only** for
   Apple OS software (as opposed to `"anchor apple generic"`, which also passes
   App Store and Developer ID).
2. **Location.** A plist on the sealed Signed System Volume (`/System/Library/…`)
   shipped with the OS and cannot have been modified. Caveat: Apple also
   installs under `/Library/Apple/System/Library/…` (XProtect Remediator,
   Rosetta) and inside cryptexes — so "not under /System" ≠ third-party.
3. **Label prefix `com.apple.*`.** Necessary-looking but **spoofable and never
   sufficient**. A `com.apple.*` label whose executable is not Apple-signed is a
   high-priority red flag (classic adware pattern).

**Rule:** *Apple system* = passes `anchor apple` (or platform identifier) **and**
lives on the SSV or under `/Library/Apple`. Everything else is third-party,
graded on a trust ladder (broken signature → ad-hoc → unsigned → Developer ID
unnotarized → Developer ID notarized → App Store → Apple platform).

Apple-system rows are **read-only by default** in the UI (behind a "show system
items" toggle) for two reasons: safety, and because `launchctl` overrides on
SIP-protected services frequently don't stick anyway. This mirrors Apple's own
System Settings, which refuses to deregister system items.

**The interpreter trap.** Items whose `Program` is `/bin/bash`,
`/usr/bin/python3`, or `/usr/bin/osascript` carry Apple's signature on the
*interpreter*, not the payload — System Settings itself mislabels these as
"unidentified developer." BootCaptain must classify "Apple-signed interpreter +
third-party script argument" as its own category and attribute trust from the
script in `ProgramArguments`, because it is a favorite adware shape.

---

## 5. Attribution: associating an item with a recognizable app

This is the "show me it belongs to Dropbox" promise. Resolve identity through an
ordered pipeline, stopping at the first high-confidence hit:

1. **Inside/points into an installed `.app`** → that bundle (high). Walk parents
   to the outermost `.app`, then `Bundle(url:)` for name and icon.
2. **BTM record** — `developerName` + `teamIdentifier` + `associatedBundleIdentifiers`
   (high; the developer name persists even after the app is deleted).
3. **`AssociatedBundleIdentifiers`** in the plist, **Team-ID-verified** against
   the target app (high). The system honors this key only when the item's
   signing Team ID matches the referenced app's — so BootCaptain must replicate
   that cross-check rather than trust a self-declared claim.
4. **Code signature Team ID** → vendor via the leaf certificate organization
   (`SecCodeCopySigningInformation` / `codesign -dv --verbose=4`). **Team ID is
   the primary grouping key** — cryptographically bound, survives renames,
   shared across a vendor's app + agents + daemons + helpers.
5. **Apple's own attribution table** — `/System/Library/PrivateFrameworks/
   BackgroundTaskManagement.framework/Versions/A/Resources/attributions.plist`
   (~4,000 entries mapping helper executables/labels to products and Team IDs).
   This is the same data System Settings uses to pretty-name items — a **free,
   local catalog seed** (parse read-only; it's a private-framework resource, so
   bundle a snapshot as fallback).
6. **Package receipt** — `pkgutil --file-info <plist path>` returns the receipt
   package ID that installed the exact file, yielding vendor attribution even
   for unsigned binaries or deleted apps.
7. **Curated catalog** keyed by (Team ID, label-prefix) — adds plain-language
   descriptions and safe-to-disable ratings on top of identity.
8. **Label reverse-DNS prefix** — display only as a hint, never as ground truth.
9. **Nothing** → "Unknown item from `<Developer Name>`", amber, show the raw
   facts honestly.

**Display.** Names and icons come from
`NSWorkspace.shared.urlsForApplications(withBundleIdentifier:)` (macOS 12+,
returns all copies — flags the ran-from-DMG duplicate), `Bundle`'s
`localizedInfoDictionary`, and `NSWorkspace.shared.icon(forFile:)`, with
`mdfind "kMDItemCFBundleIdentifier == '…'"` as stale-LaunchServices insurance.
When the owning app is gone, fall back through BTM's captured developer name →
`attributions.plist` → leftover-binary signature → pkg receipt → catalog →
generic icon + explicit **orphaned** badge.

**Curated catalog.** Ship a signed, updatable data file (keyed by Team ID +
label-prefix regex): vendor, product, one-sentence purpose, category
(updater/sync/backup/VPN/security/peripheral/menu-bar/telemetry),
safe-to-disable rating, and a consequence sentence ("stops automatic Chrome
updates"). Seed identity from `attributions.plist` and the well-known helper
labels (`com.google.keystone.*`, `com.microsoft.update.agent`,
`com.adobe.ARMDC.*`, `com.docker.vmnetd`, …); layer BootCaptain's plain-language
explanations on top. This is the descriptive layer no free tool provides today.

**Show WHY an item runs.** Turn plist keys into a human chip: "Starts at
login/boot" (`RunAtLoad`), "Kept running permanently" (`KeepAlive`), "Scheduled
every N minutes" (`StartInterval`), "When files change in …" (`WatchPaths`),
"On demand — only when an app asks" (`MachServices`/`Sockets`). The last one is
critical UX: on-demand items should not be presented as login-time savings.

---

## 6. Safe disabling and the privilege model

### 6.1 Per-type disable story

- **User agents (`~/Library/LaunchAgents`)** — no elevation needed:
  `launchctl disable gui/$UID/<label>` (persists in
  `/var/db/com.apple.xpc.launchd/disabled.<uid>.plist`) **+** `launchctl bootout
  gui/$UID/<label>` (stops the running instance now). Undo with `enable` +
  `bootstrap`. Agents with `LimitLoadToSessionType = Background` live in the
  `user/$UID` domain rather than `gui/$UID`, so to be thorough disable in
  **both** domains.
- **System daemons/agents (`/Library/…`)** — same verbs with `sudo` and the
  `system/` domain. `/Library/LaunchAgents` items load into *every* user's gui
  domain, so present "disable for me" (per-user override) vs "disable for
  everyone" (move the plist, root) honestly.
- **Ventura+ "Allow in the Background" (BTM) items** — **no public or reliable
  private API** to flip another app's toggle. Effective disabling of file-based
  launchd items goes through the launchd layer (above); items registered from
  inside an app bundle (SMAppService) are **System-Settings-only** →
  deep-link with `SMAppService.openSystemSettingsLoginItems()` or the URL
  `x-apple.systempreferences:com.apple.LoginItems-Settings.extension`. Never
  edit a plist inside another app's bundle — it breaks the signature and trips
  App Management TCC.
- **Classic "Open at Login" entries** — AppleScript via System Events still
  works (`tell application "System Events" to delete login item "X"`), gated by
  the Automation TCC prompt. This is the one quasi-supported mutation path for
  other apps' items.
- **System extensions** — never programmatically; `systemextensionsctl uninstall`
  requires **SIP disabled** (confirmed by Apple DTS on 15.2; the "near future"
  message has been there since 2020). Enumerate, attribute, and route users to
  app-deactivation / drag-to-Trash / the Settings pane.
- **cron** — comment out lines with a BootCaptain marker and rewrite via
  `crontab`; never `crontab -r` (destroys the whole tab). On macOS 15+ check the
  new **"Legacy Background Tasks"** toggle, which (per an Apple engineer) gates
  whether cron runs at all.

**Preferred mechanism ranking:** override DB (`disable` + `bootout`) is primary
— it's label-keyed so it survives an updater recreating the plist (the
whack-a-mole defense), reversible with one command, and survives OS updates.
"Move to quarantine" is the stronger opt-in. **Never** edit a vendor plist's
`Disabled` key in place (updaters overwrite it and the override DB supersedes it
anyway), and never delete as the default action.

### 6.2 What must never be touched

Everything under `/System/Library/Launch*` is sealed and read-only. But
`launchctl disable system/com.apple.*` **succeeds** for many Apple services
(the override DB is on the writable Data volume), and SIP only blocks runtime
ops on a *subset* — so SIP is **not** a sufficient guard. BootCaptain ships a
curated, updatable **deny-list** of critical services that it hard-refuses to
touch even in a power-user mode, including at minimum: `opendirectoryd`,
`securityd`, `trustd`, `tccd`, `WindowServer`, `loginwindow`, `logd`,
`cfprefsd`, `configd`, `powerd`, `diskarbitrationd`, `coreservicesd`,
`launchservicesd`, `mDNSResponder`, `UserEventAgent`, `fseventsd`, `watchdogd`,
`apsd`, `mobile.softwareupdated`.

### 6.3 Reversibility and recovery

- **Staged (two-phase) disable:** `bootout` first ("try without it until
  reboot"), persist `disable` only after the user confirms things still work.
  Confirm that the action took by reading the **launchd** layer
  (`launchctl print-disabled`, `launchctl print`), *not* by re-reading BTM/System
  Settings — that view is eventually-consistent (§2.2) and can lag up to a day,
  so an immediate BTM re-read will produce false "it didn't take" mismatches.
- **Rescue manifest:** write a plain-text log of every change with exact undo
  commands to a predictable path (e.g. `/Users/Shared/BootCaptain/rescue.txt`),
  so a technician in Recovery can revert without BootCaptain running.
- **Quarantine, not delete:** move plists to a timestamped folder with a JSON
  manifest (`original_path`, `sha256`, `label`, `domain`, `method`, `date`,
  attribution); archive a copy even on explicit "delete permanently."
- **Snapshots:** export/restore full enable-disable state as a JSON diff — the
  basis of the undo stack.
- **Recovery paths, worst case:** Safe Mode (boots without third-party launchd
  jobs, enough to run `launchctl enable`); Recovery OS (its `launchctl` can't
  target the installed system's domains — the working fix is deleting/editing
  `/Volumes/<Data>/private/var/db/com.apple.xpc.launchd/disabled*.plist`
  directly); `sudo sfltool resetbtm` (dump first, restart after) to rebuild
  corrupt BTM state.

**The whack-a-mole reality.** Chrome/Keystone, Dropbox, Adobe, Microsoft
AutoUpdate, Zoom, and corporate agents re-register their helpers on next
launch. Override-DB disable wins most rounds (recreated same-label plists stay
disabled). When a vendor rotates the label, tell the user plainly: *"Chrome
re-added Google Keystone under a new name. The durable fix is inside the app
itself — [open its settings]."* Maintain a small map of known items → the
vendor's own off-switch and present that as the recommended fix, with
BootCaptain's disable as the enforcement backstop.

### 6.4 Privileges, permissions, and distribution

- **Privileged helper:** the modern pattern is BootCaptain's own daemon embedded
  at `BootCaptain.app/Contents/Library/LaunchDaemons/…` (using `BundleProgram`
  + `AssociatedBundleIdentifiers` + `MachServices`), registered via
  `SMAppService.daemon(plistName:).register()` (user approves once, admin auth).
  Harden the XPC channel with `NSXPCConnection.setCodeSigningRequirement(_:)`
  pinning BootCaptain's Team ID; never trust PID-based checks.
- **TCC:** the current user's own `~/Library/LaunchAgents` needs nothing;
  `/Library` and `/System` launchd dirs are world-readable. **Full Disk Access**
  is needed for other users' agents, the BTM store, crontabs, and saved
  application state. FDA has no prompt API — deep-link to Privacy & Security and
  detect the grant by test-reading a protected file. Crucially, a LaunchDaemon
  helper is **its own** TCC-responsible process and needs its own FDA grant — so
  put TCC-protected *reads* in the app process and keep the root helper to
  non-TCC operations (`launchctl system/…`, file moves in `/Library`).
  **App Management** TCC is only triggered by modifying another app's bundle —
  design that out entirely.
- **Distribution:** Developer ID + hardened runtime + **notarization** for the
  app and every embedded executable. The full app is **infeasible on the Mac
  App Store** (the sandbox forbids root helpers, cross-domain `launchctl`, and
  `/var/db` reads); only a heavily degraded read-only viewer could pass, if at
  all. Real distribution is Developer ID direct.
- **The irony guard.** BootCaptain should default to **zero persistent
  components**: enumerate in-process, batch privileged work into one-shot
  elevations, register nothing. If a user opts into a frictionless helper,
  register it **on-demand only** (no `KeepAlive`), list it *first* in
  BootCaptain's own UI with a one-click "Uninstall helper" (`unregister()`), and
  say plainly what it owns. The "install → operate → unregister at quit"
  ephemeral pattern is viable because BTM remembers the approval across
  re-registration.

---

## 7. Diagnosing startup failures — the founding feature

This is the reason BootCaptain exists, and it is the capability **no consumer
tool offers**. The key insight: BootCaptain cannot map a dialog to an item by
intercepting the dialog — those are drawn by the failing programs themselves.
It must reconstruct the failure story from the log, launchctl, and crash
reports, then optionally match dialogs by owning **pid**.

**Who shows which dialog:**

- **launchd** — never shows UI; a missing executable produces one unified-log
  line (`Service could not initialize …` with an errno; `0x2`/ENOENT = missing
  binary).
- **BTM / orphaned login items** — silently not launched; the row lingers as a
  "ghost" in System Settings (and can re-enable itself); the blunt fix is
  `sfltool resetbtm`.
- **loginwindow + Launch Services** — the generic `The application "X" can't be
  opened.` (LS errors `-10810`, `-600`) naming the *item*, not the source.
- **AppleScript applets** — the classic *"Where is X?"* file-picker when an
  embedded alias can't resolve.
- **Apps from ejected DMGs** — path under `/Volumes/<gone>` fails silently
  (launchd) or as a bookmark-resolution failure (BTM).
- **The launched program itself** — arbitrary text ("Could not open file",
  missing-resource, license nags). **This is the majority of vague dialogs.**

**Evidence sources:**

1. **Unified log.** Shell out to `/usr/bin/log show --last boot --style ndjson`
   (parse NDJSON) with tight predicates on `com.apple.xpc.launchd` (spawn/exit/
   throttle), `com.apple.loginwindow`, `com.apple.backgroundtaskmanagement`,
   `com.apple.syspolicy`/`CoreServicesUIAgent` (Gatekeeper). Access gotchas:
   admin users can read the log, **standard users get silently empty output**
   (detect "zero entries where there must be some" as a permissions failure,
   not a healthy boot); `OSLogStore.local()` is blocked for third parties by the
   `com.apple.logging.local-store` entitlement — route standard-user installs
   through the privileged helper. Some paths are redacted `<private>` unless an
   opt-in Enable-Private-Data logging profile is installed (partial efficacy —
   "sensitive"-level values stay masked). Log text is version-fragile — ship a
   per-OS matcher table and fail soft.
2. **`launchctl print`.** The `services` block gives a one-call health sweep
   (`PID  last-exit-status  label`; negative = killed by that signal). Per-service
   `runs` (spawn count — high minutes after login = crash loop), `last exit
   code`, and `path`. **Exit 78 = EX_CONFIG** (launchd rejected the job's config
   or couldn't spawn the program — and it will **not** respawn even under
   `KeepAlive`, so "runs stuck at 1 + status 78" is its own verdict, distinct
   from a throttled crash loop). Crash loops show `Service only ran for N
   seconds. Pushing respawn out by 10 seconds.` (10s = default `ThrottleInterval`).
3. **Crash reports.** `~/Library/Logs/DiagnosticReports` (user; note the path is
   under `Logs/`) and `/Library/Logs/DiagnosticReports` (admin-readable, so the
   app process can read it without the root helper). Since Monterey
   these are `.ips` files = **two concatenated JSON documents** (split on the
   first newline). Join `procPath` / `parentPid == 1` / `captureTime` to
   enumerated items; the `termination` namespace gives the plain-English reason
   (`DYLD` carries "Library not loaded: /path/…"; `CODESIGNING` explains
   signature kills).
4. **Static per-item health checks (no logs needed):** `plutil -lint`;
   `Program`/`ProgramArguments[0]` exists and is executable; Mach-O arch vs
   Rosetta (EBADARCH); `otool -L` dyld-closure check (predicts "Library not
   loaded"); `codesign --verify`; quarantine xattr; stale `/Users/<olduser>` or
   `/Volumes/<gone>` paths; bookmark staleness via `URL(resolvingBookmarkData:…
   [.withoutUI, .withoutMounting])`.

**The flagship: a first-run "boot audit."** On first launch after login, run
the log queries over `--last boot`, join with `launchctl print` counters and
crash reports, and annotate **every enumerated item** with: *launched OK (pid,
time) / failed (reason: missing binary, crash SIGSEGV, code-signing kill,
config-rejected EX_CONFIG, throttled crash loop) / never attempted (disabled,
session-gated)*. This directly answers "which of these threw that error at
login," which is the whole point.

---

## 8. Out-of-the-box ideas, honestly rated

- **First-run boot audit** *(feasible — flagship).* Described in §7. All inputs
  are readable; the joins are BootCaptain's; only log-string matching is
  fragile.
- **Dialog attribution via Accessibility** *(feasible-hacky — the only real
  path).* Poll the AX tree for dialog-ish windows, read the text, and — the key
  move — take the **owning pid** and walk pid → `procPath` → item. The pid, not
  the text, is the attribution. Needs Accessibility TCC; the monitor is itself a
  login item with no ordering guarantee, so coverage is best-effort. Prefer AX
  over screenshots (which need Screen Recording and, on Sequoia, periodic
  re-consent).
- **Exec-ability probe** *(feasible-hacky).* `posix_spawn` with
  `POSIX_SPAWN_START_SUSPENDED` then `SIGKILL` before resume — validates
  existence, architecture, and exec-time code-signing without running user code.
  True "dry-run replay" of items is **not feasible safely** (launching runs
  arbitrary side effects).
- **Per-item login-time impact** *(estimate only — say so).* No public per-item
  accounting exists. Heuristics: spawn-timestamp timeline from launchd/
  RunningBoard log entries; `proc_pid_rusage()` polling of early CPU; coarse
  before/after A-B when a user disables items. Present as "estimated impact,"
  never ground truth.
- **"What changed since last look" monitor** *(feasible in layers).* Layer 1
  (supported, zero TCC): record `NSWorkspace` launch/terminate notifications.
  Layer 2 (hacky): FSEvents/periodic `sfltool dumpbtm` diff on the launch
  folders + BTM store. Layer 3 (entitlement-gated): Endpoint Security exec/BTM
  events — perfect but needs Apple approval, a system extension, and non-MAS
  distribution; a "Pro" feature, not v1.

---

## 9. Prior art and where BootCaptain fits

The market is bifurcated. **Security/expert tools are exhaustive but don't help
normal users act safely; consumer tools are actionable but shallow and
poorly-attributed.** Nobody combines exhaustive coverage + app attribution +
plain-language explanation + safe reversible disable + failure diagnosis. That
gap is BootCaptain's slot.

| Tool | Coverage | Disable | UX | License / price |
|---|---|---|---|---|
| **System Settings › Login Items** | BTM only | toggle only (can't remove legacy/orphans) | consumer, but opaque names, no WHY, no diagnosis | built-in |
| **KnockKnock** (Objective-See) | very broad (20 categories) | none (view-only) | hacker aesthetic, no hand-holding | GPL-3.0, free |
| **EtreCheck** | broad | removes orphans/adware | diagnostic report, jargon | free + $19.99 one-time Power User |
| **LaunchControl** (soma-zone) | launchd only, deep | yes (launchctl-level; reads BTM state) | power-user IDE, best failure diagnosis | ~$16.99 one-time |
| **Lingon Pro** | launchd only | yes | friendlier editor, still assumes launchd literacy | $23.99 one-time |
| **CleanMyMac**-class | shallow | deletes files → items "come back" | consumer, upsell-heavy | ~$40/yr sub |
| **osquery / Fleet** | broad tables, **no BTM table**, `startup_items` broken on modern macOS | none | SQL/telemetry | Apache-2.0 OR GPL-2.0 |

**Lessons baked into this plan:** KnockKnock's plugin-per-source architecture is
the right completeness checklist (and its 20 categories ∪ osquery's tables ∪
Csaba Fitzl's "Beyond the good ol' LaunchAgents" taxonomy is the superset to
cover); EtreCheck proves orphan detection ("plist points at missing executable")
is high-value and understandable; LaunchControl proves the launchd-override
method is the only real third-party disable path on 13+ **and** that displaying
BTM state alongside launchd state (as it has since v2.3) is the honest pattern;
CleanMyMac's "it came back" one-star reviews prove **disable ≠ delete** and that
trust is the scarce resource — no scare-numbers, no upsell, full undo.

**Licensing:** Objective-See code is GPL-3.0 (learn from it, re-implement, don't
vendor into a proprietary app); osquery is dual Apache-2.0/GPL-2.0 (its table
specs are legally reusable under Apache with attribution); blog taxonomies are
copyrightable prose but the paths/techniques are unprotectable facts.

**Positioning statement:** *the first consumer-friendly, exhaustive startup
manager — shows everything that runs at boot/login (not just what BTM
registered), names the app/vendor behind every item in recognizable terms,
explains what it does in plain language, disables it reversibly through the
mechanisms the OS actually honors, cleans up orphans, and tells you when a
startup item is broken or slowing your login.* Suggested pricing: a free
read-only audit mode plus a one-time ~$20–30 unlock, slotting between the
expert one-time tools and the consumer subscriptions.

---

## 10. Proposed architecture

**Two-process design (forced by the permission model):**

- **BootCaptain.app** — SwiftUI, non-sandboxed, Developer ID + notarized. Owns
  all enumeration that doesn't need root, the attribution engine, the curated
  catalog, the UI, and TCC-protected reads (holds the Full Disk Access grant).
- **com.bootcaptain.helper** — a privileged daemon registered via
  `SMAppService.daemon`, on-demand (no `KeepAlive`), XPC-hardened with a
  code-signing requirement. Does only what needs root: `launchctl` against
  `system/…`, file moves in `/Library`, reading the BTM store and other users'
  agents, system-domain `launchctl print` and `log show` for standard users.
  Ephemeral by default (unregister at quit); persistent only if the user opts
  in.

**Core modules:**

1. **Collectors** — one per source (launchd dirs, BTM, launchctl live state,
   cron, periodic, system extensions, pluginkit, config profiles, loginwindow
   relaunch, …), mirroring KnockKnock's plugin decomposition. Each returns raw
   items; a reconciler (§3) merges and diffs them.
2. **Attribution engine** — the §5 pipeline: bundle walk → BTM record →
   `AssociatedBundleIdentifiers` (Team-ID-verified) → code signature → Apple's
   `attributions.plist` → pkg receipt → curated catalog → label heuristic.
   Cache by CDHash.
3. **Health/diagnosis engine** — static checks (§7.4) always; log + launchctl +
   crash-report joins (§7) for the boot audit; per-OS-version log-matcher table.
4. **Action engine** — least-destructive-first disable, staged commit, undo
   journal, quarantine with manifest, deny-list enforcement, deep-linking for
   BTM/extension items it can't touch directly.
5. **Curated catalog** — signed, updatable data file (Team ID + label-prefix →
   product, purpose, category, safe-to-disable rating, consequence text), seeded
   from `attributions.plist`.

**UI shape:** default view **grouped by vendor (Team ID) → app → items** with
real names and icons; two separate badges per item — **trust** (macOS /
Identified developer / Unknown-unsigned) and **health** (OK / failing /
orphaned); trigger chips explaining WHY it runs; disclosure showing label, plist
path, signature line, and "installed by `<pkg>` on `<date>`"; search across
name/vendor/label/bundle-ID/path; filters (third-party only, orphans,
launches-at-login only). Every action is previewed, journaled, and undoable.

---

## 11. Phased roadmap

- **Phase 0 — Hardware truth-pass.** Stand up 13/14/15/26 VMs and resolve the
  §12 open questions (BTM schema per release, `statusForLegacyPlist` regression,
  launchctl/BTM coupling, log-string corpus). Everything downstream depends on
  this.
- **Phase 1 — Read-only auditor (free tier).** launchd + BTM + long-tail
  collectors, reconciliation, the attribution engine, static health checks,
  grouped read-only UI, JSON/text export. No mutations. Ships value immediately
  and validates the enumeration against real Macs.
- **Phase 2 — Safe disable.** Privileged helper, override-DB disable + bootout
  with staged commit and undo journal, quarantine, deny-list, deep-linking for
  BTM/extension items, whack-a-mole messaging.
- **Phase 3 — Boot audit & failure diagnosis.** Unified-log/launchctl/crash
  correlation, the first-run boot audit annotating each item launched-OK /
  failed / never-attempted, orphan cleanup. This is the founding-pain-point
  feature and the headline differentiator.
- **Phase 4 — Advanced.** Dialog attribution via Accessibility; "what changed"
  monitor (Layers 1–2); estimated login-impact; curated-catalog expansion; an
  optional Endpoint-Security "Pro" monitoring tier.

---

## 12. Open questions — must verify on hardware

These are the load-bearing uncertainties, all needing confirmation on real
13/14/15/26 systems before code depends on them:

- **BTM schema per release** — exact `BackgroundItems-v<N>` numbers for every
  point release (anchors confirmed: v4=13.0, v7=13.1, v8=14, v13=15.2, v16=26),
  whether stale lower-version files coexist after upgrades, and whether DumpBTM
  parses each.
- **`launchctl disable` ↔ System Settings toggle coupling** — reported coupled
  on 13/14 but no authoritative source documents the mechanism; test both
  directions per OS, and whether BTM re-enables items disabled via `launchctl`.
- **`SMAppService.statusForLegacyPlist(at:)`** — reportedly returns `.notFound`
  for installed services since Sonoma 14.5; confirm current behavior and always
  keep the `launchctl print-disabled` fallback.
- **`sfltool dumpbtm` privileges** — root definitely; confirm whether the
  invoking process also needs Full Disk Access on Sonoma+.
- **SIP vs `launchctl disable system/com.apple.*`** — whether it's refused
  outright with SIP on or silently ignored (drives the deny-list posture); and
  the definitive per-release set of Apple services SIP blocks from bootout.
- **Log access specifics** — `/private/var/db/diagnostics` permissions on
  current macOS; re-confirm the standard-user "silently empty" failure mode on
  Sequoia+; which subsystems the Enable-Private-Data profile actually unmasks.
- **Log message corpus** — build a per-OS-build matcher table for the launchd/
  BTM/loginwindow strings (`Service could not initialize`, `Service exited with
  abnormal code: N`, `Pushing respawn out by`) via `log stream` on test VMs;
  never hard-fail on a miss.
- **Legacy cutoffs** — whether LoginHook still fires on Ventura 13 in all
  configs; whether `/etc/emond.d` survives as inert cruft on in-place upgrades;
  the macOS 15 "Legacy Background Tasks" toggle's exact scope (cron confirmed;
  periodic/at unknown).
- **Attribution details** — `AssociatedBundleIdentifiers` Team-ID enforcement
  end-to-end (matched/mismatched/unsigned); `attributions.plist` schema
  stability and the licensing of redistributing a snapshot.
- **Ephemeral helper** — on which builds `unregister()` leaves stale enabled
  entries in Login Items (reproduce before shipping the ephemeral mode).
- **MAS viability** — whether even a read-only viewer using user-granted folder
  access passes App Review (untestable without submission).

---

## 13. Sources

Primary and load-bearing references consulted (verified against live sources in
a 2026-07 pass; treat any exact log/`sfltool` string as version-fragile):

- **Apple** — `launchd.plist(5)`, `launchctl(1)`, `log(1)`,
  `backgroundtaskmanagementd(8)` man pages; ServiceManagement / `SMAppService`
  docs incl. `statusForLegacyPlist(at:)` and the "Updating your app package
  installer…" migration article; Endpoint Security docs (BTM events); Device
  Management schema (`com.apple.servicemanagement`,
  `apple/device-management` repo); Platform Security guide (SSV, SIP, cryptexes);
  "Interpreting the JSON format of a crash report"; Apple Developer Forums
  (AssociatedBundleIdentifiers Team-ID matching #713493/#717609; interpreter
  "unidentified developer" #755904; `statusForLegacyPlist` regression #750685;
  systemextensionsctl+SIP #773002/#685225; Legacy Background Tasks toggle
  #756671; log entitlement #666679; exit-status threads #133915/#133504/#726826).
- **Objective-See / Patrick Wardle** — DumpBTM (BTM store path, schema, type/
  disposition flags, FDA requirement — the reference parser); KnockKnock
  (persistence categories, GPL-3.0); BlockBlock; "Demystifying (& Bypassing)
  macOS's Background Task Management" (DEF CON 31).
- **Howard Oakley / eclecticlight.co** — "In the background: Identification"
  (Feb 2026; `BackgroundItems-v16.btm`, `attributions.plist`, log subsystem);
  "Manage Login and Background items" (Dec 2025); the 2023 Ventura BTM /
  login-items series; unified-log access model.
- **Csaba Fitzl / theevilbit** — "Beyond the good ol' LaunchAgents" persistence
  series (the fullest public taxonomy); "macOS Service Management — the
  SMAppService API."
- **Rich Trouton / Der Flounder** — `sfltool dumpbtm`/`resetbtm`, MDM managed
  login items, system-extension removal.
- **osquery** — schema (`launchd`, `launchd_overrides`, `startup_items`,
  `crontab`, `kernel_extensions`, `system_extensions`, `authorization_*`);
  LICENSE (Apache-2.0 OR GPL-2.0); issue #5564 (`startup_items` broken on
  modern macOS).
- **Prior-art vendors** — soma-zone LaunchControl (release notes: BTM-state
  display since v2.3, `fdautil`); Peter Borg Apps Lingon Pro; Etresoft
  EtreCheck; MacPaw CleanMyMac; Nektony; FreeMacSoft AppCleaner.

*Full per-dimension research notes (launchd, BTM/login-items, legacy-obscure,
attribution/UX, safe-disable, prior-art, failure-diagnosis), each with its own
key-facts, open-questions, and source lists, back this document.*
