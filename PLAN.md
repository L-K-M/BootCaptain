# BootCaptain - Research & Plan

*A consumer-friendly macOS startup manager: provide broad, versioned coverage
of the ways software starts at boot/login, explain what each item is and which
app it belongs to, disable supported items safely and reversibly, and present
useful evidence when a startup item is broken.*

**Status:** desk research + architecture plan; hardware validation is still
required. **Production target:** macOS 13 Ventura through macOS 26 Tahoe, with
explicit handling of legacy mechanisms that linger on upgraded Macs. macOS 27
Golden Gate is a preview-qualification target, not a production promise.
**Founding pain point:** at login a Mac fires off a crowd of helpers, and when
one fails it throws a useless dialog like *"Could not open
file"* that names nothing. macOS scatters startup items across a dozen opaque
locations with no clear line back to a recognizable application. BootCaptain's
job is to make that legible and controllable.

> **A note on confidence.** This plan was checked against Apple documentation,
> current man pages, open-source implementations, and reputable independent
> research. That is not the same as release-by-release validation. Private
> stores, undocumented command output, reverse-engineered behavior, and forum
> reports are observations, not contracts. Each collector must expose its
> source, parser version, permissions, timestamp, and coverage gaps. The
> load-bearing items still requiring clean-install and upgraded-hardware tests
> are in [§12](#12-open-questions-and-hardware-validation), and the evidence
> behind reviewed claims is recorded in [`EVIDENCE.md`](EVIDENCE.md).

---

## Table of contents

1. [Why this is hard](#1-why-this-is-hard)
2. [Where macOS stores things that launch at startup/login](#2-where-macos-stores-things-that-launch-at-startuplogin)
3. [Collection and reconciliation strategy](#3-collection-and-reconciliation-strategy)
4. [System vs. third-party: telling needed from unneeded](#4-system-vs-third-party-telling-needed-from-unneeded)
5. [Attribution: associating an item with a recognizable app](#5-attribution-associating-an-item-with-a-recognizable-app)
6. [Safe disabling and the privilege model](#6-safe-disabling-and-the-privilege-model)
7. [Diagnosing startup failures](#7-diagnosing-startup-failures)
8. [Out-of-the-box ideas, honestly rated](#8-out-of-the-box-ideas-honestly-rated)
9. [Prior art and where BootCaptain fits](#9-prior-art-and-where-bootcaptain-fits)
10. [Proposed architecture](#10-proposed-architecture)
11. [Phased roadmap](#11-phased-roadmap)
12. [Open questions and hardware validation](#12-open-questions-and-hardware-validation)
13. [Evidence policy and sources](#13-evidence-policy-and-sources)

---

## 1. Why this is hard

Three structural facts make macOS startup items uniquely opaque, and each one
is a design constraint for BootCaptain:

1. **There is no single list.** "Runs at login" is spread across launchd
   directories and domains, Background Task Management (BTM), classic login
   items, window restoration, managed background tasks, and legacy schedulers.
   Extensions and plugin-host mechanisms form a related but distinct forensic
   surface. System Settings intentionally presents scoped views rather than a
   complete execution graph.
2. **Historical evidence is incomplete.** launchd is not a user-interface
   process, but a launched program, interpreter, child, or OS broker can present
   an error. Unified logs are retained and redacted according to system policy,
   current launchd state is not history, and not every failure generates a crash
   report. BootCaptain can prove some failures; it cannot prove that an item was
   never attempted from an absence of evidence.
3. **Items don't announce who they belong to.** A file called
   `com.foo.helperd.plist` running `/bin/bash` gives the user nothing. The
   signals that *do* identify a vendor (code-signing Team ID, package receipts,
   the Ventura `AssociatedBundleIdentifiers` key, Apple's own attribution table)
   have to be actively gathered and cross-checked.

BootCaptain therefore has to (a) maintain a published, versioned taxonomy and
report partial coverage instead of claiming unknowable completeness, (b)
reconcile configured, authorized, loaded, running, and observed state without
collapsing them into one Boolean, (c) resolve identity from independent signals,
(d) mutate only mechanisms with a tested restore path, and (e) build a
confidence-rated failure timeline from the evidence macOS retained.

---

## 2. Where macOS stores things that launch at startup/login

### 2.1 launchd - the core (LaunchAgents & LaunchDaemons)

`launchd` (PID 1) is the primary startup mechanism. Jobs are property lists
(XML or binary) in these directories:

| Path | Domain | Owner | Writable | Notes |
| --- | --- | --- | --- | --- |
| `/System/Library/LaunchDaemons` | system | Apple | No (sealed SSV) | Hundreds of Apple daemons; read-only even to root. |
| `/System/Library/LaunchAgents` | per-user | Apple | No (sealed SSV) | Apple agent definitions considered when an applicable user/login domain is bootstrapped. |
| `/Library/LaunchDaemons` | system | third-party | root | The standard third-party daemon location. Plists must be root-owned and disallow group/world writes. |
| `/Library/LaunchAgents` | per-user | third-party | root | System-wide definitions considered for each applicable user/login domain, subject to session eligibility and overrides. |
| `~/Library/LaunchAgents` | that user | user | user | Per-user agents; folder often absent on a fresh account. |
| `/Library/Apple/System/Library/Launch{Daemons,Agents}` | system / per-user | Apple | No (SIP-restricted) | Apple software updated outside the SSV, e.g. XProtect Remediator and Rosetta's `oahd`. Readable, not modifiable. |
| `<App>.app/Contents/Library/Launch{Daemons,Agents}/*.plist` | via SMAppService | third-party | (bundle) | **Ventura+**: SMAppService registers bundled plists without copying them to `/Library`. Discover through app inventory, BTM, and live launchd evidence. |
| `<App>.app/Contents/Library/LoginItems/*.app` | gui | third-party | (bundle) | Used by modern `SMAppService.loginItem` and legacy `SMLoginItemSetEnabled` helpers. |
| `/Library/PrivilegedHelperTools/<label>` + `/Library/LaunchDaemons/<label>.plist` | system | third-party | root | Legacy, macOS 13-deprecated `SMJobBless` helpers remain common. An unmatched file is evidence to investigate, not permission to delete it. |

Jobs can also be bootstrapped from **arbitrary paths** (`launchctl bootstrap`
accepts any path), so a loaded job whose origin plist is outside the canonical
directories is a signal worth surfacing.

**Domains and timing:** `system` is the privileged domain; jobs default to root
but can specify `UserName`/`GroupName`. `user/<uid>` can exist without a GUI
login. `login/<asid>` is a concrete GUI audit session and `gui/<uid>` is its
convenient alias. GUI and user domains share namespaces but contain distinct
services. `pid/<pid>` hosts process-scoped XPC services and is not itself a
startup surface. Enumerate concrete active domains instead of assuming one
domain per visible user ([L-03](EVIDENCE.md#launchd-and-service-management)).

**The classification core: does it actually run at startup?** The plist keys
determine this, and BootCaptain must present the difference:

- **Initial speculative launch:** `RunAtLoad == true`, any `KeepAlive` value, or
  legacy `OnDemand == false`. Apple documents that `KeepAlive`, including its
  dictionary form, implicitly implies `RunAtLoad`; dictionary members describe
  when the job should remain alive or restart
  ([L-04](EVIDENCE.md#launchd-and-service-management)).
- **Scheduled:** `StartInterval` / `StartCalendarInterval`.
- **Event-triggered:** `WatchPaths`, `QueueDirectories`, `StartOnMount`,
  `LaunchEvents`.
- **On-demand only:** `MachServices` / `Sockets` and none of the above - the
  definition is registered when its applicable domain/session is bootstrapped,
  but **no process runs** until a client asks for it. Disabling these breaks app
  features rather than saving boot time; they should be down-ranked as disable
  candidates and clearly labeled.

Trigger dimensions are independent because a job can have several. "On-demand
only" is the derived fallback when no speculative, scheduled, or event trigger
applies.
Other keys BootCaptain reads: `Label` (the primary key - jobs are keyed by the
`Label` inside the file, *not* the filename), `Program`/`ProgramArguments`,
`BundleProgram` (bundle-relative, SMAppService), `AssociatedBundleIdentifiers`
  (Ventura+, attribution), `LimitLoadToSessionType`, `Disabled` (a *default* only;
  the override database wins), and the standard-out/error paths (useful UI
info). Preserve unknown keys and parser failures so a newer OS cannot silently
turn an item into a misleading partial record.

### 2.2 Background Task Management - the Ventura 13 watershed

macOS 13 introduced **Background Task Management (BTM)** as an authorization and
visibility layer for classic login items, Service Management items, and items
from managed profiles. It does **not** cover all persistence mechanisms. BTM is
surfaced in **System Settings > General > Login Items** (renamed **Login Items &
Extensions** in macOS 15).

- **Daemon:** `backgroundtaskmanagementd`, inside
  `/System/Library/PrivateFrameworks/BackgroundTaskManagement.framework`
  (there is a `backgroundtaskmanagementd(8)` man page; note the common claim
  that it lives in `/usr/libexec` is wrong for documented 13+ targets).
- **Private database:** observed releases store an NSKeyedArchiver archive named
  `BackgroundItems-v<N>.btm` below
  `/private/var/db/com.apple.backgroundtaskmanagement/`. Its path, filename,
  classes, schema, and permissions are implementation details. Discover all
  candidates as separate snapshots. Select a canonical store only through an
  OS-build-qualified rule plus coherence checks. If several remain plausible,
  preserve the ambiguity and derive no effective state or action from a merged
  view; do not select a lexically "newest" filename or hard-code an unverified
  version map.
- **Observed record fields** (per DumpBTM's reverse-engineered schema): `uuid`,
  `name`, `developerName`, `teamIdentifier`, `type`,
  `disposition`, `identifier`, `url`, `executablePath`, `bundleIdentifier`,
  `associatedBundleIdentifiers`, `container`/parent, `embeddedItems`, `bookmark`
  (for login items), `lightweightRequirement`. Type is a bit-flag: app `0x2`,
  login item `0x4`, agent `0x8`, daemon `0x10`, developer-grouping `0x20`,
  legacy `0x10000`, curated `0x80000`. Disposition bits have also been observed,
  but no Apple contract defines a stable `enabled AND allowed` "will run"
  formula. Preserve raw values with the decoder and OS version; never make a
  safety decision from a private bit alone. `developerName` is an opaque private
  display field, not validated certificate identity; keep it separate from the
  independently verified signer and show it only as a historical hint.
- **Reading it:** Apple documents `sfltool dumpbtm` for diagnostics, but not a
  stable machine-readable format. Direct archive decoding is equally private,
  not inherently more robust. Implement both as independently versioned
  adapters, probe their actual permission requirements, and report degraded
  coverage on failure ([B-01 through B-04](EVIDENCE.md#btm-login-items-and-managed-tasks)).
- **Managed items:** correlate BTM's observed management metadata with installed
  `com.apple.servicemanagement` profiles. On macOS 15+, also collect supervised
  Declarative Device Management (DDM)
  configuration `com.apple.configuration.services.background-tasks`, which can
  install scripts, executables, and launchd configurations in protected
  system-managed storage. Where management integration exposes it, collect the
  separate `services.background-task` status item. Managed rows are read-only
  and direct the user to their administrator
  ([B-06 and B-07](EVIDENCE.md#btm-login-items-and-managed-tasks)).
- **Consistency:** timestamp every source and tolerate disagreement, but do not
  invent a universal convergence deadline. Apple's 24-hour language concerns
  notification suppression, not a guarantee that BTM state converges within a
  day.

**Classic Open at Login items are a first-class source.** They can be apps,
documents, folders, volumes, or server connections, not just helper apps. The
collector must retain unresolved bookmarks as evidence and must not mount a
volume or show resolution UI merely to inspect one.

### 2.3 loginwindow "reopen windows" - the great confuser

Apps can relaunch at login **without being login items at all**, via the
"Reopen windows when logging back in" checkbox (Transparent App Lifecycle):

- List: `~/Library/Preferences/ByHost/com.apple.loginwindow.<HardwareUUID>.plist`,
  key `TALAppsToRelaunchAtLogin` (array of dicts with `BundleID`, `Path`,
  `Hide`, `BackgroundState`). Read with `defaults -currentHost read
  com.apple.loginwindow TALAppsToRelaunchAtLogin`.
- Per-app window state: `~/Library/Saved Application State/<bundle-id>.savedState/`.

This private schema is a useful, best-effort explanation for *"why does X launch
at login when it isn't a login item?"* It needs release-specific adapters and
must degrade to unknown when parsing fails. A supported remediation is the
logout/restart **Reopen windows** checkbox. An advanced action may back up and
clear the pending private snapshot, but must explain that this does not disable
future window restoration.

### 2.4 Legacy and adjacent execution surfaces

These mechanisms matter on upgraded, managed, or unusual Macs, but many do not
literally run at boot or GUI login. Each collector must label its trigger and
scope rather than mixing every executable extension into one startup list.

| Mechanism | Paths / evidence | Current treatment | Action policy |
| --- | --- | --- | --- |
| StartupItems (SystemStarter) | `/Library/StartupItems/` | Inert since SystemStarter's removal; report upgraded-system artifacts | Read-only; offer documented manual cleanup only after attribution |
| `launchd.conf` | `/etc/launchd.conf` | Documented as ignored | Read-only artifact |
| `rc` scripts | `/etc/rc.server`, `/etc/rc.cdrom`, `/etc/rc.netboot`, other `/etc/rc.*` | Some are still referenced by internal boot tasks on observed releases; verify each target OS | Read-only until fixture tests establish execution and recovery |
| cron | `/etc/crontab`, `/usr/lib/cron/tabs/<user>` | Officially supported legacy scheduler; includes `@reboot` | User tabs: qualified `crontab` round-trip; `/etc/crontab`: separate descriptor-safe parser/action; see §6.1 |
| at / atrun | `/usr/lib/cron/jobs`, root `atq`, `com.apple.atrun` state | Scheduler exists but `atrun` is disabled by default | Read-only; BootCaptain offers no job or scheduler mutation |
| periodic | configured periodic directories and `periodic.conf*` | Version-sensitive; present on 13/14 and reported removed on 15+ | Detect capability; residual files are artifacts unless another execution edge exists |
| Login/Logout hooks | system/root `com.apple.loginwindow` preferences and managed `LoginWindowScripts` payload | Deprecated behavior; exact 13/14/15/26 cutoff is unverified | Read-only until per-release execution and restore tests pass |
| emond | daemon presence and `/etc/emond.d/rules/*.plist` | Release behavior is not sufficiently documented | Read-only evidence; do not label inert solely from a version number |
| Kernel extensions | `/Library/Extensions`, loaded state, AuxKC/approval/reboot state | Active but heavily gated; installed is not the same as loaded | Route to vendor uninstaller or an explicit Apple recovery workflow |
| System extensions | bundled/staged extension, approval and active state | Network, Endpoint Security, DriverKit, camera, and audio families differ | Route to the owning app, System Settings, or MDM; do not use developer-only reset/uninstall tools |
| Audio HAL plug-ins | `/Library/Audio/Plug-Ins/HAL/*.driver`, host evidence | Host-loaded audio code | Guided vendor uninstall only; do not kill `coreaudiod` as a generic action |
| Authorization plug-ins | `/Library/Security/SecurityAgentPlugins`, authorization database | Login-window code with lockout risk | Read-only by default; never rewrite authorization rules automatically |
| App extensions | System Settings, app bundles, `pluginkit` diagnostic output | Installed, selected, and executing are different states | Guide to System Settings/owning app; never delete nested signed code or rely on debug elections |
| Dock tile plug-ins | `NSDockTilePlugIn` in Dock applications | Host-triggered, not necessarily login execution | Remove the app from the Dock or use vendor guidance; never alter its signed bundle |
| Profiles and managed login-item rules | installed profile metadata, BTM, `profiles` diagnostics | Organization-owned policy | Read-only; direct the user to an administrator |
| DDM background tasks (15+) | live launchd evidence and `services.background-task` status where available | Protected managed executables/scripts/launchd jobs | Read-only; direct the user to an administrator |
| Cryptex launchd jobs | live launchd evidence and cryptex paths | Apple system content | Read-only |
| Shell / SSH / PAM startup | shell rc files, `/etc/ssh/sshrc`, `~/.ssh/rc`, forced commands, PAM configuration | Triggered by shell, SSH, or authentication, not GUI login | Advanced forensic view; no generic mutation |
| Persistent environment sources | launchd `EnvironmentVariables`, `launchctl config ... path`, source job/script | An environment value is behavior, not persistence by itself | Act on the owning source; `launchctl setenv` alone is not persistent across restarts |

The product has two explicit boundaries. **Core startup/background** covers
launchd, SMAppService, BTM, classic login items, window restoration, managed
background tasks, cron/at, and release-supported periodic jobs. **Advanced
execution surfaces** covers extensions, plug-ins, shell/SSH/PAM, Folder Actions,
Quick Look/Spotlight importers, SSO components, browser add-ons, and other
host-triggered mechanisms. The product promise is coverage of the published
taxonomy for the detected OS build, accompanied by a visible coverage report.

---

## 3. Collection and reconciliation strategy

No single source is complete or trustworthy alone, so BootCaptain collects from
several, preserves provenance, and **reconciles without inventing certainty**:

1. **Inventory files and applications.** Walk the canonical §2.1 directories.
   Discover applications through Launch Services/Spotlight, mounted volumes,
   BTM URLs, and live launchd origins instead of assuming a fixed list of app
   folders. Inspect embedded LaunchAgents, LaunchDaemons, and LoginItems. Record
   file identity, ownership/mode, mtime, raw plist, parse errors, label, program,
   and all trigger dimensions.
2. **Snapshot every observable launchd domain.** Query `system`, all active
   `user/<uid>` domains, and concrete `login/<asid>` domains. `launchctl print`
   is explicitly **not API**; keep it behind build-tested diagnostic adapters,
   make every field (including origin path) optional, and expose parser failure
   rather than treating a missing field as a missing job.
3. **Collect BTM and classic login items.** Independently adapt `sfltool dumpbtm`
   and the private archive, collect app/user/login-item records including
   non-app bookmarks, and scan embedded Service Management content. No one
   source is exclusive or authoritative.
4. **Collect state as separate axes.** Use `launchctl print-disabled` per domain
   for the documented launchd override view. Treat direct override files as
   versioned, read-only forensic artifacts; `launchctl` warns that its external
   state must not be manipulated directly. Retain BTM authorization,
   registration, loaded state, process state, and observation history
   independently.
5. **Collect managed state.** Correlate configuration profiles, managed
   ServiceManagement rules, and macOS 15+ DDM background tasks/status. Live-only
   managed jobs are valid even if protected source files cannot be read.
6. **Run core and advanced collectors.** Apply the §2.4 OS capability matrix and
   record skipped collectors, denied permissions, unsupported schemas, and
   unknown types/bits as first-class coverage results.
7. **Reconcile cautiously.** Disk-only, live-only, or BTM-only records each have
   several legitimate explanations. Produce candidate explanations, not cleanup
   verdicts. Recheck mounted volumes, active domains, parser coverage, current
   signatures, and a later scan before calling an item orphaned. Never offer
   deletion solely because a BTM record, override, or source path is unmatched.

The state model therefore has at least: **configured source**, **registration**,
**user/management authorization**, **launchd override per domain**, **loaded**,
**running**, and **historical observation**. The UI may summarize them, but the
action engine must consume the individual facts and their provenance.

**Supported read shortcut, narrow contract.** Apple documents
`SMAppService.statusForLegacyPlist(at:)` for an app checking a legacy helper
from its earlier releases. Cross-app queries are useful observed behavior, not
a supported inventory contract. Use them only as an optional signal and treat
`.notFound` as unresolved. There is deliberately no single "source of truth"
for all state axes.

---

## 4. System vs. third-party: telling needed from unneeded

Users must never be nudged toward disabling something that bricks their Mac.
Classification starts by building the launch recipe and validating every
resolved executable architecture with `SecStaticCodeCheckValidityWithErrors`
and the applicable explicit requirement. Collect signer, identifier, Team ID,
platform status, and CDHash per slice; cross-slice identity disagreement is a
conflict that fails closed. `SecCodeCopySigningInformation` returns metadata and
can return partial information for invalid code; it is not itself a validity
check ([S-01 and S-02](EVIDENCE.md#trust-attribution-and-privileged-actions)).

After validation, BootCaptain combines independent signals:

1. **Signature.** `anchor apple` identifies valid Apple-signed code.
   `kSecCodeInfoPlatformIdentifier` is corroborating metadata indicating code
   signed as part of an OS release, not a substitute for validity checking.
   `anchor apple generic` also covers non-OS Apple distribution chains and must
   not be used as an "Apple system" test.
2. **Protected location.** A source/executable on the sealed Signed System
   Volume, in a cryptex, or in an Apple-controlled `/Library/Apple` location is
   strong system provenance. Location alone does not prove the target reached
   through an interpreter or symlink.
3. **Management.** An organization-managed source is neither Apple system code
   nor user-owned software. It gets a distinct read-only classification.
4. **Label.** `com.apple.*` is spoofable and never sufficient. A conflicting
   label, signature, or location produces an unknown/red-flag result rather
   than choosing whichever signal looks friendliest.

**Safety rule:** BootCaptain never mutates Apple platform/system items or
organization-managed items. This is independent of whether SIP happens to
reject a particular `launchctl` operation. Other code is graded by validated
signature type and contextual Gatekeeper assessment; "notarized" and "safe to
disable" are different questions.

**The interpreter trap.** Items whose `Program` is `/bin/bash`,
`/usr/bin/python3`, or `/usr/bin/osascript` carry Apple's signature on the
*interpreter*, not the payload. System Settings may display these as
"unidentified developer." BootCaptain must classify "Apple-signed interpreter +
third-party script argument" as its own category and attribute trust from the
script in `ProgramArguments`, because it is a favorite adware shape.

**Build the launch recipe before applying that rule.** When `Program` exists it
is the executable and `ProgramArguments` remains argv; do not mistake its first
element for another executable. Without `Program`, resolve
`ProgramArguments[0]` using launchd's documented `_PATH_STDPATH` behavior.
Resolve `BundleProgram` relative to the owning app. Preserve `EnableGlobbing`,
`RootDirectory`, `WorkingDirectory`, environment, shebang, `/usr/bin/env`, and
wrapper/interpreter effects. Parse only explicitly supported interpreter
grammars. Shell command strings, inline-code modes, dynamic wrappers, and
unresolved exec chains remain unknown and fail closed for mutation.

---

## 5. Attribution: associating an item with a recognizable app

This is the "show me it belongs to Dropbox" promise. Collect **all** available
signals, score vendor and product identity separately, and surface conflicts;
do not stop at the first plausible hit:

1. **Canonical bundle containment or executable target.** Walk to the outermost
   installed `.app`, record all copies, and validate the current code. This is
   strong present-day product evidence.
2. **Validated code signature.** Team ID is a strong developer-account grouping
   key, but one Team ID can ship many unrelated products and can change after an
   acquisition or transfer.
3. **BTM record and `AssociatedBundleIdentifiers`.** These are useful
   association claims. Verify referenced apps and matching valid Team IDs where
   possible; stale BTM history or a self-declared bundle ID cannot establish
   current trust.
4. **Apple's local attribution table.** Read the host's
   `/System/Library/PrivateFrameworks/BackgroundTaskManagement.framework/Versions/A/Resources/attributions.plist`
   opportunistically as
   version-dependent display evidence. Do not assume a fixed schema or count,
   and do not redistribute a snapshot without explicit licensing clearance.
5. **Package receipt.** `pkgutil --file-info <path>` means a receipt records that
   path; it does not prove that the current bytes were installed by or remain
   owned by that package.
6. **Independently curated catalog.** Team ID plus constrained label/path facts
   can add plain-language purpose and consequence text, but catalog data never
   authorizes a privileged action.
7. **Reverse-DNS label or historical developer name.** Display as a low-confidence
   hint only. Otherwise show "Unknown" and the raw evidence honestly.

**Display.** Names and icons come from
`NSWorkspace.shared.urlsForApplications(withBundleIdentifier:)` (macOS 12+,
returns all copies - flags a launched-from-DMG duplicate), `Bundle`'s
`localizedInfoDictionary`, and `NSWorkspace.shared.icon(forFile:)`, with
`mdfind "kMDItemCFBundleIdentifier == '<bundle-id>'"` as stale-LaunchServices
insurance.
When the owning app is gone, retain BTM history, the local attribution table,
leftover-binary signature, receipts, and catalog matches with individual
provenance. Use **possibly orphaned** until mounted-volume and repeated-scan
checks establish absence.

**Curated catalog.** Ship independently researched facts: vendor, product,
purpose, category, consequence text, source URL, review date, and supported OS
range. Updates need a threat model, not merely a signature: version/expiry and
rollback protection, offline root and rotatable signing keys, schema/size
limits, bounded non-backtracking matching, atomic last-known-good installation,
and a built-in immutable safety policy. Treat a TUF-compatible design as the
baseline ([C-01](EVIDENCE.md#catalog-and-project-policy)). Never seed a
distributable file by copying Apple's private resource without licensing
approval.

**Show WHY an item runs.** Turn each trigger into a chip: "Starts when loaded"
(`RunAtLoad` or implied by `KeepAlive`), "Kept running" (`KeepAlive == true`),
"Kept alive while/when ..." (`KeepAlive` dictionary), "Scheduled every N
minutes" (`StartInterval`), "When files change ..." (`WatchPaths`), and "On
demand - only when a client asks" (`MachServices`/`Sockets` without speculative
triggers). On-demand registration is not login-time process execution.

---

## 6. Safe disabling and the privilege model

### 6.1 Per-type disable story

Apply managed/SMAppService policy before generic launchd policy. A bundled or
BTM-managed item does not fall through to direct launchd mutation unless that
specific override behavior has been separately qualified and disclosed.

- **LaunchAgents.** Determine the domain in which the service is actually
  registered; never disable both `gui/<uid>` and `user/<uid>` speculatively.
  For that domain, `launchctl disable <domain>/<label>` persists the launchd
  override across boots. Record loaded/running state, exact domain/path/file
  identity, and the observed override as absent/default, explicit-enabled,
  disabled, or unknown. Unknown pre-state blocks mutation because no safe
  inverse can be established. `launchctl bootout <domain>/<label>` is a separate,
  explicit operation that unloads and can terminate current work; it is not a
  harmless part of disabling. `/Library/LaunchAgents` are still per-user
  services; there is no supported single override for every current and future
  user.
- **LaunchDaemons.** `/Library/LaunchDaemons` use the `system` domain and require
  privileged mutation. Apply the same pre-state, exact-target, separate
  disable/bootout, and journal-driven inverse rules. A system-domain job can
  still run as a non-root user specified by its plist.
- **BTM / SMAppService items owned by another app.** There is no public API for
  BootCaptain to change another app's registration or background-activity
  authorization. Use `SMAppService.openSystemSettingsLoginItems()` and explain
  the owning app's supported off-switch. Do not use an undocumented Settings
  URL or edit another signed app bundle.
- **Classic Open at Login entries.** Prefer a supported/manual System Settings
  route. If System Events automation is retained, include
  `NSAppleEventsUsageDescription` and the Apple Events entitlement, resolve by
  path rather than ambiguous display name, preview the exact record, and fall
  back to manual instructions when Automation is denied.
- **Extensions, drivers, HAL, profiles, and managed tasks.** Enumerate and
  attribute, then route to the owning app, System Settings, vendor uninstaller,
  or administrator. Do not invoke developer-only reset tools, rewrite
  authorization policy, remove managed profiles, or delete nested signed code.
- **cron.** Export with `crontab -l` for the current user or
  `crontab -u <user> -l` as root for another user, edit one parsed entry, then
  reinstall the complete tab with `crontab <file>` or
  `crontab -u <user> <file>`. Preserve comments/environment and verify a parse
  round-trip. `/etc/crontab` has a
  different format with a user field and requires its own parser and
  descriptor-safe privileged path; never pass it to `crontab` and never use
  `crontab -r`. Treat the macOS 15 Legacy Background Tasks interaction as
  observed, build-specific behavior until the matrix establishes scope.
- **at / atrun.** Read-only. Removing a queued job is destructive, recreation
  changes identity, and a deadline can elapse while it is absent, so BootCaptain
  offers no job or scheduler mutation.

There are three action classes: **supported behaviorally reversible mutation**,
**guided vendor/Settings/admin action**, and **read-only evidence**. A new mechanism does
not enter the first class until its pre-state capture, mutation, verification,
behavioral restoration, unavoidable residue, update, and interrupted-operation
cases pass on every supported OS family.

For eligible legacy launchd services, `disable` is preferred to editing the
vendor plist's `Disabled` key. `enable` restores loadability and `bootstrap`
restores a definition that BootCaptain booted out only when its source identity
still matches. launchctl exposes no supported operation to remove an override
and restore an initially absent/default record; that case is behaviorally
reversible but not exact configuration restoration and must disclose the
residue. Updater label changes and OS-upgrade behavior also require tests.
Moving a source file to a disable vault is a stronger, separately confirmed
action, not a default. Deletion is never the default
([L-06 and L-07](EVIDENCE.md#launchd-and-service-management)).

### 6.2 What must never be touched

BootCaptain hard-refuses to mutate any source or executable that is valid Apple
platform/system code, resides on the SSV or in a cryptex/Apple-controlled
system location, or is organization-managed. Unknown or conflicting provenance
also fails closed. This policy does not depend on SIP or a particular
`launchctl` error. A built-in critical-label deny-list remains useful defense in
depth, but it cannot be the primary boundary and remote catalog data cannot
weaken it.

### 6.3 Reversibility and recovery

- **Staged disable.** Preview persistent `disable` separately from optional
  `bootout`, including the consequence of terminating current work. If the user
  chooses an unload trial, provide immediate bootstrap restoration subject to
  source-identity validation. Verify the targeted launchd override/domain and
  show BTM authorization as an independent observation, not a delayed mirror.
- **Authoritative journal.** Serialize mutations under a helper-held lock. Write
  a unique immutable **prepared** record containing verified preconditions and
  idempotent undo data, then durably flush the record and directory entry before
  mutation. Reopen and verify actual state, then durably mark **committed**;
  mark **aborted** only after proving no effect, otherwise mark
  **indeterminate**. On startup, reconcile every prepared or indeterminate
  transaction against current descriptor-derived state before allowing recovery
  or undo; never blindly repeat or reverse it. Mutation,
  verification, recovery, and undo must be idempotent, and power-loss claims use
  `F_FULLFSYNC` where supported or are explicitly downgraded. Store records under
  `/Library/Application Support/BootCaptain`, owned by `root:wheel` with
  restrictive permissions; labels and paths are inert data, never commands. A
  `/Users/Shared` export is nonauthoritative
  ([S-07](EVIDENCE.md#trust-attribution-and-privileged-actions)).
- **Disable vault.** If a qualified action moves a file, use a pre-created,
  root-owned same-volume vault and an exclusive descriptor-relative rename that
  cannot overwrite an existing destination. Preserve content, ownership, mode,
  flags, ACLs, extended attributes, file identity, hash, domain, and attribution.
  Do not call this quarantine, which has a separate macOS meaning.
- **Snapshots.** Export enable/disable observations and BootCaptain changes as
  a versioned JSON diff. Restoration only replays operations BootCaptain
  journaled; it does not overwrite unrelated launchd or BTM state.
- **Recovery.** Safe Mode suppresses certain non-required startup software but
  is not a guarantee that every third-party job is absent. Restore moved files
  from the vault, then boot the installed OS/Safe Mode and replay only the exact
  inverse recorded in the journal: `enable` only for BootCaptain's `disable`,
  and `bootstrap` only for a BootCaptain `bootout` of a previously registered
  service whose source identity still matches. Never delete or edit launchd's
  private `disabled*.plist` store. `sfltool resetbtm` is a destructive, global
  expert action for test/recovery, not orphan cleanup; a dump is diagnostic
  rather than a documented restore format.

**The whack-a-mole reality.** Chrome/Keystone, Dropbox, Adobe, Microsoft
AutoUpdate, Zoom, and corporate agents re-register their helpers on next
launch. A same-domain, same-label override commonly survives plist recreation,
but that behavior is not a substitute for testing. When a vendor rotates the
label, tell the user plainly: *"Chrome
re-added Google Keystone under a new name. The durable fix is inside the app
itself - [open its settings]."* Maintain a small map of known items to the
vendor's own off-switch and present that as the recommended fix, with
BootCaptain's disable as the enforcement backstop.

### 6.4 Privileges, permissions, and distribution

- **Privileged helper layout and lifecycle.** Put the daemon plist in
  `BootCaptain.app/Contents/Library/LaunchDaemons` and the executable in an
  appropriate signed code location such as `Contents/Resources`; reference it
  with `BundleProgram`, expose a narrowly scoped Mach service, and register via
  `SMAppService.daemon(plistName:)`. Registration requests approval; check
  `status` after every attempt. Keep the no-`KeepAlive` service registered and
  let it exit when idle. Offer explicit **Uninstall helper** via `unregister()`;
  do not unregister on every app quit or depend on approval surviving
  re-registration.
- **Mutual authentication and authorization.** On every supported release,
  configure exact anchored requirements containing the expected bundle
  identifier and Team ID on both outgoing `NSXPCConnection` and incoming
  `NSXPCListener` before either side resumes or accepts messages. Team ID alone
  is too broad. Retain the immutable audit token for caller UID/audit-session
  checks and defense-in-depth validation, not as a compatibility fallback. The
  helper also checks a BootCaptain-specific Authorization Services right and
  operation scope each time; registration is not authorization for arbitrary
  future root actions.
- **No confused deputy.** The helper accepts typed operations and opaque item
  identifiers, never shell fragments, generic `launchctl` verbs, arbitrary
  source/destination paths, or log predicates. It independently reopens and
  validates each target immediately before mutation: canonical allowlisted
  root, expected label/domain, regular-file type, owner/mode/ACL/link count,
  stable device/inode, current valid signature, and unmanaged/non-Apple status.
  Refuse the operation if the caller can write any security-relevant source,
  executable, or ancestor through mode or ACL. Open fixed roots as directory
  descriptors and resolve beneath them with `openat`, no-follow/beneath flags
  where available, or an equivalent descriptor walk; `O_NOFOLLOW` on only the
  final component is insufficient. Keep descriptors open through validation,
  reject unsafe hard links and destination collisions, use exclusive
  descriptor-relative same-volume renames, bound output, and verify afterward
  ([S-03 and S-04](EVIDENCE.md#trust-attribution-and-privileged-actions)).
- **TCC and permissions.** Maintain an OS-build matrix per collector/action for
  standard/admin users, root, FDA, Automation, Accessibility, and App
  Management. Root does not imply FDA and an FDA grant does not bypass BSD
  ownership. Perform current-user TCC reads in the app where possible and keep
  the helper to demonstrated root-only operations; anyone can query the system
  launchd domain. If an operation needs both root and TCC, test which binary is
  responsible or omit the collector rather than assuming inheritance.
- **Distribution:** Developer ID + hardened runtime + **notarization** for the
  app and every embedded executable. The full app is **infeasible on the Mac
  App Store** as designed because App Review Guidelines 2.4.5 and 2.5.2 require
  sandboxing, prohibit root escalation, and constrain broad filesystem access.
  `SMAppService` itself is not categorically forbidden. A reduced read-only
  edition would still require actual App Review. Real distribution for the full
  product is Developer ID direct.
- **The irony guard.** Read-only use registers nothing. Register the on-demand
  helper only on first privileged action, show it prominently in BootCaptain's
  own inventory, explain every right it has, and provide explicit removal.

---

## 7. Diagnosing startup failures

This is the founding use case. BootCaptain builds a best-effort evidence
timeline; it does not promise a complete historical trace. A dialog may be
presented by the launched item, an interpreter/wrapper or child, or an OS broker.
Accessibility can identify the presenting process, not automatically the
startup item that caused it. Keep **Presented by** separate from **Likely
triggered by**, each with evidence and confidence.

Common hypotheses worth testing include a missing launchd executable, an
unresolved classic-login-item bookmark, an app on an unavailable volume, an
AppleScript alias prompt, a Gatekeeper/code-signing denial, a dyld failure, or
arbitrary UI from the launched program. Exact dialog text and error-number
mappings are release-specific; do not encode anecdotes as universal rules. A
lingering BTM row is registration evidence, not proof of failure, and
`sfltool resetbtm` is not routine remediation.

**Evidence sources:**

1. **Unified log.** Query a bounded boot/login interval with narrow predicates
   for launchd, loginwindow, BTM, Launch Services, and security policy. `--last
   boot` begins at boot, not the current GUI login, and can include several
   logins, fast-user switches, sleeps, and wakes. Capture command status and
   stderr; request info/debug levels when useful, while recognizing those
   records might never have been persisted. Redaction, retention, and access
   vary. Zero matches means no accessible match, not success or a reliable
   permissions test. Report query execution as succeeded/failed separately from
   historical evidence coverage, which is partial or unavailable; record the
   requested interval, accessible-store bounds, levels, loss records, redaction,
   and permissions. Log strings use build-tested matchers and fail soft.
2. **launchd diagnostics.** `launchctl print` can expose current state, origin,
   counters, and last status, but its output is explicitly not API. Report raw
   observations such as "last reported status 78" or "14 runs". Exit 78 is the
   child's conventional `EX_CONFIG`, not proof that launchd rejected the plist;
   a high run count can be legitimate demand. Call timestamped starts/exits
   "repeated execution observed." Diagnose a restart loop only when events are
   temporally linked to a configured restart condition and unexpected
   termination; reserve "crash loop" for repeated crash signals or correlated
   reports. Missing fields are unavailable, not negative history.
3. **Crash and incident reports.** Inspect user and system DiagnosticReports
   only where permissions allow. Detect the `.ips` report/`bug_type` before
   applying Apple's documented metadata-line-plus-JSON crash parser; not every
   `.ips` file has one universal shape. Process path, PID/parent, timestamp, and
   termination data are correlation signals. `parentPid == 1` can also be a
   reparented orphan, reports can be delayed/absent/redacted, and no report means
   unknown.
4. **Static risk signals.** Plist syntax, executable existence/mode, interpreter
   target, architecture slices, Rosetta availability, signature validity,
   contextual Gatekeeper assessment, quarantine metadata, direct `otool -L`
   dependencies, suspicious old-user/offline-volume paths, and no-UI/no-mount
   bookmark resolution are useful facts. They do not reproduce launchd's UID,
   domain, environment, TCC, transitive dyld closure, or runtime success. An
   offline bookmark target is not necessarily stale.
5. **Prospective observation.** Strong historical negatives require a monitor
   that was already running. An optional future monitor records its start time,
   authorization, dropped-event/gap indicators, and stop time so the UI never
   presents an incomplete interval as complete
   ([D-01 through D-06](EVIDENCE.md#diagnostics-and-observation)).

**The flagship: boot/login evidence audit.** On first launch, correlate
available evidence into the following safe states:

| State | Meaning |
| --- | --- |
| Active now | A current process or service state was observed |
| Execution observed | A timestamped launch/exec event was found; outcome is unknown |
| Exit observed | An exit status or signal was observed and shown without automatic interpretation |
| Failure evidence | A specific missing target, denied exec, crash, or qualified restart/crash loop was observed |
| Not eligible at snapshot | Current configuration is disabled or session-ineligible; no historical claim |
| Configured, not observed | The item exists but the available window contains no matching execution evidence |
| Coverage incomplete | Permissions, retention, parser support, redaction, or monitor gaps prevent a conclusion |

Only use **succeeded** when the item exposes an item-specific success signal.
This model can answer "which item has evidence matching that failure?" without
turning absence of telemetry into "never attempted."

**Privacy boundary.** Unified logs, cross-user reports, Accessibility text,
private-data logging, and Endpoint Security events can expose document paths,
identifiers, message text, and secrets. Raw evidence remains local and
short-lived, exports are redacted by default, query duration/output are bounded,
and AX/ES collection is explicit and independently revocable. Installing a
private-data logging profile is not a normal product requirement.

---

## 8. Out-of-the-box ideas, honestly rated

- **First-run evidence audit** *(feasible, best-effort flagship).* Described in
  §7. Its value comes from concrete positive evidence and transparent gaps, not
  from pretending every input is readable or complete.
- **Dialog presenter via Accessibility** *(feasible, opt-in, privacy-sensitive).*
  AX can return a window's owning PID. Map that to a presenter path; infer an
  originating startup item only when process ancestry, identity, and timing
  support it. The monitor has no ordering guarantee and may start after the
  dialog, so retain an unknown outcome.
- **Executable-image preflight** *(narrow, opt-in).* A suspended `posix_spawn`
  can test whether the kernel admits an executable in BootCaptain's context
  without running its user-space entry point. It does not reproduce launchd's
  UID/domain/environment/TCC, dyld initialization, or Launch Services and still
  creates audit/security telemetry. Run unprivileged with a timeout, `SIGKILL`,
  `waitpid`, and explicit exclusion from BootCaptain's own launch evidence.
  There is no safe general dry-run replay.
- **Per-item login-time impact** *(estimate only; say so).* No public per-item
  accounting exists. Heuristics: spawn-timestamp timeline from launchd/
  RunningBoard log entries; `proc_pid_rusage()` polling of early CPU; coarse
  before/after A-B when a user disables items. Present as "estimated impact,"
  never ground truth.
- **"What changed since last look" monitor** *(feasible in layers).* Workspace
  notifications miss background-only/agent processes. FSEvents can coalesce or
  drop events and should trigger a rescan, not serve as a ledger. Endpoint
  Security BTM ADD/REMOVE events provide registration observations when
  delivered and separate EXEC events provide execution observations; complete
  delivery is not guaranteed. It needs Apple approval, user authorization, an
  explicit privacy case, per-type/global sequence-gap recording, client
  start/stop/restart bounds, and periodic full rescans. No history exists before
  it starts.

---

## 9. Prior art and where BootCaptain fits

The product opportunity is a **market hypothesis**, not a defensible "first" or
"nobody else" claim until current products are tested against the same fixture
corpus. Vendor features and prices change, so this is a dated snapshot of the
public pages reviewed on 2026-07-26, with versions shown where established. It
must be product/version tested and refreshed before any positioning decision.

| Tool | Reviewed scope | Actions | Remaining BootCaptain hypothesis |
| --- | --- | --- | --- |
| **System Settings > Login Items & Extensions** | Open at Login items, app background activity, many extension families | Removes Open at Login records; changes supported toggles | No cross-source reconciliation, provenance view, or failure timeline |
| **KnockKnock** (Objective-See) | Broad persistence taxonomy | Primarily inspection | Security-oriented presentation rather than mechanism-specific consumer undo |
| **EtreCheck** | Broad diagnostic inventory and remediation guidance | Product-specific remediation | Report-oriented workflow rather than a live startup state model |
| **LaunchControl 2.10.4** | Deep launchd inspection/editing, bundled/non-standard jobs, override and System Settings state, logs | Rich launchd actions | Expert launchd IDE rather than a cross-mechanism consumer explanation layer |
| **Lingon / Lingon Pro 10** | Friendly scheduling plus launchd editing; login/background-item display in Pro | User tasks and launchd actions; some background rows view-only | Broader attribution, safety policy, and evidence correlation |
| **CleanMyMac-class utilities** | Consumer cleanup/background-process workflows vary by release | Product-specific cleanup/toggles | Auditable provenance, exact consequences, and a first-class undo journal |
| **osquery** | SQL inventory including modern BTM-backed `startup_items` after merged PR #8726 | Telemetry, not consumer mutation | Consumer UX, supported actions, and confidence-rated diagnosis |

**Lessons baked into this plan:** collector-per-source decomposition is the right
way to make coverage testable; orphan candidates are useful only when uncertainty
is explicit; expert launchd tools demonstrate the value of showing definition,
override, BTM, and live state separately; and durable trust requires exact
consequences, no scare score, no destructive default, and an honest account of
what can and cannot be restored exactly.

**Licensing:** Objective-See projects are GPL-3.0 and osquery offers Apache-2.0
or GPL-2.0 terms. Any proprietary implementation needs documented provenance,
license compliance, and legal review before copying code, schemas, catalogs, or
substantial prose; this plan is not a legal conclusion.

The repository itself currently uses the **Unlicense**, which permits commercial
redistribution by anyone. That does not prevent charging for builds or support,
but it conflicts with assumptions of exclusive proprietary distribution. Decide
between intentionally unrestricted, open-core/dual-license, and proprietary
development before accepting substantial contributions or finalizing pricing.

**Candidate positioning:** *a consumer-friendly startup evidence and control
center with broad, published coverage: it associates opaque items with familiar
apps, explains when and why they run, distinguishes observation from
authorization and current state, offers only tested reversible actions, and
shows concrete evidence behind startup failures.* A free read-only audit plus a
one-time paid action tier is a hypothesis to validate after the repository's
license and distribution model are decided.

---

## 10. Proposed architecture

**Two-process design (forced by the permission model):**

- **BootCaptain.app** - SwiftUI, non-sandboxed, Developer ID + notarized. Owns
  unprivileged/current-user collection, attribution, catalog, UI, evidence
  redaction, and TCC-protected reads for permissions the user explicitly grants.
  Full Disk Access is optional and collector-specific, not a blanket startup
  requirement.
- **com.bootcaptain.helper** - a demand-launched privileged daemon registered
  via `SMAppService.daemon`, with no `KeepAlive`. It implements only the typed,
  independently authorized root operations in §6.4. The Phase 1 read-only
  product does not register it: collectors that truly require root report a
  visible coverage gap. After a user enables actions, separately authorized
  root-only reads may reuse it, but it does not exist merely to query the
  readable system launchd domain and never exposes a general command runner or
  filesystem proxy.

**Core modules:**

1. **Collectors** - one per source and OS capability. Each returns raw evidence
   plus source, timestamp, collector/parser version, permissions, OS build,
   confidence, parse warnings, and coverage status. Core and advanced collectors
   remain visibly separate.
2. **Reconciler/state model** - merges identities while preserving each source's
   configured, registered, authorized, overridden, loaded, running, and observed
   axes. It emits candidate explanations and conflicts, never destructive
   conclusions from unmatched records alone.
3. **Attribution engine** - collects all §5 signals, validates every executable
   slice before reading signature metadata, and scores vendor and product
   separately. Cache only CodeDirectory-derived and sealed-component metadata
   keyed by the complete architecture/CDHash set. Hash the complete signature
   blob or avoid caching CMS envelope, certificate-chain, and signing-time
   fields. Re-evaluate code/resource validity,
   revocation/notarization, Gatekeeper policy, filesystem identity, and
   path/history evidence at the time of a safety decision
   ([S-10](EVIDENCE.md#trust-attribution-and-privileged-actions)).
4. **Evidence/diagnosis engine** - static risk signals plus bounded log,
   launchd-diagnostic, incident-report, and optional prospective-event adapters.
   Every conclusion carries evidence, confidence, observation window, and gaps.
5. **Action engine** - enforces the immutable safety policy, exact target/domain,
   action class, per-operation authorization, preview, journal, postcondition,
   and tested undo. Unsupported mechanisms become guided actions.
6. **Permission broker** - explains why each collector/action needs root or a
   TCC permission, requests it only when used, and records denied/unavailable
   coverage without nagging.
7. **Curated catalog** - independently authored, provenance-carrying data with
   the update security controls in §5. It can explain consequences but cannot
   override trust classification or authorize actions.

**UI shape:** default view grouped by resolved vendor, app, and items, without
assuming Team ID equals product. Show separate **provenance/trust**, **current
state**, and **evidence** badges; trigger chips explain when and why an item can
run. Disclosure includes every attribution source/conflict, label/domain, source
path, validated signature, and wording such as "receipt X records this path"
rather than "installed by X." A persistent coverage banner lists denied,
unsupported, failed, or not-run collectors. Every available action shows its
class, exact scope, consequence, evidence, journal location, and undo before
authorization.

---

## 11. Phased roadmap

- **Phase 0 - fixture and hardware truth-pass.** Build a golden corpus for every
  collector and action. Test clean installs and upgrades on 13/14/15/26 VMs,
  physical Apple-silicon Macs, and applicable Intel Macs; admin/standard and
  multiple/fast-switched users; managed/unmanaged devices including supervised
  DDM; SIP/FileVault/TCC/FDA states; offline volumes; and interrupted action,
  crash, power-loss, update, undo, and recovery cases. Qualify macOS 27 preview
  separately. Publish pass criteria and evidence by OS build.
- **Phase 1A - core read-only auditor and minimum evidence audit.**
  Canonical/arbitrary/managed launchd,
  app-bundled services, BTM and classic login items, window restore, cron/at,
  versioned periodic support, state reconciliation, attribution, risk signals,
  opportunistic current-login evidence correlation, coverage report, and
  redacted JSON/text export. No mutations and no helper; root-only sources show
  as unavailable.
- **Phase 1B - advanced read-only auditor.** Kext, system/app extension, HAL,
  authorization, shell/SSH/PAM, SSO, Folder Actions, Quick Look/Spotlight, and
  other published forensic collectors, each accurately trigger-labeled.
- **Phase 2 - boot/login evidence and failure diagnosis.** Confidence-rated log,
  launchd-diagnostic, incident-report, and static-signal correlation using §7's
  safe states. Add optional prospective next-login observation for stronger
  evidence.
- **Phase 3 - constrained actions.** Ship only fixture-backed, behaviorally
  reversible mechanisms with disclosed residue, the hardened helper, immutable
  safety policy, staged launchd actions, durable root-owned journal/vault,
  postcondition checks, restoration, and guided Settings/vendor/admin routes.
  No generic orphan deletion.
- **Phase 4 - opt-in advanced evidence.** Accessibility presenter attribution,
  change monitoring, estimated login impact, catalog expansion, and only then a
  separately justified Endpoint Security tier.

---

## 12. Open questions and hardware validation

These are the load-bearing uncertainties, all needing confirmation on clean and
upgraded 13/14/15/26 systems before code depends on them:

- **BTM adapters:** active private store names/classes, coexistence of old
  stores after upgrade, unknown fields/bits, `sfltool` output drift, and graceful
  behavior when neither adapter works.
- **State coupling:** both directions of launchd override, BTM authorization,
  System Settings toggle, registration, and updater re-registration for each
  item type and OS build. Do not assume one mirrors another.
- **`statusForLegacyPlist`:** own legacy helper versus arbitrary third-party
  paths, `.notFound` behavior, and whether any cross-app result remains useful.
- **Permission matrix:** `sfltool`, private BTM archive, other users' agents and
  crontabs, DiagnosticReports, unified log, App Management, and which binary is
  TCC-responsible when a helper participates.
- **Domain inventory:** user domains without GUI login, multiple login/audit
  sessions, fast user switching, LoginWindow sessions, and exact placement of
  `LimitLoadToSessionType` variants.
- **Managed sources:** what local evidence and DDM status is available to an
  unmanaged app for `services.background-task`, and how protected origins
  appear in launchd/BTM on 15+.
- **Log and report corpus:** per-build messages, fields, persistence/redaction,
  report shapes, standard/admin behavior, and test fixtures for every safe §7
  state. Never hard-fail or infer a historical negative from a miss.
- **Legacy capability cutoffs:** `rc.*`, LoginHook/LogoutHook, emond, periodic,
  cron/at, and the exact scope of Legacy Background Tasks on clean versus
  upgraded systems.
- **Attribution:** current validation behavior for associated bundle IDs,
  conflicts after app transfer/update, local `attributions.plist` schema, and
  legal approval before any redistribution or derived snapshot.
- **Helper security/lifecycle:** enforcement of exact designated requirements
  on macOS 13+, per-operation rights, approval flow, idle exit, unregister,
  stale rows, update replacement, caller attacks, path races, and interrupted
  journal/vault operations.
- **Recovery:** Safe Mode behavior for each supported action and a documented
  offline path that restores only BootCaptain-journaled changes without editing
  launchd/BTM private databases.
- **macOS 27:** rerun the complete matrix against preview builds; no production
  support until the public release passes it.
- **Distribution and licensing:** actual App Review outcome for any reduced MAS
  build, and a project decision on the current Unlicense versus a paid,
  proprietary, or dual-licensed product model.

---

## 13. Evidence policy and sources

[`EVIDENCE.md`](EVIDENCE.md) maps the load-bearing reviewed claims to sources,
confidence, and hardware work. Implementation PRs must update it with the exact
URL/man-page version, access date, relevant quotation or reproduction command,
tested OS build/hardware, result, and fixture. Source precedence is: public
Apple API/schema or current man page; Apple deployment/security guidance;
reproducible local observation/open-source implementation; independent research;
forum or vendor anecdote. Private behavior never becomes a contract through
repetition.

Key references accessed 2026-07-26:

- **launchd:** [`launchd.plist(5)`](https://keith.github.io/xcode-man-pages/launchd.plist.5.html), [`launchctl(1)`](https://keith.github.io/xcode-man-pages/launchctl.1.html), and [`backgroundtaskmanagementd(8)`](https://keith.github.io/xcode-man-pages/backgroundtaskmanagementd.8.html) from the Xcode man-page corpus.
- **Login/background management:** Apple's [deployment guide](https://support.apple.com/guide/deployment/manage-login-items-background-tasks-mac-depdca572563/web), [Login Items & Extensions user guide](https://support.apple.com/guide/mac-help/change-login-items-extension-settings-mtusr003/mac), [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice), and [helper migration guide](https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos).
- **Managed tasks:** Apple's [DDM background-task guide](https://support.apple.com/guide/deployment/background-task-management-declarative-dep931381403/web) and the open [device-management schema](https://github.com/apple/device-management/blob/release/declarative/declarations/configurations/services.background-tasks.yaml).
- **Security:** Apple's [Secure Coding Guide for helpers](https://developer.apple.com/library/archive/documentation/Security/Conceptual/SecureCodingGuide/DesigningSecureHelpers/DesigningSecureHelpers.html), [race-safe file operations](https://developer.apple.com/library/archive/documentation/Security/Conceptual/SecureCodingGuide/Articles/RaceConditions.html), [code-signing requirements](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html), [Platform Security](https://support.apple.com/guide/security/welcome/web), [Safe Mode behavior](https://support.apple.com/en-us/116946), and [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).
- **Diagnostics:** Apple's [crash-report JSON guide](https://developer.apple.com/documentation/xcode/interpreting-the-json-format-of-a-crash-report), [`log(1)`](https://keith.github.io/xcode-man-pages/log.1.html), and Endpoint Security documentation for [BTM add events](https://developer.apple.com/documentation/endpointsecurity/es_event_btm_launch_item_add_t), [exec events](https://developer.apple.com/documentation/endpointsecurity/es_event_type_notify_exec), and [`seq_num`](https://developer.apple.com/documentation/endpointsecurity/es_message_t/seq_num).
- **Legacy schedulers:** [`cron(8)`](https://keith.github.io/xcode-man-pages/cron.8.html), [`crontab(5)`](https://keith.github.io/xcode-man-pages/crontab.5.html), [`at(1)`](https://keith.github.io/xcode-man-pages/at.1.html), and the target OS's own man pages as the final authority.
- **Open-source/reverse engineering:** Objective-See [DumpBTM](https://github.com/objective-see/DumpBTM), [KnockKnock](https://github.com/objective-see/KnockKnock), and Csaba Fitzl's [Beyond the good ol' LaunchAgents](https://theevilbit.github.io/beyond/).
- **Independent research:** Howard Oakley's [In the background: Identification](https://eclecticlight.co/2026/02/20/in-the-background-identification/) and related BTM/log research; treat observed private details as build-specific.
- **Telemetry/prior art:** osquery's merged [modern BTM `startup_items` PR #8726](https://github.com/osquery/osquery/pull/8726), [LaunchControl comparison](https://www.soma-zone.com/LaunchControl/comparison.html), and [Lingon product documentation](https://www.peterborgapps.com/lingon/). Vendor claims require fixture verification.
