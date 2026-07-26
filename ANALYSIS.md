# BootCaptain Analysis and Roadmap

Updated: 2026-07-26

Source review: [`sol.md`](sol.md), based on `main` at `72b1726`

This is the forward-looking project document. `sol.md` preserves the complete
point-in-time audit, including findings that have since been implemented in open
pull requests. This file removes those completed implementations from the active
backlog while retaining a PR ledger so no reasoning is lost.

BootCaptain remains a research prototype. No mutation is release-qualified, and
no macOS version is supported until the corresponding hardware evidence is
recorded in `EVIDENCE.md`.

## Current priorities

1. Merge the fail-closed containment change after focused human security review.
2. Build correct source and launchd domain/session identity before adding more
   collectors or action logic.
3. Make collector/parser failure structurally distinct from an empty source.
4. Bound and cancel subprocess/scanning work before expanding Boot Audit.
5. Redesign diagnosis around typed, time-bounded evidence.
6. Deliver a narrow, read-only, third-party-first product before reintroducing
   mutation.

## Implemented PR ledger

These items are implemented and have their own branches/PRs. They are not active
roadmap entries unless a PR is rejected or closed without replacement.

| PR | Audit entries | Implemented outcome | Merge note |
| --- | --- | --- | --- |
| [#7](https://github.com/L-K-M/BootCaptain/pull/7) | SOL-001, containment from SOL-004 | Disables every privileged operation; requires mutation-permitted trust, reversible policy, resolved recipe, unconflicted attribution, and concrete broken health; hides helper candidates while disabled | Merge first; requires focused human security review |
| [#8](https://github.com/L-K-M/BootCaptain/pull/8) | SOL-012 | Removes private BTM `willRun`; leaves authorization and launchd override unknown; preserves disposition as private display evidence | Independent Core/Kit change |
| [#9](https://github.com/L-K-M/BootCaptain/pull/9) | SOL-020 | Stops suppressing live services merely because a label contains a UUID | Independent Core change |
| [#10](https://github.com/L-K-M/BootCaptain/pull/10) | bounded part of SOL-022 | Requires component-bounded label evidence for catalog product matching and uses Team ID to reject conflicts | Independent Core change |
| [#11](https://github.com/L-K-M/BootCaptain/pull/11) | current leak paths in SOL-028 | Uses opaque redacted IDs, removes command labels/notes, redacts display paths, passes custom homes, and adds adversarial tests | Independent Kit/CLI change |
| [#12](https://github.com/L-K-M/BootCaptain/pull/12) | sudo portion of SOL-050 | Removes forbidden sudo guidance and explains current-user/FDA scope | Independent CLI change |
| [#13](https://github.com/L-K-M/BootCaptain/pull/13) | SOL-030 | Keeps emond/periodic files visible without inventing an execution trigger from file presence | Independent Kit change; retain evidence-bounded periodic behavior |
| [#14](https://github.com/L-K-M/BootCaptain/pull/14) | SOL-045, SOL-047 | Removes default mutation selection/Return shortcut, confirms helper-backed batches, blocks dismissal during work, and makes cleanup copy honest | Independent SwiftUI change |
| [#15](https://github.com/L-K-M/BootCaptain/pull/15) | SOL-040 | Reconciles selection with displayed rows, resets detail-local state by item ID, and adds a contextual no-results view | Independent SwiftUI change |
| [#16](https://github.com/L-K-M/BootCaptain/pull/16) | SOL-060, SOL-066 | Documents the real prototype scope and provides isolated Python setup | Documentation/build-help change |
| [#17](https://github.com/L-K-M/BootCaptain/pull/17) | action-pin portion of SOL-064 | Pins every GitHub Action to a commit, disables persisted checkout credentials, and scopes release write permission to one job | Merge before updating Dependabot PR #4 |

## Merge guidance

- PR #7 is the release-blocking safety containment and should be reviewed first.
- PRs #8 through #13 modify separate Core/Kit/CLI concerns and are intentionally
  independent.
- PR #14 touches `CleanupSheet.swift` and `ItemDetailView.swift`; PR #15 touches
  `ContentView.swift` and `ScanViewModel.swift`, so they should normally merge
  without conflict.
- PR #16 owns README/setup wording.
- PR #17 owns action references and can conflict with Dependabot PR #4. Merge
  #17 first, then regenerate or rebase the setup-node update so it preserves SHA
  pinning and the readable version comment.
- Do not combine these branches into one unreviewable security/UI change. If
  main advances, rebase each PR independently and rerun all checks.

## Release blockers

### RB-01: Keep all mutation disabled

PR #7 restores the immediate build gate. Keep it closed until every requirement
below is implemented, tested, documented, and approved:

- Per-request Authorization Services right with narrow operation scope.
- Audit-token, UID, and login-session binding.
- Helper-side target reconstruction from an opaque identifier.
- Independent source, signature, management, Apple-critical, attribution, and
  policy checks in the helper.
- Descriptor-relative path traversal from fixed roots with no followed symlink.
- ACL, hard-link, mode, owner, device, inode, mount, and destination validation.
- Same-volume exclusive rename while retaining validated descriptors.
- Exact postcondition and already-achieved idempotency checks.
- Authoritative durable journal and startup recovery.
- Signed malicious-client and interruption tests.
- Complete hardware matrix in `EVIDENCE.md`.
- Explicit owner and focused human security approval.

Relevant full-review entries: SOL-002, SOL-003, SOL-005, SOL-006, SOL-007.

### RB-02: Build an authoritative journal and recovery state machine

The current JSON journal is useful scaffolding, not a release journal. Required
work:

- One helper-wide transaction lock, plus target-level serialization.
- Versioned schema and migrations.
- Exclusive record creation and duplicate-ID detection.
- Root-owned storage with verified mode, ACL, flags, ancestry, and no symlinks.
- Typed preconditions containing source/destination device, inode, hash, mode,
  ownership, metadata, action policy, exact domain, and actual vault path.
- Ordered file and parent-directory `fsync`/`F_FULLFSYNC` behavior with explicit
  unsupported-storage outcomes.
- Postcondition verification before terminal state.
- Structured load result that preserves corrupt, undecodable, duplicate, or
  unreadable records as blocking recovery errors.
- Reconciliation before accepting any new action or undo.
- Persistent action history rebuilt from committed records.
- Recovery-required/indeterminate outcomes exposed in app and CLI.

Acceptance requires crash and power interruption before and after every write,
rename, verification, and terminal transition. Unit tests alone do not qualify
this work.

Relevant full-review entries: SOL-005, SOL-006, SOL-046.

### RB-03: Remove or redesign login-item mutation

Classic login-item mutation remains unsuitable for release:

- The real scan pipeline does not establish a dead item end to end.
- Comma-separated enumeration is ambiguous.
- AppleScript source interpolation accepts quotes, slashes, and newlines.
- Removal can affect duplicate records.
- Hidden state, name, order, identity, bookmark data, and multiplicity are lost.
- Undo is in-memory, best-effort, and unjournaled.
- No exact postcondition is checked.
- The Automation usage description does not accurately disclose modification.

Keep the mechanism guided-only until a structured record API/event path, exact
preimage, journal, and verified restoration exist.

Relevant full-review entry: SOL-008.

### RB-04: Establish real Mac evidence before support claims

No tracked fixture corpus or hardware result currently qualifies macOS 13, 14,
15, 26, or 27. Required dimensions include:

- Clean install and upgraded systems.
- Intel and Apple silicon where applicable.
- Admin and standard users.
- Current user, SSH user domain, loginwindow, GUI login, fast user switching,
  and multiple concrete login sessions.
- Managed and unmanaged Macs.
- SIP, FileVault, TCC, and FDA combinations.
- Signed, unsigned, ad-hoc, tampered, universal, revoked, interpreter, and
  external-volume fixtures.
- Every private/unstable parser source on every supported build.
- Every action interruption and recovery point.

The artifacts must remain private and must not be committed raw, per
`AGENTS.md`.

## Architecture foundations

### AF-01: Separate configured source identity from service instances

The current `StartupItem` shape cannot correctly represent one source registered
in multiple domains or sessions. Replace label-based identity with a typed graph:

- Source identity: mechanism, canonical source root, device/inode or equivalent,
  owner UID, path/bookmark/BTM key, and mechanism-native key.
- Registration identity: exact launchd domain type, UID, audit session, label,
  registration source, and observation time.
- Execution identity: PID, start time, executable identity, signer, parent, and
  observation source.
- Product identity: candidate owning app/vendor/product claims with independent
  evidence.
- Explicit candidate edges among source, BTM, live launchd, app, receipt, and
  diagnostic records.
- Ambiguous/conflicting edges remain visible and never collapse facts.

Acceptance tests must cover identical labels in system, two user domains, two
login sessions, two source paths, and cross-mechanism label collisions.

Relevant full-review entries: SOL-009, SOL-010.

### AF-02: Attach provenance to every state observation

Each axis needs observations rather than one bare value:

```text
Observation<T>
  value
  collector and parser version
  exact source/domain/session
  collectedAt and requested interval
  OS version/build
  permission context
  confidence and warnings
  parse completeness/truncation
```

Do not overwrite disagreement. Compute display summaries from observations, and
never feed a compact display summary into mutation policy.

Relevant full-review entries: SOL-011, SOL-013, SOL-029.

### AF-03: Return structured parser and collector outcomes

Every parser/adapter must distinguish:

- Supported and successfully empty.
- Supported with records.
- Partially parsed with rejected records.
- Permission denied.
- Timed out or cancelled.
- Command unavailable.
- Recognized source but incompatible output.
- Unsupported on this build.
- Not implemented.
- Truncated by a safety bound.

Known-field type errors must retain the raw value and warning rather than
coercing false or silently dropping an argument. Zero-record outcomes need the
same parser/build/permission provenance as successful items.

Relevant full-review entries: SOL-016, SOL-017, SOL-029.

### AF-04: Model launch recipe context conservatively

Required recipe work:

- `RootDirectory`, `WorkingDirectory`, environment, PATH, and glob context.
- Absolute normalized paths only for authoritative resolution.
- `BundleProgram` traversal rejection and app ownership.
- Launcher, wrapper/interpreter, script, and final payload as separate nodes.
- Narrow per-interpreter option grammar.
- Shebang and `/usr/bin/env` chains.
- Inline commands, relative paths, combined/unknown flags, dynamic wrappers, and
  unknown launch context remain unresolved.

Relevant full-review entries: SOL-015, SOL-018, SOL-019.

### AF-05: Redesign signing and management observations

Separate these concepts:

- Signature absent.
- Signature present and valid.
- Signature present and invalid.
- Inspection unavailable/unknown.
- Apple platform versus Apple generic anchor.
- Team ID, signing ID, authority, and notarization status.
- Expected architecture slices and per-slice agreement.
- Management verified yes, verified no, or not checked.
- Source definition trust versus launcher/payload trust.

Unknown, incomplete, mixed-slice, source/payload conflict, or unchecked
management must remain mutation-forbidden. Unsigned code is a trust fact, not
proof that an executable is broken.

Relevant full-review entries: SOL-014, SOL-015, SOL-019.

### AF-06: Replace the collapsed effective-state boolean

The UI needs independent plain-language summaries:

- Configured source exists.
- Registered in exact domains/sessions.
- Authorized or blocked by documented policy.
- Launchd override for future launches.
- Loaded now.
- Process running now.
- Axes disagree or coverage is incomplete.

Examples such as running plus disabled-for-future-launches must remain
simultaneously visible. Plist `Disabled` default, session eligibility, and
registration/authorization cannot be omitted.

Relevant full-review entry: SOL-013.

### AF-07: Resolve attribution as coherent candidates

PR #10 fixes current catalog boundary matching. Remaining attribution work:

- Resolve coherent candidate product identities, not independent best fields.
- Confidence and provenance per vendor, product, Team ID, bundle ID, and icon.
- Product, bundle, path/app-copy, signer, and BTM-history conflict detection.
- Team ID as developer-account evidence, never sufficient product identity.
- Launch Services/Spotlight app discovery across installed copies and volumes.
- Preserve all `AssociatedBundleIdentifiers` and BTM claims.
- Return ambiguity/open confidence rather than input-order tie breaking.
- Versioned catalog schema, size limits, source URLs, expiry, rollback/freeze,
  key rotation, and bounded matching.

Relevant full-review entries: SOL-021, remaining SOL-022 work.

## Performance and responsiveness

### PF-01: Replace `ProcessRunner` with a bounded async runner

Required behavior:

- Async/await API with cooperative cancellation.
- Explicit stdout/stderr byte and record caps.
- Streaming parse where practical.
- Process group creation and descendant termination.
- SIGTERM grace period, SIGKILL escalation, bounded pipe drain, and bounded reap.
- Global scan deadline plus per-command deadlines.
- Structured timeout/cancel/truncation coverage.
- Tests for inherited pipes, signal-resistant children, large output, launch
  race, cancellation, and confirmed reap.

Relevant full-review entry: SOL-031.

### PF-02: Add one scan/mutation operation coordinator

The coordinator must:

- Retain a cancellable task.
- Publish phase, elapsed time, active source, items found, and progress bounds.
- Run independent collectors with bounded concurrency.
- Serialize TCC-sensitive prompts.
- Serialize all mutation against source reads.
- Queue mandatory generation-tagged post-action and post-undo scans.
- Reject stale result publication.
- Preserve and timestamp diagnosis until replaced, marking it stale instead of
  silently deleting it.
- Return accepted/queued/rejected outcomes rather than silently dropping calls.

Relevant full-review entries: SOL-032, SOL-033, SOL-049.

### PF-03: Move icon work off the main actor

Use bounded asynchronous prefetch and publish only completed images on the main
actor. Cache by app path/bundle ID plus strong file identity and scan generation,
not startup-item ID alone. Invalidate on remount, reinstall, replacement, or
reattribution.

Relevant full-review entry: SOL-034.

### PF-04: Profile before optimizing derived SwiftUI data

Add representative 500- and 1,000-item performance fixtures. Measure search,
filter, grouping, sorting, cleanup planning, icon population, and detail
selection. Only then derive one displayed snapshot per relevant model change or
add caching.

Relevant full-review entry: SOL-035.

### PF-05: Make user scope explicit and efficient

Discover users and active sessions through account/session APIs, preserve
UID-home mapping including custom homes, and make cross-user collection an
explicit scope. Probe permissions per collector rather than touching Mail/BTM
globally. Read system diagnostic reports once.

Relevant full-review entry: SOL-036.

## Diagnosis and evidence

### DE-01: Define a real observation window

Every audit must record:

- Requested boot/login/start/end interval.
- Actual accessible store bounds.
- Query execution status.
- Retention, redaction, truncation, and permission gaps.
- Source timestamps and parser versions.
- Whether evidence predates the current source identity.

An empty successful query is not useful negative coverage.

Relevant full-review entries: SOL-025, SOL-027.

### DE-02: Use typed evidence semantics and strong joins

Replace summary-string searching with typed signals:

- Current process.
- Execution observed.
- Normal/abnormal exit observation.
- Crash.
- Exec denial.
- Disabled refusal.
- Launchd configuration rejection.
- Qualified restart loop.
- Uninterpreted diagnostic observation.

Correlate by exact label, domain/session, source/executable identity, signer, PID,
parent relationship, and bounded timestamp where available. Basename substring
matches cannot establish causality. A restart loop requires repeated linked
events plus restart configuration.

Current activity, failure evidence, and coverage must remain independent facets;
one must not hide another.

Relevant full-review entries: SOL-025, SOL-026.

### DE-03: Integrate diagnostic coverage into UI and export

Inventory coverage and audit coverage need one timestamped capability model.
Every diagnosis and support export must state source execution, item-specific
coverage, interval, gaps, confidence, and sanitized supporting evidence.

Relevant full-review entries: SOL-027, SOL-029.

## Product and interface roadmap

### UX-01: Group by product family, not only technical tier

Default to known third-party vendor -> product -> component groups. Keep Apple
and system groups collapsed, unknown attribution explicit, and mechanism tier as
a secondary facet. Preserve every raw component and conflict.

Relevant full-review entry: SOL-037.

### UX-02: Expose all independent state axes

The detail view should show configured, registered, authorized, override,
loaded, and running with plain language, scope/domain, source/time, confidence,
and unknown reason. Keep raw technical values in an expert disclosure.

Relevant full-review entry: SOL-038.

### UX-03: Model guided destinations explicitly

Replace the universal Login Items deep link with typed destinations:

- Owning app settings.
- Login Items & Extensions.
- Family-specific extension settings.
- Profiles/management administrator.
- Reveal source or executable.
- Vendor documentation/off switch.
- Read-only explanation when no safe destination exists.

Carry the exact policy reason structurally; do not rediscover it by searching
free-form notes.

Relevant full-review entry: SOL-039.

### UX-04: Correct labels, status semantics, and accessibility

Remaining work after PR #15:

- Rename or correct Third-party, Launches at login, startup-items, broken, and
  cleanup counts so every predicate matches its label.
- Distinguish known non-Apple from unknown provenance.
- Use text plus symbol/shape plus color for health/running/trust state.
- Add row accessibility values, tooltips, and a status legend.
- Stop using a checkmark seal for unsigned, unknown, and conflicting trust.
- Make Failure Evidence health/status presentation consistent.
- Disable or queue menu scan commands while a scan is active.

Relevant full-review entries: SOL-041, SOL-042.

### UX-05: Make layouts adaptive and testable

Add App unit/UI test targets and screenshot coverage before redesigning layout.
Then replace fixed stat widths, nonwrapping badge/chip rows, path-expanding grids,
and fixed sheet dimensions with adaptive grids, wrapping layouts,
`ViewThatFits`, sensible split minimums, and resizable sheet min/ideal sizes.

Test minimum/wide windows, long localized values, long paths/vendors, large text,
VoiceOver, keyboard focus, light/dark, reduced contrast, and scan/result changes.

Relevant full-review entry: SOL-043.

### UX-06: Make coverage a first-class passport

Show pending/current/prior scan generations, timestamps, current scope, OS
build, permissions, and one row for every capability. Map internal enum names to
clear prose, provide exact remediation, and allow full detail expansion/copy.

Relevant full-review entries: SOL-029, SOL-044.

### UX-07: Build a permission center

Before a TCC prompt, explain the source, data scope, privacy effect, and optional
mutation use. After denial, show exact settings navigation and retry. The
Automation usage string must disclose both inventory and optional modification
if login-item mutation ever returns.

Relevant full-review entry: SOL-048.

### UX-08: Decide the first-run audit flow

Recommended flow:

1. Fast cancellable inventory.
2. Clear scope and coverage receipt.
3. Offer an explicit, privacy-explained Boot Audit.
4. Keep its timestamped result until replaced.
5. Mark evidence stale after inventory changes instead of deleting it.

Do not silently run an expensive, weakly bounded diagnostic query merely to
match old README wording.

Relevant full-review entry: SOL-049.

### UX-09: Add persistent actions and recovery UI only with the journal

An Actions & Recovery view should display transaction ID, scope, precondition,
prepared/committed/aborted/indeterminate state, verification, recovery need,
undo availability, residue, and timestamps. It must be reconstructed from the
authoritative journal, not an app-session array.

Relevant full-review entry: SOL-046.

### UX-10: Finish CLI behavior

PR #12 removes sudo guidance. Remaining CLI work:

- Strict known commands/options.
- Required option values; a flag cannot become `--out`'s filename.
- Usage errors to stderr with nonzero status.
- `--no-color` and TTY-aware ANSI output.
- Documented exit policy for command failure, partial coverage, and findings.
- Domain, independent state axes, conflicts, and gap details in machine output.
- Dedicated CLI tests.

Relevant full-review entry: remaining SOL-050 work.

## Inventory roadmap

Prioritize correctness of current sources before adding breadth.

### IR-01: Complete core application/launchd discovery

- Launch Services/Spotlight app inventory.
- Installed copies across user/system roots and mounted volumes.
- Nested apps and `Contents/Library/LoginItems`.
- Embedded SMAppService agents/daemons with malformed-item coverage.
- Arbitrary live launchd origins from per-service detail.
- Active user and concrete login-session domains.
- Unmatched `/Library/PrivilegedHelperTools` census.
- Source ownership, mode, ACL, mtime, file identity, raw plist hash, and exact
  trigger values.

Relevant full-review entry: SOL-051.

### IR-02: Build a versioned BTM/ServiceManagement adapter set

- Diagnostic text adapter with parser completeness.
- Optional private-store adapter with strict versioning and no action authority.
- Store ambiguity/coherence reporting.
- Parent/embedded item graph.
- Classic bookmark evidence.
- Managed and ServiceManagement status evidence where publicly supported.
- Visible disagreement across adapters.

Relevant full-review entry: SOL-052.

### IR-03: Preserve complete classic login records

Inventory apps, documents, folders, volumes, connections, duplicates, hidden
state, bookmark resolution, and unresolved/offline records. Compare with System
Settings while preserving private-schema uncertainty.

Relevant full-review entry: SOL-053.

### IR-04: Add managed background-task correlation

Parse relevant ServiceManagement profile policy and supervised macOS 15+ DDM
background-task configuration/status on qualified managed fixtures. Correlate
management facts to exact source and service identities; do not list every
profile as an execution item.

Relevant full-review entry: SOL-054.

### IR-05: Correct cron, at, and periodic capability handling

- Supported current-user `crontab -l` path.
- Per-source cron coverage and exact parsing provenance.
- `at` queue plus whether `atrun` has a real scheduling edge.
- Per-build periodic capability detection and launchd edge correlation.
- Residual artifact versus executable mechanism distinction.

Relevant full-review entry: SOL-055.

### IR-06: Add advanced mechanisms by evidence and user value

Candidate order:

1. Family-specific system extension and app extension state.
2. Kernel extensions/AuxKC.
3. Authorization and HAL host-load evidence.
4. Login/logout hooks and rc artifacts.
5. Shell, SSH, PAM, and persistent environment sources.
6. Folder Actions and Dock tile plug-ins.
7. Cryptex jobs.
8. Quick Look, Spotlight, SSO, browser add-ons, input methods, and scripting
   additions.

Each collector needs a capability contract, host/trigger explanation, source
provenance, error outcomes, fixtures, and an explicit reason it belongs in the
product. Do not flatten these into "launches at login."

Relevant full-review entry: SOL-056.

## Export and local history

### EX-01: Define explicit export privacy levels

PR #11 closes current obvious leaks. Before exporting richer evidence, define
separate DTOs:

- Local full: private, complete, never implied share-safe.
- Support redacted: opaque stable pseudonyms, no command/source secrets,
  sanitized evidence, exact scope/build/coverage.
- Summary only: aggregate counts and capability gaps.

Add a preview and privacy lint. Treat every ID, label, command, note, URL,
domain, volume, process observation, and path as potentially sensitive. Never
encode raw local models directly and never upload automatically.

Relevant full-review entry: remaining SOL-028 work, SOL-057.

### EX-02: Add local scan comparison

Use a versioned local snapshot schema after identity is corrected. Show new,
removed, moved, re-signed, re-attributed, domain-changed, authorization-changed,
newly running, newly denied, and newly failing components. Provide retention and
delete controls.

Relevant full-review entry: SOL-058.

## Test infrastructure

### TI-01: Add App, helper, and CLI test targets

- App view-model tests for selection, queued scans, stale diagnosis, coverage
  generations, cleanup result handling, and helper status refresh.
- SwiftUI/UI tests for keyboard, focus, VoiceOver, layout, permission copy,
  cleanup confirmation, and undo/recovery entry points.
- Helper integration tests with signed positive and negative identities.
- CLI argument, stderr/stdout, color, exit-status, JSON, and redaction tests.

### TI-02: Add adversarial portable suites

- Parser incompatibility and rejected-line accounting.
- Domain/session reconciliation collisions.
- Signing unknown/unsigned/invalid/mixed-slice cases.
- ProcessRunner descendants, output bounds, timeout, cancellation, and reap.
- Diagnosis time/correlation/conflict cases.
- Export path/user/URL/command/evidence secret cases.
- Journal corrupt/unreadable/duplicate/schema/transition cases.
- Request path traversal, negative/overflow line, mismatch, and replay cases.

### TI-03: Record the private hardware matrix

Use the issue template and `EVIDENCE.md` fields. Keep raw BTM stores, logs,
crashes, crontabs, signing materials, and private fixtures out of Git. Record
sanitized expected/actual outcomes and evidence references only.

Relevant full-review entry: SOL-059.

## Delivery and repository controls

### DR-01: Enforce human review of security-sensitive paths

Add CODEOWNERS/repository rules for `Helper/`, XPC, action/journal/policy code,
entitlements, signing, and release automation. Require a human security review
that automation cannot self-satisfy. Protect main, release environment, and tags.

CI should also assert:

- Every unqualified operation is disabled in the built artifact.
- Read-only startup cannot register the helper.
- App/helper IDs, plists, paths, versions, requirements, entitlements, runtime
  flags, and no-persistence keys are mutually consistent.
- Wrong ID, Team ID, ad-hoc signature, stale version, and missing authorization
  are rejected.

Relevant full-review entry: SOL-063.

### DR-02: Lock package-manager tooling

PR #17 pins GitHub Actions. Remaining supply-chain work:

- Pin `npx` packages and use a lockfile rather than `--yes` latest installs.
- Pin Python package versions with hashes.
- Pin or verify XcodeGen/create-dmg/Homebrew inputs.
- Separate mutable tool installation from the signing boundary.
- Minimize release-token lifetime and rotate credentials after suspected runner
  compromise.

Relevant full-review entry: remaining SOL-064 work.

### DR-03: Strengthen release provenance and package verification

- Require strict semver tags created through the release script.
- Verify signed tag provenance, protected-main ancestry, and monotonic build.
- Remove blanket `create-dmg ... || true`.
- Mount the final DMG and verify exact app hash, IDs, Team ID, signatures,
  requirements, entitlements, hardened runtime, staple, and expected layout.
- Verify the ZIP contains the same final stapled app.
- Keep every release draft/prerelease until a separate approval publishes it.

Relevant full-review entry: SOL-065.

### DR-04: Finish helper lifecycle behavior

After mutation is disabled and before any new helper trial:

- Refresh status before and after registration and on app activation.
- Distinguish requires-approval from not-registered.
- Check helper/protocol version before every privileged session.
- Invalidate connections after use.
- Implement transaction-aware idle exit.
- Expose status and explicit uninstall with surfaced errors.
- Test app replacement, stale running helper, upgrade, unregister, and idle exit.
- Remove `collectRootOnly` until separately authorized and bounded, or redesign it
  without assuming root implies FDA.

Relevant full-review entries: SOL-061, SOL-062.

## Product ideas

These remain candidates, not commitments. They must preserve uncertainty and
never influence trust/action policy merely because they are delightful.

### Startup Story

A causal graph from boot/login -> mechanism -> source -> launcher -> payload ->
product -> observed result/dialog, with an evidence receipt on every edge.

### Product Family Tree

One expandable family for an app, updater, daemon, agent, login helper,
extensions, BTM records, and managed rules while retaining raw identities.

### Evidence Receipt

Every badge opens source, timestamp, scope/domain, permission, parser version,
confidence, warnings, and why confidence is not higher.

### Coverage Passport

Per-Mac OS/build capability map: qualified, partial, denied, unsupported,
parser-drifted, not implemented, or intentionally excluded.

### Demand, Not Startup

A smart view for registered-on-demand services so users do not chase harmless
launchd definitions as login slowdown.

### Ghost App Detective

Explain helpers tied to unmounted volumes, stale DMGs, transferred accounts,
duplicate app copies, replaced executables, and old bundle claims. Offer reveal
and vendor guidance, not automatic deletion.

### System Settings Diff

Explain what macOS Settings shows, what BootCaptain additionally observes, and
why the records differ.

### Share-safe Support Capsule

Export preview, privacy lint, stable pseudonyms, scope/build/coverage metadata,
and sanitized evidence without automatic upload.

### Next Login Watch

Opt-in prospective observation with explicit start/stop time, dropped-event/gap
counters, and no claims about history before activation.

### Mystery Dialog Capture

Opt-in Accessibility capture of the presenting process, explicitly separated
from the likely triggering startup item.

### Label-churn Detector

Recognize a vendor updater reappearing under a new label and direct the user to
the durable vendor-supported off switch.

### Local Annotations

Private recognized/expected/investigate notes. Annotations never change trust,
health, evidence, or mutation authorization.

### Login Impact Lab

Measured before/after observations and clearly labeled estimates, never a scare
score and never automatic disabling.

## Definition of done for the next milestone

The next milestone should be a narrow read-only auditor, not a cleanup release.
It is done when:

- PR #7 or equivalent keeps all mutations disabled.
- Source/domain/session identity passes collision fixtures.
- Every implemented collector has structured zero/error/partial outcomes.
- Current-user launchd, app-contained services, BTM diagnostic evidence, classic
  login items, window restoration, and static missing-target checks are honest
  about scope and gaps.
- State axes and their provenance are visible without a collapsed action-driving
  boolean.
- The scan is bounded, cancellable, phase-visible, and stale-result safe.
- Export has reviewed privacy levels and adversarial tests.
- The default UI is third-party/product-first with Apple/system collapsed.
- App, CLI, and relevant helper rejection tests run in CI.
- README claims exactly that scope and nothing broader.
- No support or release qualification is claimed without recorded hardware
  evidence.
