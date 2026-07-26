import Foundation

/// The safe evidence states from PLAN.md §7. Diagnosis reports **positive
/// evidence with confidence**; it never turns absence of telemetry into
/// "never attempted", and only claims `succeeded` on an item-specific success
/// signal.
public enum StartupEvidenceState: String, Codable, Sendable {
    case activeNow            // a current process/service state was observed
    case executionObserved    // a timestamped launch/exec event; outcome unknown
    case exitObserved         // an exit status/signal was observed, uninterpreted
    case failureEvidence      // missing target, denied exec, crash, or restart loop
    case notEligibleAtSnapshot// disabled/session-ineligible now; no history claim
    case configuredNotObserved// exists, but the window has no matching evidence
    case coverageIncomplete   // permissions/retention/parser/redaction/monitor gap
    case succeeded            // item-specific success signal only

    public var displayName: String {
        switch self {
        case .activeNow: return "Active now"
        case .executionObserved: return "Execution observed"
        case .exitObserved: return "Exit observed"
        case .failureEvidence: return "Failure evidence"
        case .notEligibleAtSnapshot: return "Not eligible at snapshot"
        case .configuredNotObserved: return "Configured, not observed"
        case .coverageIncomplete: return "Coverage incomplete"
        case .succeeded: return "Succeeded"
        }
    }
}

/// A single piece of correlated evidence about an item's startup behaviour.
public struct EvidenceItem: Codable, Sendable, Equatable {
    public enum Origin: String, Codable, Sendable {
        case unifiedLog
        case launchctlPrint
        case crashReport
        case staticCheck
        case processState
        case prospectiveMonitor
    }

    public var origin: Origin
    public var summary: String
    /// Verbatim observation (e.g. "last reported status 78", "14 runs"),
    /// presented without automatic interpretation (PLAN.md §7).
    public var rawObservation: String?
    public var confidence: Confidence
    /// Seconds since 1970, if the evidence is timestamped.
    public var timestamp: Double?

    public init(
        origin: Origin,
        summary: String,
        rawObservation: String? = nil,
        confidence: Confidence = .medium,
        timestamp: Double? = nil
    ) {
        self.origin = origin
        self.summary = summary
        self.rawObservation = rawObservation
        self.confidence = confidence
        self.timestamp = timestamp
    }
}

/// The diagnosis for one item: a derived safe state plus its evidence and the
/// coverage gaps that qualify it.
public struct Diagnosis: Codable, Sendable, Equatable {
    public var state: StartupEvidenceState
    public var evidence: [EvidenceItem]
    public var confidence: Confidence
    public var coverageGaps: [String]

    public init(
        state: StartupEvidenceState,
        evidence: [EvidenceItem] = [],
        confidence: Confidence = .low,
        coverageGaps: [String] = []
    ) {
        self.state = state
        self.evidence = evidence
        self.confidence = confidence
        self.coverageGaps = coverageGaps
    }
}
