# BootCaptain

*A consumer-friendly, honest macOS startup manager.* BootCaptain shows
everything that can run at boot or login, tells you which app each item belongs
to, explains **why** it runs, distinguishes observation from authorization from
current state, disables what's safe to disable **reversibly**, and shows the
concrete evidence behind a failed startup item — the vague *"Could not open
file"* dialog with no name attached.

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
- **Safe, reversible actions** — the qualified mechanisms disable through the
  launchd override database (or a reversible cron-comment toggle), always with a
  precomputed undo. Everything else is a guided route to the owning app or
  System Settings. Nothing is deleted.

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
swift test            # 90 tests
swift run bootcaptain coverage
sudo swift run bootcaptain audit    # full coverage needs root + Full Disk Access
```

On non-macOS the CLI runs the whole engine and returns an empty, fully-gap-
flagged scan by design.

### The app + helper (macOS)

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
python3 scripts/make-icons.py     # regenerate the AppIcon set from media-sources/icon.png
xcodegen generate
open BootCaptain.xcodeproj         # set DEVELOPMENT_TEAM, then build & run
```

The app is Developer ID, hardened-runtime, **non-sandboxed** (the full feature
set is incompatible with the App Sandbox — see PLAN.md §6.4). The privileged
helper is registered on demand via `SMAppService.daemon`, pins the app's
designated code-signing requirement on every XPC connection, and is removable
with one click.

> **Status.** The portable engine (Core + Kit + CLI) compiles and passes its
> full test suite on the Linux Swift toolchain used in CI. The Xcode app/helper
> targets are authored against the documented macOS APIs but have **not** been
> built on a Mac in this environment — building them, wiring the real Team ID,
> and running the Phase-0 hardware matrix in PLAN.md §12 is the next step.

## Safety model in one paragraph

BootCaptain fails closed. It never mutates Apple/system or organization-managed
items, or anything whose provenance is unknown, conflicting, or whose launch
recipe couldn't be resolved — independent of SIP. Mutations are typed (never
shell fragments), routed through a privileged helper that re-validates every
target immediately before acting, journaled with a precomputed inverse, and
reversible. When it cannot prove an action's effect it reports *indeterminate*
rather than guessing.

## License

Released under the [Unlicense](LICENSE).
