## Summary

Describe what changed and why.

## Verification

- [ ] `swift build`
- [ ] `swift test`
- [ ] `swift run bootcaptain coverage`
- [ ] `scripts/verify.sh` for macOS app/helper changes
- [ ] Documentation/evidence updated where behavior or assumptions changed

List checks not run and why.

## Safety Review

- [ ] No private parser output is used to authorize mutation.
- [ ] Unknown/failed coverage remains visible and fails closed.
- [ ] No raw host evidence, secrets, exports, logs, paths, or private fixtures are included.
- [ ] Generated `BootCaptain.xcodeproj` and build artifacts are not committed.
- [ ] This change does not qualify a mutation or macOS release based only on unit tests.

If this touches the helper, XPC, mutation, authorization, journal/recovery,
entitlements, signing, or release path, explain the threat model and request
focused human security review:

<!-- Security-sensitive rationale or "Not applicable" -->
