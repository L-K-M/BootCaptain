import Foundation

/// Provenance / trust classification, kept **separate** from health and from
/// effective state (PLAN.md §4, §10 three-badge model).
public enum TrustClass: String, Codable, Sendable {
    /// Valid Apple platform/system code on the SSV, cryptex, or /Library/Apple.
    case applePlatform
    /// Apple-distributed but optional (Rosetta etc.) — shown under Apple, own row.
    case appleDistributed
    /// Organisation-managed by profile/MDM/DDM — read-only, direct to admin.
    case managed
    /// Valid Developer ID, notarised.
    case developerIDNotarized
    /// Valid Developer ID, notarisation not established.
    case developerIDUnnotarized
    /// Mac App Store distribution.
    case appStore
    /// Ad-hoc signed only (no team identity).
    case adhoc
    /// Unsigned.
    case unsigned
    /// Signature present but invalid/tampered, or signals conflict.
    case brokenOrConflicting
    /// Not yet evaluated.
    case unknown

    /// PLAN.md §6.2: BootCaptain hard-refuses to mutate Apple/system and
    /// organisation-managed items, and anything whose provenance is unknown or
    /// conflicting. This is independent of SIP.
    public var isMutationForbidden: Bool {
        switch self {
        case .applePlatform, .appleDistributed, .managed, .brokenOrConflicting, .unknown:
            return true
        case .developerIDNotarized, .developerIDUnnotarized, .appStore, .adhoc, .unsigned:
            return false
        }
    }

    public var displayName: String {
        switch self {
        case .applePlatform: return "macOS system"
        case .appleDistributed: return "Apple (optional component)"
        case .managed: return "Managed by your organization"
        case .developerIDNotarized: return "Identified developer (notarized)"
        case .developerIDUnnotarized: return "Identified developer"
        case .appStore: return "Mac App Store"
        case .adhoc: return "Ad-hoc signed"
        case .unsigned: return "Unsigned"
        case .brokenOrConflicting: return "Broken or conflicting signature"
        case .unknown: return "Unknown"
        }
    }
}

/// Health, separate from trust: is this item working?
public enum HealthState: String, Codable, Sendable {
    case ok
    /// Executable missing, plist malformed, signature broken, arch mismatch.
    case broken
    /// Owning app / target appears gone (needs re-scan confirmation → §5).
    case possiblyOrphaned
    /// Observed failing / crash-looping at runtime.
    case failing
    case unknown

    public var displayName: String {
        switch self {
        case .ok: return "OK"
        case .broken: return "Broken"
        case .possiblyOrphaned: return "Possibly orphaned"
        case .failing: return "Failing"
        case .unknown: return "Unknown"
        }
    }
}

/// Per-architecture signing facts, collected before trusting metadata (§4/§5).
public struct SigningIdentity: Codable, Sendable, Equatable {
    public var architecture: String?
    public var teamIdentifier: String?
    public var signingIdentifier: String?
    /// Common name of the leaf certificate (e.g. "Developer ID Application: …").
    public var authority: String?
    /// Organisation from the leaf certificate.
    public var vendorName: String?
    public var isPlatformBinary: Bool
    public var cdHash: String?
    /// Result of an explicit validity check (`SecStaticCodeCheckValidity`).
    public var isValid: Tristate
    public var anchorApple: Tristate          // passes `anchor apple`
    public var anchorAppleGeneric: Tristate   // passes `anchor apple generic`

    public init(
        architecture: String? = nil,
        teamIdentifier: String? = nil,
        signingIdentifier: String? = nil,
        authority: String? = nil,
        vendorName: String? = nil,
        isPlatformBinary: Bool = false,
        cdHash: String? = nil,
        isValid: Tristate = .unknown,
        anchorApple: Tristate = .unknown,
        anchorAppleGeneric: Tristate = .unknown
    ) {
        self.architecture = architecture
        self.teamIdentifier = teamIdentifier
        self.signingIdentifier = signingIdentifier
        self.authority = authority
        self.vendorName = vendorName
        self.isPlatformBinary = isPlatformBinary
        self.cdHash = cdHash
        self.isValid = isValid
        self.anchorApple = anchorApple
        self.anchorAppleGeneric = anchorAppleGeneric
    }
}
