import SwiftUI
import BootCaptainCore

/// Shared presentation helpers mapping Core enums to colors, symbols, and text.
enum UIModel {
    static func trustColor(_ t: TrustClass) -> Color {
        switch t {
        case .applePlatform, .appleDistributed: return .secondary
        case .managed: return .purple
        case .developerIDNotarized, .appStore: return .green
        case .developerIDUnnotarized: return .teal
        case .adhoc, .unsigned: return .orange
        case .brokenOrConflicting: return .red
        case .unknown: return .gray
        }
    }

    static func healthColor(_ h: HealthState) -> Color {
        switch h {
        case .ok: return .green
        case .broken: return .red
        case .possiblyOrphaned: return .orange
        case .failing: return .red
        case .unknown: return .gray
        }
    }

    static func healthSymbol(_ h: HealthState) -> String {
        switch h {
        case .ok: return "checkmark.circle.fill"
        case .broken: return "xmark.octagon.fill"
        case .possiblyOrphaned: return "questionmark.circle.fill"
        case .failing: return "exclamationmark.triangle.fill"
        case .unknown: return "minus.circle"
        }
    }

    static func evidenceColor(_ s: StartupEvidenceState) -> Color {
        switch s {
        case .activeNow, .succeeded: return .green
        case .executionObserved, .exitObserved: return .blue
        case .failureEvidence: return .red
        case .notEligibleAtSnapshot, .configuredNotObserved: return .secondary
        case .coverageIncomplete: return .gray
        }
    }

    static func tierTitle(_ tier: Mechanism.Tier) -> String {
        switch tier {
        case .core: return "Startup & Background"
        case .legacy: return "Legacy & Lingering"
        case .advanced: return "Advanced Execution Surface"
        }
    }

    static func actionColor(_ c: ActionClass) -> Color {
        switch c {
        case .reversibleMutation: return .green
        case .guidedAction: return .blue
        case .readOnly: return .secondary
        }
    }
}
