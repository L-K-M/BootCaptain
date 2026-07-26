import Foundation

/// Derives an item's health from cheap static facts (PLAN.md §7.4). Health is
/// kept separate from trust and from effective state (§10 three-badge model).
public enum HealthDeriver {
    public struct Inputs: Sendable, Equatable {
        /// The resolved trust-path executable exists on disk.
        public var executableExists: Tristate
        /// The executable is a regular file with the exec bit.
        public var executableIsRunnable: Tristate
        /// The plist parsed cleanly.
        public var plistParsed: Tristate
        /// A slice's signature is valid (nil if not checked).
        public var signatureValid: Tristate
        /// Architecture can run here (nil if not checked).
        public var archRunnable: Tristate
        /// Source path points into an unmounted /Volumes/... location.
        public var pointsToMissingVolume: Bool
        /// AssociatedBundleIdentifiers resolve to nothing / owning app gone.
        public var owningAppMissing: Bool
        /// Runtime failure evidence (from diagnosis).
        public var diagnosis: StartupEvidenceState?

        public init(
            executableExists: Tristate = .unknown,
            executableIsRunnable: Tristate = .unknown,
            plistParsed: Tristate = .yes,
            signatureValid: Tristate = .unknown,
            archRunnable: Tristate = .unknown,
            pointsToMissingVolume: Bool = false,
            owningAppMissing: Bool = false,
            diagnosis: StartupEvidenceState? = nil
        ) {
            self.executableExists = executableExists
            self.executableIsRunnable = executableIsRunnable
            self.plistParsed = plistParsed
            self.signatureValid = signatureValid
            self.archRunnable = archRunnable
            self.pointsToMissingVolume = pointsToMissingVolume
            self.owningAppMissing = owningAppMissing
            self.diagnosis = diagnosis
        }
    }

    public static func derive(_ i: Inputs) -> HealthState {
        // Broken: it cannot run as configured.
        if i.plistParsed == .no { return .broken }
        if i.executableExists == .no { return .broken }
        if i.executableIsRunnable == .no { return .broken }
        if i.signatureValid == .no { return .broken }
        if i.archRunnable == .no { return .broken }

        // Runtime failure observed.
        if i.diagnosis == .failureEvidence { return .failing }

        // Possibly orphaned (needs re-scan confirmation per §5).
        if i.pointsToMissingVolume || i.owningAppMissing { return .possiblyOrphaned }

        // Enough positive facts to call it OK.
        if i.executableExists == .yes && i.plistParsed == .yes { return .ok }
        return .unknown
    }
}
