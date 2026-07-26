import Foundation

/// Every collected fact carries where it came from and how much to trust it.
/// PLAN.md §13 source precedence, encoded as an ordinal so results can be
/// ranked and conflicts surfaced.
public enum SourceQuality: Int, Codable, Sendable, Comparable {
    case appleContract = 5      // public Apple API/schema or current man page
    case appleGuidance = 4      // Apple deployment/security guidance
    case reproducible = 3       // local observation / open-source implementation
    case independent = 2        // independent research
    case anecdote = 1           // forum or vendor claim

    public static func < (lhs: SourceQuality, rhs: SourceQuality) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Confidence rating attached to a derived conclusion (PLAN.md §13 / EVIDENCE.md).
public enum Confidence: String, Codable, Sendable {
    case high
    case medium
    case low
    case open   // sources conflict / not established
}

/// Provenance envelope for a collected observation.
public struct Provenance: Codable, Sendable, Equatable {
    public var collector: String
    public var parserVersion: String
    public var source: String            // e.g. path, command, adapter name
    public var sourceQuality: SourceQuality
    public var osBuild: String?
    public var permissions: String?      // e.g. "user", "root", "root+FDA"
    /// Seconds since 1970 (Date is avoided in Core so values are deterministic).
    public var collectedAt: Double?
    public var parseWarnings: [String]

    public init(
        collector: String,
        parserVersion: String = "1",
        source: String,
        sourceQuality: SourceQuality,
        osBuild: String? = nil,
        permissions: String? = nil,
        collectedAt: Double? = nil,
        parseWarnings: [String] = []
    ) {
        self.collector = collector
        self.parserVersion = parserVersion
        self.source = source
        self.sourceQuality = sourceQuality
        self.osBuild = osBuild
        self.permissions = permissions
        self.collectedAt = collectedAt
        self.parseWarnings = parseWarnings
    }
}
