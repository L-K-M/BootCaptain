# BootCaptain Review

Review date: 2026-07-26

Reviewed baseline: `main` at `72b17263339133367df1f2af2aa4f606acf66bdf`

## Scope and method

This review covers the SwiftUI app, portable Core and Kit packages, CLI,
privileged helper, XPC boundary, tests, project generation, build and release
automation, and the product contract in `PLAN.md`, `EVIDENCE.md`, `README.md`,
and `CICD.md`.

The review was static. The workspace does not have a Swift toolchain, so
`swift build`, `swift test`, and `swift run bootcaptain coverage` could not be
executed locally (`swift: command not found`). This Linux workspace also cannot
render the SwiftUI app or validate macOS behavior. Findings that depend on
private output, TCC, signing, launchd sessions, interruption behavior, or real
hardware remain explicitly marked as requiring fixtures or hardware evidence.

The review started at `fcc1dc1`. PR #6 was merged during the review, so the
repository was pulled again and the cleanup/helper delta was re-reviewed at
`72b1726` before this document was written.

## Severity and disposition

- **Critical**: unsafe root mutation, likely destructive behavior, or a direct
  defeat of a load-bearing safety boundary.
- **High**: materially wrong inventory, state, diagnosis, privacy, or mutation
  behavior.
- **Medium**: reproducible reliability, performance, usability, accessibility,
  or maintainability problem.
- **Low**: polish or a bounded edge case.
- **Implement now**: narrow, high-confidence work that does not require private
  schema guesses or hardware qualification.
- **Design first**: valid and important, but a quick patch would reinforce the
  wrong architecture or create migration risk.
- **Hardware first**: implementation must wait for the matrix in `EVIDENCE.md`.
- **Product decision**: useful direction that needs scope or interaction-design
  approval.

## Executive verdict

BootCaptain has an unusually strong written safety model and useful portable
foundations, but the implementation does not yet uphold several of its central
claims. It is a promising research prototype, not a trustworthy cleanup tool or
an exhaustive auditor today.

The most urgent issue is the merge of PR #6. It enables privileged
`moveToVault` and `restoreFromVault` operations even though no mechanism has
passed the documented qualification matrix. The helper currently lacks
per-operation Authorization Services approval, independent semantic policy,
descriptor-safe path traversal, authoritative durable recovery, and exact
postcondition verification. The generic move request can also accept cron paths
that the explicit cron operation claims are disabled. A signed build should not
be distributed from this baseline.

The next foundational issues are launchd identity and uncertainty. Live state
is keyed by label rather than exact domain/session, failed reads can become
definite negative state, and private BTM disposition is converted into launchd
override/effective state. Those choices contradict `AGENTS.md`, `PLAN.md`, and
`EVIDENCE.md` and can make an attractive UI confidently wrong.

The best near-term product is narrower: a fast, honest, read-only current-user
auditor with explicit scope, exact evidence receipts, third-party product
grouping, reliable coverage gaps, and share-safe export. Mutations should return
only after the helper boundary, journal, interruption recovery, and hardware
matrix are genuinely complete.

## What is already strong

- Core models distinguish unknown values instead of relying only on booleans.
- Trigger dimensions are not forced into one mutually exclusive category.
- Coverage gaps have a first-class model and a visible UI location.
- Trust, health, state, attribution, and diagnosis are conceptually separate.
- The app and helper use exact bundle ID plus Team ID XPC requirements.
- Read-only app startup does not register the helper.
- Explicit launchd and cron verbs remain disabled.
- There is no app telemetry or network dependency.
- Portable Core/Kit tests and mandatory macOS app/helper compilation provide a
  useful CI foundation.
- `PLAN.md` and `EVIDENCE.md` document uncertainty and required validation more
  carefully than most startup-item tools.

## Immediate release blockers

### SOL-001: Privileged vault operations bypass qualification

**Severity:** Critical
**Disposition:** Implement now; focused human security review required

`SafetyPolicy.isMechanismQualified` returns false for every mechanism, but the
separate `MutationPolicy` enables root vault moves. The helper checks the latter
and performs the operation. This turns an operation flag into a bypass around
the authoritative qualification decision.

References:

- `Sources/BootCaptainCore/Logic/SafetyPolicy.swift:44-74`
- `Sources/BootCaptainCore/Logic/MutationPolicy.swift:11-24`
- `Helper/main.swift:44-87`
- `Tests/BootCaptainCoreTests/MutationPolicyTests.swift:4-15`

Required direction: disable privileged vault moves and hide helper-required
cleanup candidates until authorization, target reconstruction, descriptor-safe
movement, durable recovery, postconditions, and the Phase-0 matrix are complete.
A future build flag may be one input to policy, never the complete policy.

### SOL-002: The enabled helper is an unauthorized root deputy

**Severity:** Critical
**Disposition:** Design first, then hardware and adversarial testing

SMAppService approval authorizes registration, not every future root operation.
Requests contain no operation-scoped Authorization Services right. The helper
does not bind user intent to the connection audit token, UID, or login session,
and does not independently reconstruct and authorize the startup item.

References:

- `App/Services/HelperClient.swift:92-127`
- `Helper/main.swift:39-87`
- `Helper/main.swift:134-156`
- `PLAN.md:554-576`

Required direction: use a short-lived, operation-specific authorization right;
validate it in the helper; bind it to the caller/session and opaque target; and
rerun signature, management, Apple-critical, source, and item policy in the
helper. App-side classification is not a security boundary.

### SOL-003: Generic root moves permit operation/path confusion and TOCTOU

**Severity:** Critical
**Disposition:** Design first; hardware first before re-enabling

`moveToVault` accepts the generic source allowlist, including `/etc/crontab` and
cron tabs, even though `cronToggleEntry` is disabled. `TargetGuard` checks only
the final path with `lstat`, discards the result, and later calls pathname-based
`FileManager.moveItem`. Intermediate symlinks, caller-writable ancestors, ACLs,
hard links, source identity, destination races, mount changes, and same-volume
atomicity are not protected.

References:

- `Sources/BootCaptainKit/XPC/RequestValidator.swift:9-16`
- `Sources/BootCaptainKit/XPC/RequestValidator.swift:53-75`
- `Helper/main.swift:55-81`
- `Helper/main.swift:114-130`
- `Sources/BootCaptainKit/Engine/ActionRunner.swift:120-158`
- `EVIDENCE.md:75-79`

Required direction: use helper-owned opaque target IDs and operation-specific
roots. Walk from fixed directory descriptors without following any symlink,
retain the validated file identity through an exclusive descriptor-relative
same-device rename, and verify the destination and postcondition.

### SOL-004: Cleanup admits mutation-forbidden and weakly orphaned items

**Severity:** Critical for helper candidates, High for user candidates
**Disposition:** Implement now as containment; deeper policy design follows

`CleanupPlanner` excludes Apple and managed classes but still admits `.unknown`
and `.brokenOrConflicting`, ignores `item.actionClass`, unresolved recipes and
attribution conflict, and treats one scan's `.possiblyOrphaned` result as enough
to mutate. A disconnected volume can therefore look broken. The helper does not
independently re-check these facts.

References:

- `Sources/BootCaptainCore/Logic/CleanupPlanner.swift:45-93`
- `Sources/BootCaptainCore/Model/Trust.swift:27-35`
- `Sources/BootCaptainCore/Logic/HealthDeriver.swift:45-60`
- `App/Services/CleanupService.swift:145-153`

Required direction: reject every mutation-forbidden trust class, attribution
conflict, unresolved execution chain, read-only action class, offline/unresolved
target, and single-scan orphan hypothesis. Later eligibility must be a positive
capability from one composed policy and be independently revalidated at action
time.

### SOL-005: Journaling is not yet durable, authoritative, or recovering

**Severity:** High
**Disposition:** Design first; hardware first for power-loss claims

PR #6 correctly aborts when an ordinary prepared write fails, journals user
vault undo, preserves failed undo for retry, and blocks app-session re-entry.
Those are useful fixes. The remaining journal uses `Data.write(.atomic)` without
file and parent-directory durability, records no verified preconditions or file
identity, has no helper-wide lock or postcondition check, and only logs pending
records at startup. Corrupt/unreadable records are logged and then disappear
from `unfinished()`. Completion-write failure is logged while the caller still
receives a committed result.

References:

- `Sources/BootCaptainKit/Engine/FileJournal.swift:10-92`
- `Sources/BootCaptainCore/Logic/ActionJournal.swift:48-78`
- `App/Services/CleanupService.swift:120-136`
- `Helper/main.swift:73-87`
- `Helper/main.swift:181-195`

Required direction: add a helper-wide transaction lock, schema/versioning,
exclusive record creation, restrictive verified storage, typed preconditions,
device/inode/hash/metadata and actual destination, ordered full file/directory
flushes, exact postconditions, structured load errors, and startup reconciliation
that blocks new work until every transaction is resolved.

### SOL-006: Restore is not bound to the original transaction

**Severity:** High
**Disposition:** Design first

Restore reconstructs a vault name from caller-controlled `itemID` and basename,
then accepts another caller-controlled destination. It is not tied to the
committed forward journal. A vaulted daemon could be restored into another
allowlisted root with the same basename. Restore also lacks the forward target
guard.

References:

- `Helper/main.swift:57-66`
- `Sources/BootCaptainKit/Engine/ActionRunner.swift:144-158`
- `Sources/BootCaptainCore/Logic/ActionJournal.swift:108-113`

Required direction: restore accepts only an opaque journal transaction ID. The
helper obtains the immutable original path and source identity from its own
committed record.

### SOL-007: User vault containment is only a string-prefix test

**Severity:** High
**Disposition:** Design first

A path such as `~/Library/LaunchAgents/../Preferences/file` passes the current
prefix check. The user path does not receive canonical containment, UID, regular
file, ancestor symlink, hard-link, ACL, or stable identity validation immediately
before mutation.

References:

- `Sources/BootCaptainCore/Logic/CleanupPlanner.swift:90-93`
- `App/Services/CleanupService.swift:112-142`
- `Sources/BootCaptainKit/Engine/ActionRunner.swift:125-140`

Required direction: use the same fixed-root descriptor strategy for user-scope
moves, with current-UID ownership and immediate-child plist constraints.

### SOL-008: Classic login-item cleanup is injected, lossy, and unreachable

**Severity:** High
**Disposition:** Implement guided-only containment now; redesign before mutation

The real scan pipeline does not mark recipe-less dead login items orphaned, so
the advertised cleanup case is normally unreachable. If called, source paths
are interpolated into AppleScript, allowing quotes, backslashes, or newlines to
change source. Enumeration splits on commas. Removal can delete every matching
record, and undo recreates one record with `hidden:false`, losing multiplicity,
order, identity, and original behavior. There is no journal or postcondition.

References:

- `Sources/BootCaptainKit/Collectors/SubprocessCollectors.swift:13-34`
- `Sources/BootCaptainKit/Engine/StaticHealth.swift:12-19`
- `App/Services/CleanupService.swift:156-186`
- `App/Info.plist:21-23`

Required direction: keep this guided-only for now. Later use structured Apple
events or `osascript` argv rather than source interpolation, collect all original
properties, mutate one reviewed record, journal it, and verify exact removal and
restoration. Update the Automation disclosure to mention optional modification.

## State, identity, and parser correctness

### SOL-009: Launchd identity drops domain, user, and session

**Severity:** High
**Disposition:** Design first

Live services are keyed only by label and overwrite one another across `system`,
`user/<uid>`, and `gui/<uid>`. Disk IDs omit source identity and session. Most
agents have no domain, and reconciliation defaults them to `system`. Same-label
records can disappear or borrow another domain's loaded/running/override state.

References:

- `Sources/BootCaptainCore/Model/StartupItem.swift:43-54`
- `Sources/BootCaptainKit/Collectors/LaunchctlStateCollector.swift:8-70`
- `Sources/BootCaptainKit/Collectors/LaunchdFileCollector.swift:87-109`
- `Sources/BootCaptainKit/Engine/Scanner.swift:67-138`

Required direction: model configured sources separately from per-domain
registrations. Identity must include mechanism key, source file identity, owner
UID, exact domain type/UID/audit session, and label. Preserve conflicts rather
than selecting one row.

### SOL-010: Cross-source reconciliation is mostly synthetic-ID deduplication

**Severity:** High
**Disposition:** Design first

Disk launchd, BTM, embedded service, and live records normally have unrelated
IDs and remain duplicates. Exact ID collisions select one whole record and keep
little beyond provenance and one running fact, dropping competing source, state,
domain, attribution, and conflict information.

References:

- `Sources/BootCaptainKit/Collectors/LaunchdFileCollector.swift:87-109`
- `Sources/BootCaptainKit/Collectors/BTMCollector.swift:39-53`
- `Sources/BootCaptainKit/Engine/Scanner.swift:67-91`
- `Sources/BootCaptainKit/Engine/Scanner.swift:228-233`

Required direction: introduce a reconciliation graph with source nodes,
domain/session instances, cautious evidence-backed edges, and visible ambiguous
matches.

### SOL-011: Failed or unparsed launchctl reads become definite state

**Severity:** High
**Disposition:** Design first, then implement with parser outcomes

Missing services become loaded/running `.no`, and a missing override entry
becomes `.absentDefault`, even when a domain command failed or output was not
recognized. `print-disabled` failures have no separate coverage. This directly
violates unknown-is-not-false.

References:

- `Sources/BootCaptainKit/Collectors/LaunchctlStateCollector.swift:21-69`
- `Sources/BootCaptainKit/Engine/Scanner.swift:126-138`
- `Sources/BootCaptainCore/Model/StateAxes.swift:66-75`

Required direction: carry command and parser completeness per domain and per
axis. Infer negative/absent state only after a successful authoritative query
with a recognized complete format.

### SOL-012: Private BTM disposition is treated as effective launchd state

**Severity:** High
**Disposition:** Implement now

`BTMRecord.willRun` assumes private `enabled && allowed` bits form a stable
formula. `BTMCollector` then converts that result into launchd override state,
coupling two independent axes. Tests currently codify the unsupported formula.

References:

- `Sources/BootCaptainCore/Parsing/BTMDumpParser.swift:34-45`
- `Sources/BootCaptainKit/Collectors/BTMCollector.swift:33-37`
- `Tests/BootCaptainCoreTests/OutputParsingTests.swift:94-110`
- `Tests/BootCaptainKitTests/CollectorTests.swift:118-132`
- `EVIDENCE.md:46-49`

Required direction: remove `willRun`, preserve raw disposition plus decoder/build
metadata and unknown bits, and leave launchd override unknown. Any authorization
hint must remain separately labeled private evidence.

### SOL-013: `effectivelyEnabled` invents certainty from disagreeing axes

**Severity:** High
**Disposition:** Design first

Examples include disabled override plus running process returning off,
configured plus absent override returning on despite plist `Disabled`, and
explicit enable returning on despite registration or authorization denial.
Registration and authorization are mostly ignored.

References:

- `Sources/BootCaptainCore/Model/StateAxes.swift:20-31`
- `Sources/BootCaptainCore/Model/StateAxes.swift:66-75`
- `Tests/BootCaptainCoreTests/LogicTests.swift:264-275`

Required direction: present independent summaries such as running now, disabled
for future launches, loadable, and axes disagree. A compact value must become
unknown when material facts conflict and must not drive actions.

### SOL-014: Signing states confuse unknown, unsigned, and invalid

**Severity:** High
**Disposition:** Design first, then portable tests

Inspection failure returns a nonempty unknown identity that later classifies as
unsigned. Explicit unsigned code is represented as invalid and can classify as
broken/conflicting and broken health. One aggregate identity cannot establish
per-architecture agreement. Management-not-checked is also indistinguishable
from verified unmanaged.

References:

- `Sources/BootCaptainKit/Adapters/CodeSigningInspector.swift:13-58`
- `Sources/BootCaptainCore/Logic/TrustClassifier.swift:37-93`
- `Sources/BootCaptainCore/Model/Trust.swift:77-115`
- `Sources/BootCaptainKit/Engine/StaticHealth.swift:39-42`

Required direction: model presence, validity, identity agreement, notarization,
management, and source/payload trust as separate observations. Unknown remains
mutation-forbidden; unsigned is not the same as a corrupt signature or broken
executable.

### SOL-015: SSV source trust can mask an external or interpreted payload

**Severity:** High
**Disposition:** Design first

The scanner computes SSV status from the source plist and may skip inspecting an
external trust target. An unresolved interpreter falls back to trusting the
Apple interpreter itself. A system-owned definition can therefore make a
mutable payload appear Apple-owned.

References:

- `Sources/BootCaptainCore/Model/StartupItem.swift:34-38`
- `Sources/BootCaptainCore/Parsing/RecipeResolver.swift:54-63`
- `Sources/BootCaptainKit/Engine/Scanner.swift:140-158`

Required direction: keep source definition, launcher, wrapper/interpreter,
script/payload, and owning product trust separate. An unresolved payload has no
authoritative trust path.

### SOL-016: Parsers cannot distinguish empty data from incompatible data

**Severity:** High
**Disposition:** Design first

Launchctl, BTM, cron, and NDJSON parsers generally return only records. A new
format, malformed line set, and genuinely empty source can all return an empty
array. Callers then report collection ran and derive negative state.

References:

- `Sources/BootCaptainCore/Parsing/LaunchctlParsers.swift:3-155`
- `Sources/BootCaptainCore/Parsing/BTMDumpParser.swift:64-109`
- `Sources/BootCaptainCore/Parsing/CronParser.swift:48-75`
- `Sources/BootCaptainCore/Parsing/UnifiedLogMatchers.swift:76-86`

Required direction: return structured parse outcomes with recognized-format
confidence, records, rejected lines, warnings, input counts, unknown fields, and
fatal incompatibility.

### SOL-017: Launchd plist type errors are coerced into plausible jobs

**Severity:** High
**Disposition:** Design first

Malformed booleans become false, mixed `ProgramArguments` lose non-string
members, malformed schedules still mark jobs scheduled, and absent versus false
`Disabled` is collapsed. Invalid required labels and known-key errors have no
structured warning.

References:

- `Sources/BootCaptainCore/Parsing/LaunchdJob.swift:92-154`
- `Tests/BootCaptainCoreTests/LaunchdParsingTests.swift:9-62`

Required direction: validate known types strictly, preserve malformed raw values
as evidence, and return partial/error outcomes instead of invented facts.

### SOL-018: Recipe resolution accepts context-dependent and inline commands

**Severity:** High
**Disposition:** Design first

Relative paths containing `/`, `BundleProgram` traversal, combined shell flags,
inline commands containing slashes, and unknown wrappers can be marked resolved
without modeled root/working directory or interpreter grammar.

References:

- `Sources/BootCaptainCore/Parsing/RecipeResolver.swift:26-87`
- `Sources/BootCaptainCore/Parsing/LaunchdJob.swift:60-66`

Required direction: resolve only normalized absolute paths under an explicit
launch context. Use narrow per-interpreter grammars and leave every unsupported
wrapper or inline mode unresolved.

### SOL-019: Static health turns incomplete checks into healthy or broken

**Severity:** High
**Disposition:** Design first

`plistParsed` defaults positive, existence can produce `.ok` while architecture,
signature, payload, and runnability are unknown, and health checks an
interpreter rather than its script. A missing mounted volume is classified as a
missing executable before its tentative offline-volume signal. Cleanup reasons
are reconstructed from the coarse enum and can state the wrong failure.

References:

- `Sources/BootCaptainKit/Engine/StaticHealth.swift:12-45`
- `Sources/BootCaptainCore/Logic/HealthDeriver.swift:20-61`
- `Sources/BootCaptainCore/Logic/CleanupPlanner.swift:94-101`

Required direction: make every observation unknown by default, inspect launcher
and resolved payload separately, give unavailable-volume status precedence, and
carry structured health findings through to UI and policy.

### SOL-020: UUID syntax alone hides live-only services

**Severity:** High
**Disposition:** Implement now

Any UUID anywhere in a label is treated as proof of a transient session service.
Persistent or malicious arbitrary-origin jobs can therefore disappear by using
a UUID. The tests enforce this heuristic.

References:

- `Sources/BootCaptainCore/Logic/DisplayPolish.swift:11-18`
- `Tests/BootCaptainCoreTests/DisplayAndCleanupTests.swift:14-17`
- `Sources/BootCaptainKit/Engine/Scanner.swift:89-110`

Required direction: never suppress on label syntax alone. Keep unmatched
live-only records visible unless a build-qualified registration shape and
supporting domain/origin evidence establish transience.

### SOL-021: Attribution can synthesize a confident identity that no source made

**Severity:** Medium
**Disposition:** Design first

Vendor, product, Team ID, bundle ID, and icon are selected independently while
one global confidence comes from the strongest signal. Product and bundle
conflicts are not detected. Equal weights can depend on input order.

References:

- `Sources/BootCaptainCore/Logic/AttributionScorer.swift:21-60`
- `Sources/BootCaptainCore/Model/Attribution.swift:49-80`

Required direction: resolve coherent identity candidates, retain per-field
confidence and provenance, and surface unresolved strong conflict as open.

### SOL-022: Catalog Team ID and prefix matching can name the wrong product

**Severity:** Medium
**Disposition:** Implement now for boundary/ambiguity behavior

The first Team ID match wins even when a developer ships several products, and
prefix matching lacks a component boundary (`com.dropbox` matches
`com.dropboxevil`).

References:

- `Sources/BootCaptainCore/Logic/Catalog.swift:44-68`
- `EVIDENCE.md:83-86`

Required direction: use Team ID as vendor evidence unless constrained product
facts also match, require equality or `.` boundaries for prefixes, and return
ambiguity instead of first-entry wins.

### SOL-023: Cron identity and inverse behavior are not stable

**Severity:** Medium
**Disposition:** Design first; keep mutation disabled

Line number is called stable identity, `toggle` is non-idempotent, whitespace is
not round-tripped exactly, a forged marker can be re-enabled, and the inverse
does not capture a full-tab/line preimage. A negative line number can pass XPC
validation and later index an array. `/etc/crontab` is incorrectly suitable for
`crontab <file>` behavior.

References:

- `Sources/BootCaptainCore/Parsing/CronParser.swift:12-19`
- `Sources/BootCaptainCore/Parsing/CronParser.swift:111-126`
- `Sources/BootCaptainKit/XPC/RequestValidator.swift:45-51`
- `Sources/BootCaptainKit/Engine/ActionRunner.swift:84-117`

Required direction: directional set-state operations, exact preimage hashes and
transaction markers, strict source/user separation, nonnegative bounds, and
postcondition verification.

### SOL-024: Bootout has the wrong inverse

**Severity:** Medium while gated
**Disposition:** Design first

`launchdBootout` returns `launchdDisable` as its inverse. Undoing unload by
persistently disabling a service is objectively wrong. Enable/disable inverses
also cannot restore an absent/default override.

References:

- `Sources/BootCaptainCore/Logic/ActionJournal.swift:85-114`
- `Tests/BootCaptainCoreTests/LogicTests.swift:217-224`

Required direction: add typed bootstrap only when exact source and pre-state are
known, and return no exact inverse when persistent residue cannot be restored.

## Diagnosis, privacy, and coverage

### SOL-025: Boot Audit correlates stale and unrelated evidence

**Severity:** High
**Disposition:** Design first; hardware fixtures required

All available `.ips` files are read without a current-boot/login interval,
system reports are duplicated per home, and crashes are matched mainly by
process basename. Unified logs are indexed by emitter, so launchd messages often
do not join the target. Substring matching, first-five-record limits, discarded
timestamps, and a single throttle line can produce missed or false conclusions.

References:

- `Sources/BootCaptainKit/Adapters/DiagnosticsAdapters.swift:27-66`
- `Sources/BootCaptainKit/Engine/DiagnosisEngine.swift:20-112`
- `EVIDENCE.md:92-98`

Required direction: record an explicit interval and accessible-store bounds,
deduplicate sources, retain timestamps, and correlate typed evidence through
exact label/path/PID/domain/signing facts. Restart-loop claims require repeated
temporally linked events plus configured restart behavior.

### SOL-026: Diagnosis derives state from prose and hides conflicting facts

**Severity:** High
**Disposition:** Design first

Human summaries are searched for words such as failure/respawn. Any unmatched
log evidence can become execution-observed, including a disabled refusal.
`activeNow` takes precedence over crash/failure evidence. Evidence confidence is
discarded or hard-coded, and usable coverage defaults optimistically.

References:

- `Sources/BootCaptainCore/Logic/SafeStateDeriver.swift:18-106`
- `Sources/BootCaptainCore/Parsing/UnifiedLogMatchers.swift:53-92`

Required direction: use typed semantics such as execution, current process,
exit, crash, exec denial, disabled refusal, and qualified loop. Keep current
activity, failure, and coverage as independent facets.

### SOL-027: Diagnostic coverage can become a false negative conclusion

**Severity:** High
**Disposition:** Design first

A successful zero-row log query is considered usable historical coverage. If
logs fail, any unrelated crash report can make coverage usable for every item.
The CLI and export retain inventory coverage but omit diagnostic source failure,
allowing medium-confidence configured-not-observed claims with incomplete data.

References:

- `Sources/BootCaptainKit/Adapters/DiagnosticsAdapters.swift:33-42`
- `Sources/BootCaptainKit/Engine/DiagnosisEngine.swift:56-102`
- `Sources/bootcaptain/main.swift:20-28`
- `Sources/BootCaptainKit/Engine/ScanExport.swift:49-60`

Required direction: model query execution separately from evidence coverage for
each source, item, and interval. Zero matches are not useful negative coverage.

### SOL-028: Redacted export leaks paths, usernames, and commands

**Severity:** High
**Disposition:** Implement now

Only `sourcePath` and notes are redacted. IDs and labels can contain complete
login-item paths, usernames, cron tab paths, full cron commands, URLs, or
secrets. Custom homes are not supplied by the CLI. Raw text audit output can
also print diagnostic observations. At the same time, export omits exact domain,
independent state axes, provenance, evidence, and gaps needed to audit results.

References:

- `Sources/BootCaptainKit/Engine/ScanExport.swift:36-80`
- `Sources/bootcaptain/main.swift:84-119`
- `Sources/BootCaptainKit/Collectors/SubprocessCollectors.swift:23-30`
- `Sources/BootCaptainKit/Collectors/CronCollector.swift:49-66`

Required direction: use export-only opaque IDs, redact every free-form or
path-bearing field, include discovered custom homes, and add adversarial tests.
Design explicit local-full, support-redacted, and summary-only DTOs before adding
more evidence fields.

### SOL-029: Coverage reports success for hidden failures and missing mechanisms

**Severity:** High
**Disposition:** Design first

Only instantiated collectors receive coverage rows, so unimplemented taxonomy
is invisible. Unreadable directories/files, malformed embedded plists, failed
window-restoration reads, parser-zero BTM output, partial cron reads, profile
errors, and crash parser failures can appear empty or complete. Source-level
provenance is missing when no item exists.

References:

- `Sources/BootCaptainKit/Engine/Scanner.swift:39-64`
- `Sources/BootCaptainKit/Collectors/LaunchdFileCollector.swift:49-63`
- `Sources/BootCaptainKit/Collectors/FileCensusCollectors.swift:11-46`
- `Sources/BootCaptainKit/Collectors/CronCollector.swift:27-46`
- `Sources/BootCaptainCore/Model/Coverage.swift:6-68`

Required direction: add an OS-build capability manifest with every source marked
supported, attempted, empty, denied, timed out, parser-incompatible, partial,
not implemented, or inapplicable, including timestamp and parser provenance.

### SOL-030: Legacy census makes claims the evidence register leaves open

**Severity:** Medium
**Disposition:** Implement now for wording/classification

The collector states emond was removed in Ventura and marks periodic directory
children as active speculative scripts, while `PLAN.md` requires build-specific
capability evidence and warns residual files may be artifacts.

References:

- `Sources/BootCaptainKit/Collectors/FileCensusCollectors.swift:73-117`
- `PLAN.md:224-235`

Required direction: display version-sensitive artifacts with unknown execution
state until a concrete execution edge is observed.

## Performance and concurrency

### SOL-031: Subprocess timeouts are not hard bounds and output is unlimited

**Severity:** High
**Disposition:** Design first

`readDataToEndOfFile` retains unlimited output. Timeout kills only the direct
child, while descendants can retain pipes and make the final wait unbounded.
There is no post-kill deadline, process-group cleanup, output cap, or
cancellation. Tests cover only basic execution and launch failure.

References:

- `Sources/BootCaptainKit/System/ProcessRunner.swift:26-75`
- `Tests/BootCaptainKitTests/CollectorTests.swift:26-39`

Required direction: implement an async cancellation-aware runner, bounded
streaming buffers, process-group termination, bounded drain/reap, and explicit
truncation coverage.

### SOL-032: Serial scan topology can appear hung for minutes

**Severity:** High
**Disposition:** Design first

Collectors and per-item enrichment are sequential. Seven launchctl calls can
each take 30 seconds, receipt lookup can add 15 seconds per item, and audit log
collection can add 120 seconds while materializing full output. The UI has only
an indefinite spinner and discards the detached task handle.

References:

- `App/ViewModels/ScanViewModel.swift:27-45`
- `Sources/BootCaptainKit/Engine/Scanner.swift:51-87`
- `Sources/BootCaptainKit/Engine/AttributionEngine.swift:70-79`
- `Sources/BootCaptainKit/Adapters/DiagnosticsAdapters.swift:27-42`

Required direction: show phase, elapsed time, items found, and cancel; check
cancellation between operations; run independent work with bounded concurrency;
and safely cache immutable signing/receipt facts by strong file identity.

### SOL-033: Scans and mutations race and mandatory rescans can be dropped

**Severity:** High
**Disposition:** Design first

Cleanup stays available while a scan is reading. `scan()` silently rejects an
overlapping request, so the required post-mutation scan can be lost and an older
scan can publish stale pre-mutation data. Cleanup's re-entry guard silently
returns, while callers still rescan and may display an unrelated last result.
Normal rescans also erase prior audit diagnosis.

References:

- `App/ViewModels/ScanViewModel.swift:27-44`
- `App/Views/ContentView.swift:191-218`
- `App/Views/ItemDetailView.swift:102-126`
- `App/Services/CleanupService.swift:54-69`

Required direction: serialize scans and mutations in one coordinator, return an
accepted/result value, queue generation-tagged mandatory rescans, and retain
timestamped diagnosis until replaced or explicitly marked stale.

### SOL-034: Icon lookup can stutter scrolling on the main actor

**Severity:** Medium
**Disposition:** Implement after app test target exists

Row rendering can perform filesystem, bundle, Launch Services, and icon work
synchronously on the main actor. Cache identity is only item ID, so missing or
old icons survive remount, reinstall, or reattribution.

References:

- `App/Views/ContentView.swift:132-149`
- `App/Services/IconStore.swift:9-58`

Required direction: bounded asynchronous prefetch, main-actor publication only,
and cache keys/invalidation based on attribution path, bundle ID, file identity,
and scan generation.

### SOL-035: Derived list work repeats on every publication and keystroke

**Severity:** Low
**Disposition:** Implement only after profiling representative inventories

Filtering, lowercasing, grouping, sorting, and cleanup planning are repeatedly
recomputed. This is likely visible at hundreds of rows but should be measured
before adding caching complexity.

References:

- `App/ViewModels/ScanViewModel.swift:48-86`
- `App/Views/ContentView.swift:10-62`

Required direction: derive one displayed snapshot per relevant model change and
normalize the query once. Do not add memoization without a measured need.

### SOL-036: User discovery causes duplicate work and privacy-sensitive probes

**Severity:** Medium
**Disposition:** Design first

Every `/Users/*/Library` directory is treated as a user without UID/session
mapping. A custom home can be omitted. FDA probes touch Mail/BTM even when the
result is unused, diagnosis scans dormant homes automatically, and system crash
reports are reread once per home.

References:

- `Sources/BootCaptainKit/System/SystemEnvironment.swift:12-53`
- `Sources/BootCaptainKit/Engine/DiagnosisEngine.swift:23-29`
- `Sources/BootCaptainKit/Adapters/DiagnosticsAdapters.swift:52-65`

Required direction: discover current and active users through account/session
APIs, retain UID-home mapping, request cross-user scope explicitly, and probe
permissions only for the collector that needs them.

## UI, layout, and usability

### SOL-037: The default information architecture is a flat technical list

**Severity:** High product issue
**Disposition:** Product decision, then implement

Rows are grouped only by core/legacy/advanced tier. Apple jobs dominate and
related helpers are not grouped under their vendor/app, despite attribution
being a central product promise.

References:

- `App/ViewModels/ScanViewModel.swift:54-62`
- `App/Views/ContentView.swift:45-71`
- `PLAN.md:812-817`

Recommended direction: third-party-first vendor -> product -> component groups,
with collapsed Apple/system sections and explicit unknown attribution. Keep tier
and raw source available as secondary facets.

### SOL-038: Item detail hides most independent state axes

**Severity:** High product issue
**Disposition:** Implement after identity/state corrections

The detail view shows collapsed effective state plus loaded and running, omitting
configured, registered, authorized, and launchd override. Raw enum values such
as `yes` and `unknown` are not consumer explanations.

References:

- `App/Views/ItemDetailView.swift:161-173`
- `Sources/BootCaptainCore/Model/StateAxes.swift:34-48`

Recommended direction: show all axes with plain language, exact scope/domain,
observation source/time, and why an unknown is unknown. Keep the summary but do
not let it replace the facts.

### SOL-039: Every guided action opens the Login Items pane

**Severity:** High usability issue
**Disposition:** Design model first

Cron, profiles, extensions, window restoration, launchd definitions, and other
mechanisms all route to the same settings URL. The structured safety reason is
reduced to free text and rediscovered through case-sensitive keyword matching.

References:

- `App/Views/ItemDetailView.swift:141-153`
- `Sources/BootCaptainCore/Logic/SafetyPolicy.swift:57-66`

Recommended direction: model typed destinations and reasons: owning app,
Login Items, extension settings, profiles, administrator, reveal source, or
documentation.

### SOL-040: Selection and detail-local state can refer to the wrong row

**Severity:** Medium
**Disposition:** Implement now

Filtering can hide the selected row while detail still looks it up in all items.
Action messages and spinners in `ItemDetailView` can survive a selection change
and appear on another item. Zero-result search has no contextual empty state.

References:

- `App/Views/ContentView.swift:18-71`
- `App/ViewModels/ScanViewModel.swift:64-67`
- `App/Views/ItemDetailView.swift:9-10`

Required direction: reconcile selection against displayed IDs, key detail state
by item ID, and show query/filter-specific no-results UI with clear controls.

### SOL-041: Counts and labels do not match their predicates

**Severity:** Medium
**Disposition:** Implement now

"Third-party" includes unknown provenance. "Launches at login" uses a generic
startup predicate that includes boot daemons. "Startup items" includes on-demand
advanced surfaces. Cleanup counts can include helper-gated or already completed
items.

References:

- `App/ViewModels/ScanViewModel.swift:18-24`
- `App/ViewModels/ScanViewModel.swift:69-77`
- `App/Views/ContentView.swift:228-255`
- `App/Views/CleanupSheet.swift:17-30`

Required direction: either tighten predicates or use honest labels such as
known non-Apple, starts automatically, items found, and review N issues. Count
pending/actionable and guided-only candidates separately.

### SOL-042: Status is color-only and trust always looks approved

**Severity:** Medium
**Disposition:** Implement now

Tiny red/orange/green dots lack textual labels, a legend, and useful VoiceOver
values. The trust badge always uses `checkmark.seal`, including unsigned,
unknown, or conflicting states. Failure Evidence can contain an item whose row
still looks unknown.

References:

- `App/Views/ContentView.swift:103-124`
- `App/Views/ItemDetailView.swift:48-58`
- `Sources/BootCaptainKit/Engine/DiagnosisEngine.swift:44-47`

Required direction: combine text, shape/symbol, color, tooltip, and accessibility
value; select trust symbols and wording by actual state.

### SOL-043: Narrow windows and larger text can clip key layouts

**Severity:** Medium
**Disposition:** Implement after screenshot/UI-test harness

Four fixed-width stat tiles, nonwrapping badge/trigger stacks, path grids, and a
fixed 560x520 cleanup sheet do not adapt well to a narrow detail column, long
vendor/path text, or accessibility sizes.

References:

- `App/Views/ContentView.swift:249-290`
- `App/Views/ItemDetailView.swift:48-69`
- `App/Views/ItemDetailView.swift:161-172`
- `App/Views/CleanupSheet.swift:21-36`

Required direction: adaptive grids, `ViewThatFits` or wrapping layout, sensible
detail minimums, copy/reveal affordances for long facts, and resizable sheets
with minimum/ideal sizes.

### SOL-044: Coverage UI is initially false, stale during scans, and too raw

**Severity:** Medium
**Disposition:** Implement after scan-generation model

Initial launch can say all zero collectors ran. Rescan shows prior coverage as
current, Boot Audit diagnostic coverage is omitted, enum case names are exposed,
and useful details truncate to one line.

References:

- `App/ViewModels/ScanViewModel.swift:10-44`
- `App/Views/CoverageBanner.swift:10-39`

Required direction: model pending/current/prior generations and timestamps,
merge diagnostic source coverage, map statuses to prose, and provide expandable
full details with remediation.

### SOL-045: Cleanup UX encourages accidental privileged action

**Severity:** High
**Disposition:** Implement now as containment

All pending candidates, including system candidates, are preselected, and Clean
Up is the default Return action. A routine Return can register the helper and
batch root moves. Close/Escape remains available during work.

References:

- `App/Views/CleanupSheet.swift:17-29`
- `App/Views/CleanupSheet.swift:49-53`
- `App/Views/CleanupSheet.swift:137-149`

Required direction: no default selection for mutation, separate explicit admin
confirmation, no default-action key equivalent for privileged work, and prevent
dismissal during the critical transaction window.

### SOL-046: Cleanup history and undo are inconsistent and session-only

**Severity:** Medium
**Disposition:** Design with journal recovery

PR #6 improved in-sheet visibility and retry. Remaining issues include no
rescan after undo, unstable row IDs after result replacement, completed items in
parent counts until scan, disappearance of the cleanup entry point when only
undo history remains, and no history reconstruction after relaunch.

References:

- `App/Services/CleanupService.swift:22-27`
- `App/Services/CleanupService.swift:73-107`
- `App/Views/CleanupSheet.swift:108-129`
- `AGENTS.md:27-30`

Recommended direction: an Actions & Recovery view backed by authoritative
journal records, stable transaction IDs, post-undo queued rescan, and visible
prepared/indeterminate/recovery states.

### SOL-047: Cleanup copy overstates safety and behavior

**Severity:** High trust issue
**Disposition:** Implement now

The sheet says items are moved to a vault even when login records are deleted,
promises every change can be undone despite session-only and lossy undo, and
describes privileged moves as protected/reversible before hardware and recovery
qualification.

References:

- `App/Views/CleanupSheet.swift:61-85`
- `App/Views/ItemDetailView.swift:121-124`
- `AGENTS.md:19-30`

Required direction: describe the exact operation and current limitation for
each candidate. Do not use durable, protected, fully reversible, or every-change
language until evidence supports it.

### SOL-048: Permission prompting lacks a broker and accurate disclosure

**Severity:** Medium
**Disposition:** Product decision, then implement

Initial scan can trigger System Events access without an in-app explanation.
The usage description says the app reads login items, while the same permission
is used to delete and recreate them. Denial has no focused retry/settings flow.

References:

- `App/BootCaptainApp.swift:16-19`
- `Sources/BootCaptainKit/Collectors/SubprocessCollectors.swift:12-18`
- `App/Info.plist:21-23`

Recommended direction: a permission center explaining each source, data scope,
privacy impact, optional mutation use, exact settings destination, and retry.

### SOL-049: First-run audit does not happen and ordinary rescan erases it

**Severity:** High product mismatch
**Disposition:** Product decision before implementation

First launch runs inventory only despite README's first-run audit claim. Audit is
manual, and ordinary rescan replaces diagnosed items with raw items without
warning. Failure Evidence can silently disappear.

References:

- `App/BootCaptainApp.swift:16-29`
- `App/ViewModels/ScanViewModel.swift:35-44`
- `App/Views/ContentView.swift:200-218`
- `README.md:36-40`

Recommended direction: keep fast inventory first, then offer or run a clearly
consented cancellable audit phase. Retain and timestamp prior diagnosis, marking
it stale rather than deleting it.

### SOL-050: CLI parsing and exit behavior are not automation-safe

**Severity:** Medium
**Disposition:** Implement now in small independent steps

Unknown commands/options can exit zero, missing `--out` values are accepted,
flags can become filenames, ANSI output is unconditional, and coverage gaps do
not affect a documented exit policy. Help also says to run under `sudo`, which
the repository explicitly forbids because it changes user and launchd domains
and does not grant FDA.

References:

- `Sources/bootcaptain/main.swift:9-16`
- `Sources/bootcaptain/main.swift:55-80`
- `Sources/bootcaptain/main.swift:84-155`
- `AGENTS.md:37-39`

Required direction: immediately remove the sudo recommendation. Then add strict
argument validation, stderr/nonzero usage errors, `--no-color`, and documented
separate statuses for command failure, partial coverage, and findings.

## Missing product capabilities

### SOL-051: Application and embedded-service discovery is shallow

**Priority:** High
**Disposition:** Design first

Only direct children of a few fixed application roots are scanned, and only
embedded LaunchAgents/LaunchDaemons. Nested apps, bundled LoginItems, Launch
Services/Spotlight inventory, mounted volumes, duplicate copies, and BTM/live
origin roots are missing.

References:

- `Sources/BootCaptainKit/Collectors/LaunchdFileCollector.swift:128-166`

### SOL-052: Modern BTM/ServiceManagement inventory is not usable enough

**Priority:** High
**Disposition:** Hardware first

There is one private text adapter, no adapter disagreement/coherence model, no
store ambiguity handling, no classic bookmark evidence, no parent/embedded
graph, and no reliable join to file/live state. Regular app permission behavior
also needs real fixtures.

### SOL-053: Classic login-item inventory loses important record types

**Priority:** High
**Disposition:** Design and hardware fixtures first

Paths alone lose hidden state, unresolved bookmarks, documents, folders,
volumes, servers, duplicate names, and record identity. These are explicitly
valid login-item kinds in `EVIDENCE.md` B-05.

### SOL-054: Managed background tasks are not modeled from management data

**Priority:** High for managed Macs
**Disposition:** Hardware/managed-device fixtures first

Profiles are listed generically rather than parsing ServiceManagement policy or
DDM background-task configuration/status and correlating it to exact items.

### SOL-055: Cron/at/periodic coverage is incomplete or misleading

**Priority:** Medium
**Disposition:** Design first

The supported current-user `crontab -l` path is not used, `at` has no collector,
and periodic is represented by directory census rather than capability,
schedule, and execution-edge evidence.

### SOL-056: Several advanced and legacy surfaces are absent

**Priority:** Medium, mechanism-dependent
**Disposition:** Product prioritization and evidence per mechanism

Missing or model-only surfaces include arbitrary loaded launchd origins,
unmatched privileged helpers, kernel extensions, family-specific system/app
extension state, rc and login/logout hooks, shell/SSH/PAM startup, Folder
Actions, Dock tile plug-ins, cryptex jobs, persistent environments, Quick Look,
Spotlight, SSO components, browser add-ons, input methods, and scripting
additions. These must not all be described as "starts at login"; each needs its
host and trigger.

### SOL-057: The app has no share-safe export workflow

**Priority:** High
**Disposition:** Implement after SOL-028 privacy model

Export exists only in the CLI. A consumer app needs preview, privacy lint,
scope/build metadata, stable pseudonyms, and a save/share flow that never uploads
automatically.

### SOL-058: There is no scan comparison or local change history

**Priority:** High user value
**Disposition:** Product decision, then design local snapshot schema

Users cannot see new, removed, relabeled, reattributed, newly running, newly
denied, or newly failing items. This is more actionable than another large flat
inventory and can remain fully local.

### SOL-059: App, helper, CLI, and real-output test coverage is insufficient

**Priority:** Critical for release
**Disposition:** Implement test infrastructure now; hardware fixtures over time

There is no App unit/UI test target, helper integration test target, CLI test
target, diagnosis integration suite, adversarial ProcessRunner suite, or tracked
per-build golden corpus. CI compiles the app on one macOS runner but cannot
establish macOS 13/14/15/26 behavior, Intel/Apple silicon, TCC/FDA, multiple
sessions, signing variants, interruption, or recovery.

High-value test groups:

1. Same label across system, users, GUI, and concrete login sessions.
2. Failed/unparsed domain reads preserving unknown state.
3. BTM private bits never populating launchd override or action policy.
4. Unknown/unsigned/invalid and mixed-architecture signing fixtures.
5. Old/unrelated crash and log evidence, time bounds, and loop qualification.
6. Redaction attacks through IDs, labels, commands, URLs, evidence, and homes.
7. Subprocess descendants, large output, timeout, cancellation, and reap.
8. Wrong app/helper identity, user/session, authorization scope, and stale version.
9. Symlink/ACL/hard-link/inode/mount/destination races and exact restore binding.
10. Crash/power interruption at every journal and mutation transition.
11. SwiftUI selection, VoiceOver, keyboard, narrow width, large text, light/dark,
    focus, scan progress, cleanup, and undo.

## Documentation, build, and release issues

### SOL-060: README and in-app claims exceed current implementation

**Severity:** High trust issue
**Disposition:** Implement now

Claims such as everything, exhaustive collection, reconciled state, first-run
audit, fail-closed unknown provenance, fully journaled cleanup, and fully
gap-flagged Linux behavior are not true today. The test-count claim is stale.
README also contradicts itself by describing enabled privileged cleanup and then
saying privileged mutations remain disabled.

References:

- `README.md:3-8`
- `README.md:14-48`
- `README.md:63-70`
- `README.md:101-115`

Required direction: describe the exact implemented prototype scope and known
limits. Marketing can expand only with source and hardware evidence.

### SOL-061: Helper status, version, idle exit, and uninstall are incomplete

**Severity:** High now that registration is reachable
**Disposition:** Implement after privileged operations are disabled

After approval, cached status can remain `.requiresApproval`; `register()` can
observe enabled without publishing it. The client never checks `helperVersion`,
retains its connection, and exposes no UI call site for uninstall. The helper's
run loop never idles out despite plist comments.

References:

- `App/Services/HelperClient.swift:41-64`
- `App/Services/HelperClient.swift:72-127`
- `Helper/main.swift:35-37`
- `Helper/main.swift:181-195`

### SOL-062: Root-only read RPC overclaims FDA and lacks bounded authorization

**Severity:** Medium
**Disposition:** Remove until needed, or design separately

`collectRootOnly` remains available independently of mutation enablement, has no
operation authorization/session binding, forces `hasFullDiskAccess: true`, and
can return unbounded BTM/cron data. Root does not imply FDA. No app call site
currently needs it.

References:

- `Helper/main.swift:90-110`
- `Sources/BootCaptainKit/XPC/HelperProtocol.swift:26-29`

### SOL-063: CI does not enforce the safety contract

**Severity:** High
**Disposition:** Implement now; repository settings also required

CI compiles app/helper but does not assert that unqualified operations remain
disabled, read-only startup cannot register, final artifacts have the intended
requirements/entitlements, or security-sensitive paths received required human
review. PR #6 demonstrates that green CI can enable root mutation without
evidence.

References:

- `.github/workflows/ci.yml:43-89`
- `scripts/verify.sh:34-61`
- `AGENTS.md:61-71`

Required direction: add artifact-level disabled-operation checks, App/Helper
tests, static ID/plist/entitlement consistency checks, CODEOWNERS/protected human
review, and signed positive/negative XPC fixtures. A unit test alone is editable
by the same PR and is not a security approval.

### SOL-064: Release supply-chain inputs are mutable

**Severity:** High
**Disposition:** Implement now in delivery-only PRs

Most actions use mutable major tags, release uses mutable Homebrew/PyPI inputs,
CI invokes unversioned `npx --yes`, checkout can persist write credentials, and
the signing runner later imports release credentials. Compromise of an earlier
tool can cross the signing boundary.

References:

- `.github/workflows/ci.yml:26-38`
- `.github/workflows/ci.yml:65-86`
- `.github/workflows/release.yml:32-69`
- `.github/workflows/release.yml:203-214`

Required direction: pin every action to reviewed commit SHAs, lock and verify
tool versions/hashes, use `persist-credentials: false`, and minimize token scope
and mutable tooling before signing.

### SOL-065: Release provenance and DMG validation are weak

**Severity:** Medium
**Disposition:** Implement now after release-policy decision

Any matching `v*` tag can trigger signing without proving protected-main
ancestry, signed tag provenance, release-script origin, or monotonic build. DMG
creation suppresses every failure with `|| true`, and the final image is not
mounted to verify exact contents, signature, staple, entitlements, Team ID, or
layout.

References:

- `.github/workflows/release.yml:6-15`
- `.github/workflows/release.yml:71-80`
- `.github/workflows/release.yml:180-200`

### SOL-066: Contributor setup recommends global pip installation

**Severity:** Low
**Disposition:** Implement now

README recommends installing Pillow into the active Python environment while CI
already documents externally managed Homebrew Python and creates a virtualenv.

References:

- `README.md:86-95`
- `.github/workflows/ci.yml:72-80`

Required direction: document a local venv or fully managed tool path, and avoid
regenerating icons unless their source changed.

## Delightful and differentiating ideas

These are product ideas, not confirmed defects. They should remain read-only or
clearly evidence-bounded until the action model is qualified.

### Startup Story

A causal timeline or graph from login/boot to mechanism, exact domain, launcher,
payload, owning product, observed execution, exit/crash, and user-visible dialog.
Every edge shows source, time, confidence, and uncertainty. This is the clearest
way to make BootCaptain distinct from a persistence-location checklist.

### Product Family Tree

Group an app, updater, daemon, agent, login helper, extensions, BTM records, and
managed rules under one expandable product while preserving each raw identity.

### Evidence Receipt

Every status badge opens a compact receipt: who observed it, when, on which OS
build and domain/session, with which permission, parser version, warnings, and
why the confidence is not higher.

### Coverage Passport

A per-Mac passport showing OS build and each source as qualified, partial,
denied, unsupported, parser-drifted, or not implemented. Never reduce this to a
generic green seal.

### Demand, Not Startup

A smart view that highlights services registered only for client demand. It
helps users stop treating every launchd definition as login slowdown.

### What Changed

Local snapshots with stable pseudonyms and a calm changelog: newly installed,
removed, moved, signer changed, domain changed, started/stopped, permission lost,
or evidence confidence changed.

### Ghost App Detective

Trace helpers to unmounted volumes, transferred user accounts, old DMGs,
duplicate app copies, stale bundle claims, or replaced executables. Offer reveal
and vendor guidance, not automatic removal.

### System Settings Diff

Explain what Login Items & Extensions currently shows, what BootCaptain sees in
addition, and why records differ. This turns a confusing discrepancy into a
feature.

### Share-safe Support Capsule

Preview exactly what will leave the machine, run privacy lint, use stable local
pseudonyms, and include scope/build/coverage/evidence summaries without raw
paths or automatic upload.

### Next Login Watch

An explicit opt-in observation session with start/stop times, source gap
counters, and no claims about history before activation.

### Mystery Dialog Capture

Opt-in Accessibility capture of the presenting process for an anonymous login
error, clearly separated from the likely upstream startup item.

### Label-churn Detector

Recognize when an updater reappears under a new label or path and explain the
durable vendor-supported off switch rather than offering whack-a-mole deletion.

### Local Annotations

Allow private notes such as recognized, expected, or investigate later. User
annotations must never alter trust or mutation authorization.

### Login Impact Lab

Measured before/after observations and clearly labeled estimates, never a
scare-score and never automatic disabling.

## Recommended implementation sequence

### Batch A: immediate containment

1. SOL-001 and SOL-004: restore one fail-closed qualification boundary, disable
   helper vault mutation, and reject mutation-forbidden/weak candidates.
2. SOL-045 and SOL-047: remove mutation-default keyboard behavior and correct
   cleanup copy while any current-user prototype action remains.
3. SOL-050: remove the forbidden sudo recommendation.
4. SOL-060: make README and in-app scope claims truthful.

### Batch B: narrow correctness fixes

1. SOL-012: decouple private BTM bits from launchd override/effective state.
2. SOL-020: stop hiding services from UUID label syntax.
3. SOL-022: fix catalog boundary and ambiguous Team ID matching.
4. SOL-028: close current redacted-export leaks.
5. SOL-030: make legacy artifacts explicitly uncertain.
6. SOL-040 through SOL-042: fix selection, labels, status semantics, and basic
   accessibility without changing the core architecture.

### Batch C: foundational redesign

1. Domain/session/source identity and reconciliation (SOL-009, SOL-010).
2. Structured parser/collector outcomes and capability coverage (SOL-011,
   SOL-016, SOL-017, SOL-029).
3. Separate source/launcher/payload/signing/management trust (SOL-014, SOL-015,
   SOL-018, SOL-019).
4. Async bounded process runner and scan coordinator (SOL-031 through SOL-033).
5. Typed, time-bounded diagnosis and evidence provenance (SOL-025 through
   SOL-027).
6. Product-family UI and evidence receipts (SOL-037 through SOL-044).

### Batch D: qualified actions only after evidence

1. Per-operation authorization and audit-session binding.
2. Helper-owned target reconstruction and descriptor-safe operations.
3. Durable journal, postconditions, recovery, and persistent history.
4. Signed adversarial helper tests and complete hardware/interruption matrix.
5. Explicit owner/security approval before any operation is re-enabled.

## Final assessment

BootCaptain should not compete by claiming the longest list of persistence
locations. Its strongest opportunity is an honest causal explanation of what is
configured, what macOS authorized, what is registered in which session, what
actually ran, what failed, and exactly how the app knows. If the implementation
matches the rigor already present in `PLAN.md` and `EVIDENCE.md`, that can be both
delightful and unusually trustworthy.
