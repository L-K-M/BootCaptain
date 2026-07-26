# BootCaptain

*A consumer-friendly, honest macOS startup auditor.* BootCaptain shows
everything that can run at boot or login, tells you which app each item belongs
to, explains **why** it runs, distinguishes observation from authorization from
current state, and shows the
concrete evidence behind a failed startup item — the vague *"Could not open
file"* dialog with no name attached.

Current source version: **<!-- version -->0.1.0<!-- /version -->** (research prototype).

<p align="center">
  <img src="App/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="128" alt="BootCaptain icon">
</p>

This repository implements the design in [`PLAN.md`](PLAN.md), backed by the
evidence register in [`EVIDENCE.md`](EVIDENCE.md). Wherever a behavior relies on
undocumented tooling (`sfltool`), a private store (the BTM database), or
unstable output (`launchctl print`), the code says so and fails soft.

## What it does

- **Exhaustive, tiered collection** — launchd daemons/agents (including
  SMAppService plists embedded in app bundles), Background Task Management,
  classic login items, "reopen windows" relaunch, cron/at/periodic, system
  extensions, app extensions, configuration profiles, and a legacy/adjacent
  census — split into **core**, **legacy**, and **advanced** tiers so a shell
  rc file is never presented as "runs at login".
- **Reconciled state, never one boolean** — configured / registered /
  authorized / launchd-override / loaded / running are tracked as separate axes.
- **Real attribution** — resolves the owning app from bundle containment, code
  signing Team ID, `AssociatedBundleIdentifiers`, Apple's own
  `attributions.plist`, package receipts, and a curated catalog — scoring vendor
  and product separately and surfacing conflicts.
- **Trust you can act on** — Apple/system and organization-managed items are
  never mutated; a spoofed `com.apple.*` label is a red flag; unknown or
  conflicting provenance fails closed.
- **Confidence-rated diagnosis** — a first-run boot audit correlates the unified
  log, `launchctl` counters, and crash reports into safe states
  (*active now*, *execution observed*, *failure evidence*, *configured, not
  observed*, *coverage incomplete*, …). Absence of telemetry never becomes
  "never attempted".
- **Fail-closed action guidance** — privileged mutation is disabled in this
  prototype until the durable journal, helper authorization boundary,
  descriptor-safe target handling, and Phase-0 hardware matrix in `PLAN.md` are
  complete; the app routes those cases to the owning app or System Settings.
  The one built-in action is **Clean Up**: provably-broken user-domain leftovers
  (orphaned `~/Library/LaunchAgents` plists, dead "Open at Login" entries) can
  be moved to a reversible vault or removed via System Events — as the current
  user, journaled, with one-click undo, and never touching Apple/managed items.

## Layout

```
Sources/
  BootCaptainCore/   Portable models, parsers, and safety logic. Foundation only;
                     builds and is unit-tested on Linux CI.
  BootCaptainKit/    macOS collectors + adapters (code signing, unified log, …),
                     the Scanner, DiagnosisEngine, ActionRunner, and the XPC
                     contract. Mac-SDK code is #if os(macOS)-guarded; the
                     subprocess/parse wiring is tested on Linux with a fake runner.
  bootcaptain/       Dependency-free CLI (scan / audit / export / coverage).
App/                 SwiftUI app (Xcode-built).
Helper/              Privileged SMAppService daemon + its launchd plist.
Tests/               90 XCTest cases, green on the Linux toolchain.
project.yml          XcodeGen project for the app + helper.
```

The split is deliberate: the **load-bearing reasoning is portable and verified
off a Mac**. `swift build && swift test` runs the entire Core + Kit logic on
Linux; the collectors report every macOS-only source as a coverage gap there,
which is exactly the honest behavior the app ships.

## Building

### Core, Kit, and CLI (any platform with a Swift 5.9+ toolchain)

```sh
swift build
swift test
swift run bootcaptain coverage
swift run bootcaptain audit
```

On non-macOS the CLI runs the whole engine and returns an empty, fully-gap-
flagged scan by design.

### The app + helper (macOS)

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
python3 -m pip install -r requirements-icons.txt
scripts/generate-project.sh
scripts/verify.sh
scripts/build.sh
```

The app is designed for Developer ID distribution with the hardened runtime and
is **non-sandboxed** (the full feature set is incompatible with the App Sandbox
— see PLAN.md §6.4). The helper code is embedded for continued development, but
the app does not register it during read-only use and privileged mutations are
disabled in this prototype.

> **Status.** BootCaptain is a research prototype, not a supported release. CI
> tests the portable package and requires the unsigned app/helper bundle to
> compile on macOS. Privileged mutation and helper registration remain gated on
> the security and hardware work in `PLAN.md` §12.

## Safety model in one paragraph

BootCaptain fails closed. It never treats unknown evidence as false, never uses
private parser output to authorize an action, and currently exposes no mutation
as qualified. The planned action path uses typed requests, independent helper
validation, durable journaling, verified postconditions, and precomputed
inverses; those are release requirements, not claims about the current build.

Build/release automation is documented in [`CICD.md`](CICD.md), security reports
in [`SECURITY.md`](SECURITY.md), and data handling in [`PRIVACY.md`](PRIVACY.md).

## License

Released under the [Unlicense](LICENSE).
