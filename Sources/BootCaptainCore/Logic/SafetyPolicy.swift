import Foundation

/// The immutable safety policy (PLAN.md §6.2). It fails **closed**: anything
/// Apple/system, organisation-managed, unknown, conflicting, or unresolved is
/// never mutated. A remote catalog can never weaken this, and it does not depend
/// on SIP.
public enum SafetyPolicy {
    /// A conservative built-in deny-list of critical Apple service labels
    /// (defense in depth — PLAN.md §6.2 — never the primary boundary).
    public static let criticalAppleLabels: Set<String> = [
        "com.apple.opendirectoryd", "com.apple.securityd", "com.apple.trustd",
        "com.apple.tccd", "com.apple.WindowServer", "com.apple.loginwindow",
        "com.apple.logd", "com.apple.cfprefsd.xpc.daemon", "com.apple.configd",
        "com.apple.powerd", "com.apple.diskarbitrationd", "com.apple.coreservicesd",
        "com.apple.launchservicesd", "com.apple.mDNSResponder",
        "com.apple.fseventsd", "com.apple.watchdogd", "com.apple.apsd",
        "com.apple.mobile.softwareupdated", "com.apple.backgroundtaskmanagementd",
    ]

    public struct Decision: Sendable, Equatable {
        public var actionClass: ActionClass
        /// Why a mutation is forbidden or must be guided, for the UI.
        public var reason: String?
        public init(actionClass: ActionClass, reason: String? = nil) {
            self.actionClass = actionClass
            self.reason = reason
        }
    }

    /// Decide the action class for an item. Only mechanisms whose whole lifecycle
    /// has been qualified (`isMechanismQualified`) can reach `reversibleMutation`;
    /// everything else is at most `guidedAction`.
    public static func decide(
        mechanism: Mechanism,
        trust: TrustClass,
        recipe: LaunchRecipe?,
        overrideState: OverrideState,
        label: String?,
        isInert: Bool
    ) -> Decision {
        if isInert {
            return Decision(actionClass: .readOnly, reason: "Inert on this macOS; nothing to disable.")
        }
        if trust.isMutationForbidden {
            return Decision(actionClass: .readOnly,
                            reason: forbiddenReason(trust))
        }
        if let label, criticalAppleLabels.contains(label) {
            return Decision(actionClass: .readOnly,
                            reason: "Critical system service; protected by policy.")
        }
        // Unresolved exec chains cannot be safely inverted.
        if let recipe, recipe.isUnresolved {
            return Decision(actionClass: .readOnly,
                            reason: "Launch target could not be resolved; failing closed.")
        }
        // Unknown launchd override pre-state blocks mutation (no safe inverse).
        if requiresOverride(mechanism), overrideState == .unknown {
            return Decision(actionClass: .guidedAction,
                            reason: "Current override state is unknown; cannot establish a safe undo.")
        }
        if isMechanismQualified(mechanism) {
            return Decision(actionClass: .reversibleMutation)
        }
        return Decision(actionClass: .guidedAction,
                        reason: "This mechanism is disabled via the owning app or System Settings.")
    }

    /// Mechanisms for which BootCaptain ships a tested, behaviourally reversible
    /// action. Everything else is guided/read-only until its matrix passes.
    public static func isMechanismQualified(_ mechanism: Mechanism) -> Bool {
        switch mechanism {
        case .launchDaemon, .launchAgent, .cron:
            return true
        default:
            return false
        }
    }

    private static func requiresOverride(_ mechanism: Mechanism) -> Bool {
        mechanism == .launchDaemon || mechanism == .launchAgent
    }

    private static func forbiddenReason(_ trust: TrustClass) -> String {
        switch trust {
        case .applePlatform, .appleDistributed:
            return "Apple system software; managed by macOS."
        case .managed:
            return "Managed by your organization; contact your administrator."
        case .brokenOrConflicting:
            return "Signature is broken or signals conflict; refusing to act."
        case .unknown:
            return "Provenance could not be established; failing closed."
        default:
            return "Protected by policy."
        }
    }
}
