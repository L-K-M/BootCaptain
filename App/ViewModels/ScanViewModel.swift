import Foundation
import SwiftUI
import BootCaptainCore
import BootCaptainKit

/// Drives scanning and diagnosis off the main actor and publishes results for
/// the UI. Grouping and filtering live here so the views stay declarative.
@MainActor
final class ScanViewModel: ObservableObject {
    @Published var items: [StartupItem] = []
    @Published var coverage: CoverageReport = CoverageReport()
    @Published var isScanning = false
    @Published var lastScan: Date?
    @Published var searchText = "" {
        didSet { reconcileSelection() }
    }
    @Published var filter: Filter = .all {
        didSet { reconcileSelection() }
    }
    @Published var selection: StartupItem.ID?

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case thirdParty = "Third-party"
        case launchesAtLogin = "Launches at login"
        case orphans = "Orphaned / broken"
        case failing = "Failure evidence"
        var id: String { rawValue }
    }

    func scan(diagnose: Bool) {
        guard !isScanning else { return }
        isScanning = true
        Task.detached(priority: .userInitiated) {
            let ctx = SystemEnvironment.makeContext()
            let raw = BootCaptainKit.Scanner().scan(ctx, now: Date().timeIntervalSince1970)
            // Bind an immutable result so the MainActor closure captures a Sendable
            // value, not a mutable variable (Swift 6 concurrency safety).
            let result = diagnose
                ? ScanResult(items: DiagnosisEngine().diagnose(items: raw.items, ctx: ctx),
                             coverage: raw.coverage, generatedAt: raw.generatedAt)
                : raw
            await MainActor.run {
                self.items = result.items
                self.reconcileSelection()
                self.coverage = result.coverage
                self.isScanning = false
                self.lastScan = Date()
            }
        }
    }

    /// Items after search + filter, grouped by tier for the sidebar/list.
    var filteredItems: [StartupItem] {
        items.filter { item in
            matchesFilter(item) && matchesSearch(item)
        }
    }

    var groupedByTier: [(Mechanism.Tier, [StartupItem])] {
        let groups = Dictionary(grouping: filteredItems, by: { $0.mechanism.tier })
        let order: [Mechanism.Tier] = [.core, .legacy, .advanced]
        return order.compactMap { tier in
            guard let items = groups[tier], !items.isEmpty else { return nil }
            return (tier, items.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending })
        }
    }

    func displayedItem(id: StartupItem.ID?) -> StartupItem? {
        guard let id else { return nil }
        return filteredItems.first { $0.id == id }
    }

    private func reconcileSelection() {
        guard let selection else { return }
        if !items.contains(where: {
            $0.id == selection && matchesFilter($0) && matchesSearch($0)
        }) {
            self.selection = nil
        }
    }

    private func matchesFilter(_ item: StartupItem) -> Bool {
        switch filter {
        case .all: return true
        case .thirdParty:
            return !(item.trust == .applePlatform || item.trust == .appleDistributed)
        case .launchesAtLogin: return item.triggers.runsAtStartup
        case .orphans: return item.health == .possiblyOrphaned || item.health == .broken
        case .failing: return item.diagnosis?.state == .failureEvidence
        }
    }

    private func matchesSearch(_ item: StartupItem) -> Bool {
        guard !searchText.isEmpty else { return true }
        let needle = searchText.lowercased()
        return item.displayName.lowercased().contains(needle)
            || (item.label?.lowercased().contains(needle) ?? false)
            || (item.attribution.vendorName?.lowercased().contains(needle) ?? false)
            || (item.sourcePath?.lowercased().contains(needle) ?? false)
    }
}
