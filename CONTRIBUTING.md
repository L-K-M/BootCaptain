# Contributing

BootCaptain welcomes focused fixes and research improvements. Contributions are
released under the repository's [Unlicense](LICENSE).

## Before changing code

Read [PLAN.md](PLAN.md), [EVIDENCE.md](EVIDENCE.md), and [AGENTS.md](AGENTS.md).
The project distinguishes documented contracts, reproducible observations, and
open assumptions. Preserve that distinction in code and prose.

## Verification

Run the checks relevant to your change:

```sh
swift build
swift test
swift run bootcaptain coverage
scripts/verify.sh             # macOS app/helper changes
```

CI runs the portable suite on Linux and `scripts/verify.sh` on macOS. Do not
weaken a check or mark it best-effort to make a pull request green.

## Evidence and fixtures

- Update `EVIDENCE.md` when a change depends on new or revised undocumented behavior.
- Record macOS version/build, architecture, installation origin, account/session,
  management, SIP/FileVault/TCC state, command/fixture, and actual result.
- Use synthetic or aggressively sanitized fixtures. Never commit evidence captured
  from a real machine if it contains user, employer, software, path, command, or token data.
- A unit test does not qualify a privileged mutation or a supported OS release.

## Security-sensitive changes

Changes to the helper, XPC protocol, mutations, authorization, race-safe file
handling, journal/recovery, entitlements, signing, or releases require explicit
human security review. Explain the threat model and negative tests in the pull
request. Automated review is advisory only.

Keep commits focused and imperative. Do not commit generated Xcode projects,
build output, exports, signing files, or private fixtures.
