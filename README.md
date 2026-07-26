# BootCaptain

*A research prototype for a consumer-friendly, honest macOS startup auditor.*
BootCaptain currently inventories a partial set of startup mechanisms, keeps
several state axes separate, attempts product attribution, and experiments with
evidence behind failed startup items. The intended product is the concrete
answer to a vague *"Could not open file"* login dialog; the current prototype
does not yet provide exhaustive or release-qualified answers.

Current source version: **<!-- version -->0.1.0<!-- /version -->** (research prototype).

![BootCaptain icon](App/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png)

[`PLAN.md`](PLAN.md) is the product and architecture contract;
[`EVIDENCE.md`](EVIDENCE.md) records the claims that still need real Mac
fixtures. This repository implements early vertical slices of that design.
Undocumented tooling (`sfltool`), private BTM data, and unstable
`launchctl print` output remain build-sensitive prototypes, not support claims.

## What it does

- **Partial, tiered inventory** - canonical launchd files, shallow embedded
  service plists, an `sfltool dumpbtm` adapter, current-user login items, window
  restoration, cron files, basic extension/profile probes, and a legacy census.
  Many mechanisms in `PLAN.md` are not implemented, and several sources require
  permissions the ordinary app process does not have.
- **Separate state fields** - configured, registered, authorized, launchd
  override, loaded, and running exist in the model. Runtime reconciliation is
  provisional: launchd domain/session identity and cross-source joins are not
  yet production-correct.
- **Prototype attribution** - bundle containment, signing metadata,
  `AssociatedBundleIdentifiers`, Apple's attribution table, package receipts,
  and a small catalog contribute signals. App discovery and conflict handling
  remain incomplete.
- **Experimental diagnosis** - the manual **Boot Audit** command reads unified
  logs and crash reports. Correlation and observation windows still require
  fixtures, so results are evidence hints rather than definitive causal
  conclusions. It is not run automatically on first launch.
- **Prototype Clean Up path** - current-user vault/login-item actions and helper
  vault move/restore code exist. The helper-backed path has not passed the
  authorization, descriptor-safety, interruption, recovery, or hardware
  qualification required by `PLAN.md` and `EVIDENCE.md`; it must remain disabled
  in release builds. Launchd-state and cron mutations are also disabled. Undo
  history is session-scoped and login-item restoration is not exact.

## Layout

```text
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
Tests/               Portable Core and Kit XCTest suites.
project.yml          XcodeGen project for the app + helper.
```

The split is deliberate: much of the load-bearing reasoning is portable.
`swift build && swift test` runs Core and Kit logic on Linux. That validates
portable behavior, not real macOS schemas, permissions, signing, launchd
sessions, helper authorization, interruption recovery, or UI behavior.

## Building

### Core, Kit, and CLI (any platform with a Swift 5.9+ toolchain)

```sh
swift build
swift test
swift run bootcaptain coverage
swift run bootcaptain audit
```

On non-macOS the CLI exercises portable wiring. macOS commands are unavailable;
coverage reporting is still incomplete and should not be treated as a complete
capability manifest.

### The app + helper (macOS)

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r requirements-icons.txt
scripts/generate-project.sh
scripts/verify.sh
scripts/build.sh
```

The app is designed for Developer ID distribution with the hardened runtime and
is **non-sandboxed** (the full feature set is incompatible with the App Sandbox;
see `PLAN.md` section 6.4). The helper is embedded but is not registered
during read-only use. A research build that exposes helper-backed Clean Up can
register it on the first such action; that path is not release-qualified.

> **Status.** BootCaptain is a research prototype, not a supported release. CI
> tests the portable package and requires the unsigned app/helper bundle to
> compile on one macOS runner. That does not establish behavior across supported
> OS, architecture, permission, session, signing, or interruption matrices.

## Safety model in one paragraph

BootCaptain's required safety model is fail-closed: unknown evidence must not
become false state, private parser output must not authorize action, and no
mutation is qualified without typed requests, independent helper validation,
durable recovery, verified postconditions, and hardware evidence. The current
prototype does not yet satisfy all of those invariants; `PLAN.md` describes the
required end state rather than certifying the current build.

Build/release automation is documented in [`CICD.md`](CICD.md), security reports
in [`SECURITY.md`](SECURITY.md), and data handling in [`PRIVACY.md`](PRIVACY.md).

## License

Released under the [Unlicense](LICENSE).
