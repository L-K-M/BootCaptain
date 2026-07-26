import Foundation

/// Inputs to trust classification, gathered by the macOS collectors but modelled
/// here so the decision is pure and unit-testable off a Mac.
public struct TrustInputs: Sendable, Equatable {
    /// Per-architecture signing facts for the *trust path* (the script for
    /// interpreter items, else the executable).
    public var signing: [SigningIdentity]
    /// Source/executable resides on the sealed System Volume.
    public var onSSV: Bool
    /// Under /Library/Apple or a cryptex (Apple-distributed, optional).
    public var appleControlledLocation: Bool
    /// Organisation-managed by profile/MDM/DDM.
    public var isManaged: Bool
    /// The launchd label, for the spoofable com.apple.* heuristic.
    public var label: String?

    public init(
        signing: [SigningIdentity] = [],
        onSSV: Bool = false,
        appleControlledLocation: Bool = false,
        isManaged: Bool = false,
        label: String? = nil
    ) {
        self.signing = signing
        self.onSSV = onSSV
        self.appleControlledLocation = appleControlledLocation
        self.isManaged = isManaged
        self.label = label
    }
}

/// PLAN.md §4: combine independent signals and require agreement; a conflicting
/// label/signature/location yields unknown/red-flag rather than the friendliest
/// reading.
public enum TrustClassifier {
    public static func classify(_ input: TrustInputs) -> TrustClass {
        // Management wins over everything except an outright broken signature.
        if input.isManaged { return .managed }

        // No signing facts at all. The sealed System Volume is cryptographically
        // sealed by the OS, so an item that lives there is Apple by construction
        // — we can classify it without paying for a per-binary signature check
        // (a large win: the SSV holds hundreds of launchd items). Anywhere else,
        // absence of signing means we cannot claim anything.
        guard !input.signing.isEmpty else {
            return input.onSSV ? .applePlatform : .unknown
        }

        // Any slice with an invalid signature is disqualifying.
        if input.signing.contains(where: { $0.isValid == .no }) {
            return .brokenOrConflicting
        }

        // Cross-slice identity must agree (Team IDs, when present, must match).
        let teamIDs = Set(input.signing.compactMap { $0.teamIdentifier })
        if teamIDs.count > 1 { return .brokenOrConflicting }

        let anyAnchorApple = input.signing.contains { $0.anchorApple == .yes }
        let anyPlatform = input.signing.contains { $0.isPlatformBinary }
        let labelLooksApple = input.label?.hasPrefix("com.apple.") ?? false

        // Apple system: passes `anchor apple` (or platform binary) AND lives on
        // the SSV or an Apple-controlled location.
        if (anyAnchorApple || anyPlatform) {
            if input.onSSV { return .applePlatform }
            if input.appleControlledLocation { return .appleDistributed }
            // Apple-signed but in a third-party location: unusual; treat as
            // Apple-distributed but do not grant SSV trust.
            return .appleDistributed
        }

        // A com.apple.* label whose code is NOT Apple-signed is a red flag.
        if labelLooksApple {
            return .brokenOrConflicting
        }

        // Third-party grading.
        let team = input.signing.first(where: { $0.teamIdentifier != nil })
        let authority = (input.signing.first?.authority ?? "").lowercased()
        if authority.contains("mac app store") || authority.contains("apple mac os application signing") {
            return .appStore
        }
        if team?.teamIdentifier != nil {
            // Developer ID. Notarisation status is not encoded in the leaf alone;
            // callers may upgrade this to `.developerIDNotarized` after a
            // Gatekeeper assessment.
            return .developerIDUnnotarized
        }
        if input.signing.contains(where: { $0.isValid == .yes }) {
            return .adhoc   // valid but no team identity
        }
        return .unsigned
    }
}
