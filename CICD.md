# CI/CD

BootCaptain has a portable Swift package/CLI and an XcodeGen macOS app containing
an embedded privileged helper. Both are real products, so CI gates both.

## Workflows

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| `ci.yml` | PRs, pushes to `main`, manual, reusable call | Build/test portable code; generate, test, build, and verify app/helper. |
| `zai-code-review.yml` | Same-repository non-draft PRs | GLM 5.2 review when `ZAI_API_KEY` is configured. |
| `release.yml` | `v*` tags | Re-prove, sign, notarize, verify, and create a draft prerelease. |

CI uses least-privilege read permissions, PR-only cancellation, and job timeouts.
The release workflow alone receives `contents: write` to create a GitHub Release.

## Continuous integration

The Linux job uses `swift:6.0.3-noble` and runs:

```sh
swift build
swift test
swift run bootcaptain coverage
```

The macOS job pins macOS 15 / Xcode 16.3, installs XcodeGen and the pinned Pillow
version, then runs `scripts/verify.sh`. That command:

1. Regenerates icons and the disposable Xcode project.
2. Fails if generated tracked icon assets changed.
3. Lints all plists and entitlements.
4. Runs SwiftPM tests on macOS.
5. Builds the SwiftUI app and helper with signing disabled.
6. Asserts the helper and launchd plist are in the expected bundle locations.
7. Checks the built version and applies/verifies an ad-hoc signature.

The app/helper build is mandatory. CI must never use `continue-on-error` for it.
An ad-hoc CI build is read-only: it has no Apple Team ID and the XPC connection
correctly refuses privileged helper authentication.

## Local builds

```sh
scripts/build.sh
scripts/build.sh --debug --clean
scripts/build.sh --clean --install
scripts/build.sh --zip --dmg
scripts/build.sh --check
```

Artifacts are staged under `dist/`. `--install` quits a running BootCaptain,
copies the verified bundle to `/Applications` with `ditto`, and reveals it. It
prefers an installed Apple Development identity (then Developer ID) so app/helper
mutual authentication and TCC identity are stable; with no Apple identity it
falls back to an ad-hoc signed read-only build and warns that grants will not
survive rebuilds. Installation never registers the helper, and privileged
mutations remain disabled independently of signing.

## Releases

Cut a release on macOS with the shared release engine installed:

```sh
scripts/release.sh 0.2.0 --push
```

The script synchronizes `project.yml` and `BootCaptainCoreInfo`, increments
`CURRENT_PROJECT_VERSION`, updates the README version marker, commits, tags, and
pushes only when `--push` is present. The workflow refuses a tag that disagrees
with either committed version.

BootCaptain has no unsigned release fallback. App/helper mutual authentication
requires exact Apple-anchored signatures and a shared Team ID. The release job:

1. Re-runs CI against the tagged commit.
2. Requires all signing and notarization secrets.
3. Builds app/helper unsigned, then signs nested code inside-out.
4. Verifies app/helper IDs, Team IDs, signatures, and requirements.
5. Submits and staples the app, then checks Gatekeeper before packaging it.
6. Creates the DMG from that stapled app, notarizes/staples the DMG, and creates
   a `ditto` ZIP plus SHA-256 file after all stapling is complete.
7. Publishes a draft prerelease for manual review.

Publishing remains a human decision while privileged functionality is unqualified.

## Secrets

Configure these in a protected `release` environment, ideally with required reviewers:

| Secret | Purpose |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Developer ID Application certificate/private key as base64 `.p12`. |
| `DEVELOPER_ID_P12_PASSWORD` | Password for the `.p12`. |
| `KEYCHAIN_PASSWORD` | Temporary CI keychain password. |
| `APPLE_TEAM_ID` | Ten-character Apple Developer Team ID. |
| `AC_API_KEY_BASE64` | App Store Connect API `.p8` key as base64. |
| `AC_API_KEY_ID` | API key identifier. |
| `AC_API_ISSUER_ID` | App Store Connect issuer UUID. |
| `ZAI_API_KEY` | Optional GLM review key; absent means the review job skips. |

Signing and API private keys are recovery assets. Keep offline backups and never
commit or paste them into issue/PR text or workflow logs.
