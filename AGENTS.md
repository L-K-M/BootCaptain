# BootCaptain agent and contributor notes

BootCaptain is a macOS startup-item auditor. It inventories startup mechanisms,
keeps configured/registered/authorized/loaded/running state separate, attributes
items to products, and explains the evidence behind startup failures.

Read these before changing behavior:

1. [PLAN.md](PLAN.md) is the architecture and product contract.
2. [EVIDENCE.md](EVIDENCE.md) records load-bearing claims and required hardware validation.
3. [README.md](README.md) states what the current prototype actually does.
4. [CICD.md](CICD.md) documents build and release automation.

## Current status

- This is a research prototype, not a supported release.
- The portable `BootCaptainCore`, `BootCaptainKit`, and CLI build with SwiftPM.
- The SwiftUI app and embedded privileged helper are generated from `project.yml` with XcodeGen.
- Privileged mutation is limited to the reversible Clean Up vault move/restore,
  performed by the admin-approved helper with durable prepared/committed
  journaling. The launchd and cron state mutations remain disabled — see
  `ActionRequest.Operation.isEnabledInCurrentBuild`. No mechanism has passed the
  full Phase-0 hardware, interruption, authorization, journal, and recovery
  matrix, so even the enabled move/restore path still needs on-device validation.
- Read-only use must not register the helper or install persistent components;
  the helper is registered only on the first privileged Clean Up action.

## Build and verify

```sh
swift build
swift test
swift run bootcaptain coverage

scripts/generate-project.sh   # macOS: icons + XcodeGen
scripts/verify.sh             # macOS CI gate
scripts/build.sh              # Release app -> dist/BootCaptain.app
scripts/build.sh --install    # install verified app in /Applications; no helper registration
scripts/build.sh --check      # resolved local build configuration
```

Do not run the CLI with `sudo`. Root is not Full Disk Access, changes the user
and launchd domains being inspected, and does not model the signed app/helper
permission boundary.

## Architecture invariants

- Unknown state is not false state. Collector or parser failure is a visible coverage gap.
- BTM authorization and launchd override are independent axes.
- State identity includes the launchd domain/session; a label alone is not unique.
- Missing log or crash evidence never proves an item did not execute.
- Attribution conflicts, unknown provenance, managed items, and Apple code fail closed.
- Private or undocumented schemas may inform display, never authorize mutation.
- `project.yml` is authoritative. Never hand-edit the generated `BootCaptain.xcodeproj`.
- The app and helper mutually authenticate with exact bundle ID and Team ID requirements.
  Missing signing identity or requirement setup must terminate the connection.
- The helper distrusts the app. Typed input still requires independent authorization,
  target reconstruction, signature/management checks, and race-safe descriptor traversal.
- A mutation is not qualified until durable prepared/committed journaling, postcondition
  verification, idempotent recovery, and the complete hardware matrix pass.

## Safety rules

- Never run mutating `launchctl`, `crontab`, `sfltool resetbtm`, helper registration,
  signing, or notarization commands merely to test a change on the user's machine.
- Never enable `SafetyPolicy.isMechanismQualified` because unit tests pass. Qualification
  requires recorded hardware evidence in `EVIDENCE.md` and explicit owner approval.
- Do not add shell-fragment or arbitrary-path XPC operations.
- Do not weaken app/helper requirements, entitlements, or helper validation for local convenience.
- Do not claim support for a macOS release without a recorded clean/upgrade fixture.
- Do not read, upload, or commit raw BTM stores, logs, crash reports, crontabs, exports,
  `.build` content, signing material, or private hardware fixtures.

Changes to `Helper/`, `Sources/BootCaptainKit/XPC/`, `ActionRunner`,
`SafetyPolicy`, entitlements, signing, or release automation require focused
human security review even when CI and GLM review are green.

## Versioning and releases

`project.yml` is the build version source. `Sources/BootCaptainCore/Info.swift`
must match it; app and helper plists consume `MARKETING_VERSION` and
`CURRENT_PROJECT_VERSION` from Xcode.

Cut releases only with:

```sh
scripts/release.sh X.Y.Z --push
```

The command increments the build number, synchronizes versions, commits, and
tags. Release CI is signed-only and publishes a draft prerelease. Never create a
`v*` tag by hand or publish an ad-hoc build: helper authentication requires a
real Apple Team ID.

## Repository automation

- `ci.yml` runs the portable suite and the required macOS app/helper build.
- `release.yml` re-runs CI, signs inside-out, notarizes, staples, verifies, and checksums.
- `zai-code-review.yml` reviews same-repository non-draft PRs when `ZAI_API_KEY` exists.
- Dependabot checks GitHub Actions and Swift packages weekly.

Automated review is advisory. It never replaces human review of privileged or
security-sensitive code.
