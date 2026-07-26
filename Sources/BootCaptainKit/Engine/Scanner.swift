import Foundation
import BootCaptainCore

/// The complete result of a scan.
public struct ScanResult: Sendable {
    public var items: [StartupItem]
    public var coverage: CoverageReport
    public var generatedAt: Double
    public init(items: [StartupItem], coverage: CoverageReport, generatedAt: Double) {
        self.items = items
        self.coverage = coverage
        self.generatedAt = generatedAt
    }
}

/// Orchestrates collection, reconciliation, trust classification, attribution,
/// health, and (optionally) diagnosis (PLAN.md §3, §10). It never mutates.
public struct Scanner: Sendable {
    let collectors: [Collector]
    let stateCollector: LaunchctlStateCollector
    let signing: CodeSigningInspector
    let attributionEngine: AttributionEngine
    let health: StaticHealthChecker

    public init(
        collectors: [Collector]? = nil,
        stateCollector: LaunchctlStateCollector = LaunchctlStateCollector(),
        signing: CodeSigningInspector = CodeSigningInspector(),
        attributionEngine: AttributionEngine = AttributionEngine(),
        health: StaticHealthChecker = StaticHealthChecker()
    ) {
        self.collectors = collectors ?? Scanner.defaultCollectors
        self.stateCollector = stateCollector
        self.signing = signing
        self.attributionEngine = attributionEngine
        self.health = health
    }

    public static let defaultCollectors: [Collector] = [
        LaunchdFileCollector(),
        BTMCollector(),
        LoginItemsCollector(),
        WindowRestorationCollector(),
        CronCollector(),
        SystemExtensionCollector(),
        PluginKitCollector(),
        ProfilesCollector(),
        LegacyCensusCollector(),
    ]

    public func scan(_ ctx: ScanContext, now: Double) -> ScanResult {
        var coverages: [CollectorCoverage] = []

        // 1. Live launchd state.
        let state = stateCollector.collect(ctx)
        coverages.append(contentsOf: state.coverage)

        // 2. Run every collector.
        var raw: [StartupItem] = []
        for collector in collectors {
            let result = collector.collect(ctx)
            raw.append(contentsOf: result.items)
            coverages.append(result.coverage)
        }

        // 3. Reconcile + enrich each item.
        var byID: [String: StartupItem] = [:]
        for var item in raw {
            reconcileState(&item, state: state)
            classifyTrust(&item, ctx: ctx)
            enrichAttribution(&item)
            deriveHealth(&item)
            decideAction(&item)
            // Dedup: prefer the richer record (more provenance) on collision.
            if let existing = byID[item.id] {
                byID[item.id] = merge(existing, item)
            } else {
                byID[item.id] = item
            }
        }

        // 4. Detect loaded-but-unmatched services (bootstrapped from odd paths).
        let knownLabels = Set(byID.values.compactMap(\.label))
        for (label, svc) in state.services where !knownLabels.contains(label) {
            if label.hasPrefix("com.apple.") { continue }  // system noise
            var item = StartupItem(
                id: "launchd-live:\(label)",
                mechanism: .launchDaemon,
                label: label, displayName: label,
                sourcePath: svc.path,
                state: StateAxes(configured: svc.path == nil ? .unknown : .yes,
                                 loaded: .yes,
                                 running: Tristate(svc.pid != nil)),
                actionClass: .readOnly,
                provenance: [Provenance(collector: "launchctl-state",
                    source: "launchctl print", sourceQuality: .reproducible,
                    osBuild: ctx.osBuild)],
                notes: ["Loaded in launchd but not found in a canonical directory — worth a look."])
            classifyTrust(&item, ctx: ctx)
            byID[item.id] = item
        }

        let items = byID.values.sorted { lhs, rhs in
            if lhs.mechanism.tier != rhs.mechanism.tier {
                return tierRank(lhs.mechanism.tier) < tierRank(rhs.mechanism.tier)
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        return ScanResult(items: Array(items),
                          coverage: CoverageReport(collectors: coverages),
                          generatedAt: now)
    }

    // MARK: enrichment steps

    func reconcileState(_ item: inout StartupItem, state: LaunchctlState) {
        guard let label = item.label else { return }
        if let svc = state.services[label] {
            item.state.loaded = .yes
            item.state.running = Tristate(svc.pid != nil)
        } else if item.mechanism == .launchDaemon || item.mechanism == .launchAgent {
            item.state.loaded = .no
            item.state.running = .no
        }
        // Override state from the domain this item lives in.
        let domain = item.domain ?? "system"
        item.state.override = state.overrideState(domain: domain, label: label)
    }

    func classifyTrust(_ item: inout StartupItem, ctx: ScanContext) {
        // Sign the trust path (script for interpreter items, else the exec).
        if item.signing.isEmpty, let path = item.recipe?.trustPath ?? item.sourcePath {
            item.signing = signing.inspect(path: path)
        }
        let onSSV = (item.sourcePath?.hasPrefix("/System/") ?? false)
        let appleControlled = (item.sourcePath?.hasPrefix("/Library/Apple/") ?? false)
            || (item.sourcePath?.contains("/Cryptexes/") ?? false)
        let managed = item.trust == .managed || item.mechanism == .configurationProfile
            || item.mechanism == .managedBackgroundTask
        let input = TrustInputs(signing: item.signing, onSSV: onSSV,
                                appleControlledLocation: appleControlled,
                                isManaged: managed, label: item.label)
        // Don't override an explicit managed classification from the collector.
        if item.trust == .unknown || item.trust == .managed {
            item.trust = TrustClassifier.classify(input)
        }
    }

    func enrichAttribution(_ item: inout StartupItem) {
        let (resolved, catalog) = attributionEngine.attribute(item)
        // Keep the richer of resolved vs. pre-existing.
        if resolved.confidence != .low || item.attribution.signals.isEmpty {
            item.attribution = resolved
        }
        if let entry = catalog {
            item.notes.append("\(entry.product): \(entry.purpose)")
            if item.actionClass == .reversibleMutation {
                item.notes.append("If disabled: \(entry.disableConsequence)")
            }
            if let off = entry.vendorOffSwitch {
                item.notes.append("Vendor off-switch: \(off)")
            }
        }
        if !item.attribution.displayTitle.isEmpty, item.attribution.displayTitle != "Unknown item" {
            item.displayName = item.attribution.displayTitle
        }
    }

    func deriveHealth(_ item: inout StartupItem) {
        guard !item.isInert else { item.health = .ok; return }
        let inputs = health.check(item)
        item.health = HealthDeriver.derive(inputs)
    }

    func decideAction(_ item: inout StartupItem) {
        // Collectors set a starting class; the safety policy is the final word.
        let decision = SafetyPolicy.decide(
            mechanism: item.mechanism, trust: item.trust, recipe: item.recipe,
            overrideState: item.state.override, label: item.label, isInert: item.isInert)
        // Never upgrade a collector's guided/read-only to reversible unless the
        // policy independently allows it.
        if decision.actionClass == .reversibleMutation && item.actionClass == .guidedAction {
            // Collector already restricted this (e.g. SMAppService item) — respect it.
            return
        }
        item.actionClass = decision.actionClass
        if let reason = decision.reason { item.notes.append(reason) }
    }

    func merge(_ a: StartupItem, _ b: StartupItem) -> StartupItem {
        var out = a.provenance.count >= b.provenance.count ? a : b
        out.provenance = a.provenance + b.provenance
        // Prefer any concrete state signal.
        if out.state.running == .unknown { out.state.running = a.state.running == .unknown ? b.state.running : a.state.running }
        return out
    }

    func tierRank(_ tier: Mechanism.Tier) -> Int {
        switch tier { case .core: return 0; case .legacy: return 1; case .advanced: return 2 }
    }
}
