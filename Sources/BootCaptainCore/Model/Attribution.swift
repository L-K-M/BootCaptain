import Foundation

/// One attribution signal (PLAN.md §5). Vendor and product identity are scored
/// separately; a Team ID is strong *developer-account* evidence but not a
/// unique product identity (EVIDENCE.md A-01).
public struct AttributionSignal: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case bundleContainment      // item lives inside / points into an .app
        case codeSignatureTeamID
        case btmRecord
        case associatedBundleID
        case appleAttributionsPlist // host attributions.plist
        case packageReceipt
        case curatedCatalog
        case labelHeuristic         // reverse-DNS prefix / historical dev name
    }

    public var kind: Kind
    public var vendorName: String?
    public var productName: String?
    public var bundleIdentifier: String?
    public var teamIdentifier: String?
    public var iconPath: String?
    /// 0.0–1.0. Contribution weight toward the resolved identity.
    public var weight: Double
    public var note: String?

    public init(
        kind: Kind,
        vendorName: String? = nil,
        productName: String? = nil,
        bundleIdentifier: String? = nil,
        teamIdentifier: String? = nil,
        iconPath: String? = nil,
        weight: Double,
        note: String? = nil
    ) {
        self.kind = kind
        self.vendorName = vendorName
        self.productName = productName
        self.bundleIdentifier = bundleIdentifier
        self.teamIdentifier = teamIdentifier
        self.iconPath = iconPath
        self.weight = weight
        self.note = note
    }
}

/// The resolved attribution: best-guess identity plus every signal and any
/// conflict, so the UI can show provenance honestly (PLAN.md §5, §10).
public struct ResolvedAttribution: Codable, Sendable, Equatable {
    public var vendorName: String?
    public var productName: String?
    public var bundleIdentifier: String?
    public var teamIdentifier: String?
    public var iconPath: String?
    public var confidence: Confidence
    public var signals: [AttributionSignal]
    /// True when independent signals disagree on vendor/product.
    public var hasConflict: Bool

    public init(
        vendorName: String? = nil,
        productName: String? = nil,
        bundleIdentifier: String? = nil,
        teamIdentifier: String? = nil,
        iconPath: String? = nil,
        confidence: Confidence = .low,
        signals: [AttributionSignal] = [],
        hasConflict: Bool = false
    ) {
        self.vendorName = vendorName
        self.productName = productName
        self.bundleIdentifier = bundleIdentifier
        self.teamIdentifier = teamIdentifier
        self.iconPath = iconPath
        self.confidence = confidence
        self.signals = signals
        self.hasConflict = hasConflict
    }

    /// Best display title, honest when nothing resolved.
    public var displayTitle: String {
        if let p = productName, !p.isEmpty { return p }
        if let v = vendorName, !v.isEmpty { return v }
        return "Unknown item"
    }
}
