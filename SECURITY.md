# Security Policy

## Supported versions

BootCaptain has no supported public release yet. The repository is a research
prototype, and privileged mutations are disabled pending the security and
hardware qualification described in `PLAN.md`.

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability. Use GitHub's private
[security advisory form](https://github.com/L-K-M/BootCaptain/security/advisories/new)
or contact the maintainer through the address on their GitHub profile.

Include the affected commit, reproducible steps, expected impact, and sanitized
diagnostics only. Do not attach raw BTM stores, unified logs, crash reports,
crontabs, launchd databases, user paths, signing material, or exported scans.

## Security-sensitive scope

- Privileged helper registration, lifecycle, authorization, and XPC authentication.
- App/helper bundle identifiers, Team ID requirements, entitlements, and code signing.
- Mutation policy, target reconstruction, descriptor-safe file operations, journaling,
  postcondition verification, undo, and interruption recovery.
- launchd, BTM, cron, login-item, profile, extension, log, and crash collectors/parsers.
- Attribution and trust classification used to fail closed.
- Export redaction and handling of host-specific diagnostic evidence.
- Developer ID signing, notarization, packaging, checksums, and release credentials.

## Security baseline

- Read-only use installs and registers nothing.
- Privileged mutations remain disabled until the complete qualification matrix passes.
- Unknown, conflicting, Apple, or managed targets are immutable.
- Private parser output cannot authorize an action.
- XPC setup fails closed when either signing identity or exact code requirement is unavailable.
- The helper accepts typed operations only and must independently validate every request.
- No release is published without Developer ID signing, notarization, stapling, and verification.

The detailed threat model and evidence requirements are in [PLAN.md](PLAN.md)
and [EVIDENCE.md](EVIDENCE.md).
