import Foundation

/// Correlates collected evidence into one of PLAN.md §7's **safe** states. The
/// cardinal rule: absence of telemetry never becomes "never attempted", and
/// `succeeded` is only used on an item-specific success signal (never claimed
/// here — no generic success signal exists).
public enum SafeStateDeriver {
    /// Inputs describing what was observed for one item.
    public struct Inputs: Sendable, Equatable {
        public var state: StateAxes
        public var evidence: [EvidenceItem]
        /// Whether the diagnostic window had usable coverage at all (log
        /// readable, reports accessible, etc.). When false, everything is
        /// `coverageIncomplete`.
        public var hasUsableCoverage: Bool
        public var coverageGaps: [String]

        public init(
            state: StateAxes,
            evidence: [EvidenceItem] = [],
            hasUsableCoverage: Bool = true,
            coverageGaps: [String] = []
        ) {
            self.state = state
            self.evidence = evidence
            self.hasUsableCoverage = hasUsableCoverage
            self.coverageGaps = coverageGaps
        }
    }

    public static func derive(_ input: Inputs) -> Diagnosis {
        let ev = input.evidence

        // 1. Running/loaded right now is the strongest positive.
        if input.state.running == .yes || input.state.loaded == .yes {
            return Diagnosis(
                state: .activeNow,
                evidence: ev,
                confidence: .high,
                coverageGaps: input.coverageGaps)
        }

        // 2. Concrete failure evidence.
        if ev.contains(where: { isFailure($0) }) {
            return Diagnosis(
                state: .failureEvidence,
                evidence: ev,
                confidence: strongestConfidence(ev, where: isFailure),
                coverageGaps: input.coverageGaps)
        }

        // 3. An exit was observed but not interpreted.
        if ev.contains(where: { $0.summary.localizedCaseInsensitiveContains("exit") }) {
            return Diagnosis(
                state: .exitObserved, evidence: ev, confidence: .medium,
                coverageGaps: input.coverageGaps)
        }

        // 4. A launch/exec event was observed; outcome unknown.
        if ev.contains(where: { $0.origin == .unifiedLog || $0.origin == .processState }) {
            return Diagnosis(
                state: .executionObserved, evidence: ev, confidence: .medium,
                coverageGaps: input.coverageGaps)
        }

        // 5. Deliberately not eligible now.
        if input.state.override == .disabled {
            return Diagnosis(
                state: .notEligibleAtSnapshot,
                evidence: ev, confidence: .high,
                coverageGaps: input.coverageGaps)
        }

        // 6. No coverage at all → cannot conclude.
        if !input.hasUsableCoverage {
            return Diagnosis(
                state: .coverageIncomplete, evidence: ev, confidence: .high,
                coverageGaps: input.coverageGaps.isEmpty
                    ? ["No accessible diagnostic evidence for the window"]
                    : input.coverageGaps)
        }

        // 7. Configured but nothing matched in an otherwise-covered window.
        if input.state.configured == .yes {
            return Diagnosis(
                state: .configuredNotObserved, evidence: ev, confidence: .medium,
                coverageGaps: input.coverageGaps)
        }

        return Diagnosis(
            state: .coverageIncomplete, evidence: ev, confidence: .low,
            coverageGaps: input.coverageGaps)
    }

    // A crash, missing target, denied exec, or qualified restart loop.
    private static func isFailure(_ e: EvidenceItem) -> Bool {
        if e.origin == .crashReport { return true }
        let s = e.summary.lowercased()
        return s.contains("could not initialize")
            || s.contains("missing")
            || s.contains("not found")
            || s.contains("denied")
            || s.contains("crash")
            || s.contains("respawn")   // throttled restart loop
            || s.contains("abnormal")
    }

    private static func strongestConfidence(
        _ ev: [EvidenceItem], where predicate: (EvidenceItem) -> Bool
    ) -> Confidence {
        let matches = ev.filter(predicate)
        if matches.contains(where: { $0.confidence == .high }) { return .high }
        if matches.contains(where: { $0.confidence == .medium }) { return .medium }
        return .low
    }
}
