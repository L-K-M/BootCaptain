import Foundation

/// PLAN.md §3/§10: skipped collectors, denied permissions, unsupported schemas
/// and unknown types are **first-class results**, surfaced in a persistent
/// coverage banner rather than silently dropped.
public struct CollectorCoverage: Codable, Sendable, Equatable, Identifiable {
    public enum Status: String, Codable, Sendable {
        case ran                 // completed with results
        case ranEmpty            // completed, no items on this system
        case skippedUnsupported  // mechanism not present on this OS build
        case deniedPermission    // needs root/FDA/TCC not granted
        case failed              // adapter error
        case partial             // some sources parsed, some failed
        case notRun              // deliberately not run in this phase/mode
    }

    public var collector: String
    public var mechanism: Mechanism
    public var status: Status
    public var itemCount: Int
    public var detail: String?

    public var id: String { collector }

    public init(
        collector: String,
        mechanism: Mechanism,
        status: Status,
        itemCount: Int = 0,
        detail: String? = nil
    ) {
        self.collector = collector
        self.mechanism = mechanism
        self.status = status
        self.itemCount = itemCount
        self.detail = detail
    }

    public var isGap: Bool {
        switch status {
        case .ran, .ranEmpty: return false
        case .skippedUnsupported, .deniedPermission, .failed, .partial, .notRun:
            return true
        }
    }
}

/// The aggregate coverage report for a scan.
public struct CoverageReport: Codable, Sendable, Equatable {
    public var collectors: [CollectorCoverage]

    public init(collectors: [CollectorCoverage] = []) {
        self.collectors = collectors
    }

    public var gaps: [CollectorCoverage] { collectors.filter(\.isGap) }
    public var totalItems: Int { collectors.reduce(0) { $0 + $1.itemCount } }

    /// A short banner sentence for the UI.
    public var bannerSummary: String {
        let g = gaps
        if g.isEmpty {
            return "All \(collectors.count) collectors ran."
        }
        let denied = g.filter { $0.status == .deniedPermission }.count
        var parts = ["\(g.count) of \(collectors.count) collectors have gaps"]
        if denied > 0 { parts.append("\(denied) need additional permissions") }
        return parts.joined(separator: "; ") + "."
    }
}
