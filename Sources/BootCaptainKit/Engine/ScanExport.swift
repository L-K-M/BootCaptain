import Foundation
import BootCaptainCore

/// JSON/text export of a scan (PLAN.md §10 "redacted JSON/text export"). Paths
/// under user homes are redacted by default so exports are safe to share.
public struct ScanExport: Sendable {
    public init() {}

    public struct ExportedItem: Codable, Sendable {
        var id: String
        var mechanism: String
        var tier: String
        var displayName: String
        var label: String?
        var sourcePath: String?
        var triggers: [String]
        var trust: String
        var health: String
        var actionClass: String
        var effectiveState: String
        var evidenceState: String?
        var vendor: String?
        var product: String?
        var teamID: String?
        var notes: [String]
    }

    public struct ExportedScan: Codable, Sendable {
        var generatedAt: Double
        var itemCount: Int
        var coverageSummary: String
        var coverageGaps: [String]
        var items: [ExportedItem]
    }

    public func json(_ result: ScanResult, redact: Bool = true, homes: [String] = []) throws -> Data {
        let items = result.items.enumerated().map { index, item in
            ExportedItem(
                id: redact ? "item-\(index + 1)" : item.id,
                mechanism: item.mechanism.rawValue,
                tier: item.mechanism.tier.rawValue,
                displayName: redact ? redactedDisplayName(item, homes: homes) : item.displayName,
                label: redact ? redactedLabel(item, homes: homes) : item.label,
                sourcePath: redact ? redactPath(item.sourcePath, homes: homes) : item.sourcePath,
                triggers: item.triggerChips,
                trust: item.trust.rawValue,
                health: item.health.rawValue,
                actionClass: item.actionClass.rawValue,
                effectiveState: item.state.effectivelyEnabled.rawValue,
                evidenceState: item.diagnosis?.state.rawValue,
                vendor: item.attribution.vendorName,
                product: item.attribution.productName,
                teamID: item.attribution.teamIdentifier,
                notes: redact ? redactedNotes(item, homes: homes) : item.notes)
        }
        let scan = ExportedScan(
            generatedAt: result.generatedAt,
            itemCount: result.items.count,
            coverageSummary: result.coverage.bannerSummary,
            coverageGaps: result.coverage.gaps.map { "\($0.collector): \($0.status.rawValue)" },
            items: items)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(scan)
    }

    func redactPath(_ path: String?, homes: [String]) -> String? {
        guard let path else { return nil }
        return redactAllPaths(path, homes: homes)
    }

    func redactedDisplayName(_ item: StartupItem, homes: [String]) -> String {
        if item.mechanism == .cron { return "cron entry" }
        return redactAllPaths(item.displayName, homes: homes)
    }

    func redactedLabel(_ item: StartupItem, homes: [String]) -> String? {
        guard item.mechanism != .cron, let label = item.label else { return nil }
        return redactAllPaths(label, homes: homes)
    }

    func redactedNotes(_ item: StartupItem, homes: [String]) -> [String] {
        item.notes.compactMap { note in
            if item.mechanism == .cron && note.hasPrefix("Command:") { return nil }
            return redactAllPaths(note, homes: homes)
        }
    }

    func redactAllPaths(_ text: String, homes: [String]) -> String {
        var out = text
        for home in homes {
            out = out.replacingOccurrences(of: home, with: "~")
        }
        // Redact any residual /Users/<name> path.
        out = out.replacingOccurrences(
            of: #"/Users/[^/ ]+"#, with: "/Users/<user>", options: .regularExpression)
        return out
    }
}
