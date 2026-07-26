import Foundation

/// Turns a bag of attribution signals into a resolved identity, scoring vendor
/// and product **separately** and surfacing conflicts (PLAN.md §5). Higher-weight
/// signals win; disagreement among strong signals sets `hasConflict`.
public enum AttributionScorer {
    /// Default weights per signal kind (PLAN.md §5 ordered pipeline).
    public static func defaultWeight(for kind: AttributionSignal.Kind) -> Double {
        switch kind {
        case .bundleContainment: return 1.0
        case .btmRecord: return 0.9
        case .associatedBundleID: return 0.85
        case .codeSignatureTeamID: return 0.8
        case .appleAttributionsPlist: return 0.6
        case .packageReceipt: return 0.6
        case .curatedCatalog: return 0.5
        case .labelHeuristic: return 0.2
        }
    }

    public static func resolve(_ signals: [AttributionSignal]) -> ResolvedAttribution {
        guard !signals.isEmpty else { return ResolvedAttribution() }

        // Pick the best product name and vendor name by weight.
        let byWeight = signals.sorted { $0.weight > $1.weight }

        let product = byWeight.first { $0.productName?.isEmpty == false }
        let vendor = byWeight.first { $0.vendorName?.isEmpty == false }
        let bundle = byWeight.first { $0.bundleIdentifier?.isEmpty == false }
        let team = byWeight.first { $0.teamIdentifier?.isEmpty == false }
        let icon = byWeight.first { $0.iconPath?.isEmpty == false }

        // Conflict detection: two strong (>=0.6) signals naming *different*
        // vendors, or different Team IDs.
        let strongVendors = Set(signals
            .filter { $0.weight >= 0.6 }
            .compactMap { $0.vendorName?.lowercased() }
            .filter { !$0.isEmpty })
        let teamIDs = Set(signals.compactMap { $0.teamIdentifier }.filter { !$0.isEmpty })
        let hasConflict = strongVendors.count > 1 || teamIDs.count > 1

        // Confidence from the strongest contributing signal, downgraded by conflict.
        let topWeight = byWeight.first?.weight ?? 0
        var confidence: Confidence
        switch topWeight {
        case 0.85...: confidence = .high
        case 0.6..<0.85: confidence = .medium
        default: confidence = .low
        }
        if hasConflict { confidence = confidence == .high ? .medium : .low }

        return ResolvedAttribution(
            vendorName: vendor?.vendorName,
            productName: product?.productName,
            bundleIdentifier: bundle?.bundleIdentifier,
            teamIdentifier: team?.teamIdentifier,
            iconPath: icon?.iconPath,
            confidence: confidence,
            signals: signals,
            hasConflict: hasConflict
        )
    }
}
