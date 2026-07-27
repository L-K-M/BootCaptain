import Foundation
import BootCaptainCore

/// Collects Background Task Management records via `sfltool dumpbtm` (PLAN.md
/// §2.2, §3 step 3). Requires root (and likely Full Disk Access); when it can't
/// run it reports a permission gap rather than pretending BTM is empty.
public struct BTMCollector: Collector {
    public let name = "btm-dump"
    public let mechanism: Mechanism = .backgroundTaskManagement

    public init() {}

    public func collect(_ ctx: ScanContext) -> CollectorResult {
        guard ctx.hasRoot else {
            return CollectorResult(items: [], coverage: coverage(
                .deniedPermission, detail: "sfltool dumpbtm needs root (and Full Disk Access)."))
        }
        let res = ctx.runner.run("/usr/bin/sfltool", ["dumpbtm"], timeout: 60)
        guard res.succeeded else {
            return CollectorResult(items: [], coverage: coverage(
                res.status == -1 ? .failed : .deniedPermission,
                detail: "sfltool dumpbtm exited \(res.status): \(res.stderr.prefix(120))"))
        }
        let records = BTMDumpParser.parse(res.stdout)
        let items = records.map { makeItem($0, ctx: ctx) }
        return CollectorResult(items: items, coverage: coverage(.ran, count: items.count))
    }

    func makeItem(_ rec: BTMRecord, ctx: ScanContext) -> StartupItem {
        let mech = rec.mechanism
        let label = rec.identifier ?? rec.name ?? rec.uuid ?? "unknown"

        // Private BTM disposition bits are retained as evidence, but there is no
        // documented effective-state formula. In particular they must not fill
        // the independent launchd override or authorization axes.
        let state = StateAxes(configured: .yes, registered: .yes)

        var attribution = ResolvedAttribution()
        if let dev = rec.developerName {
            // Historical hint only; kept separate from the verified signer.
            attribution.vendorName = dev
            attribution.confidence = .low
        }
        attribution.teamIdentifier = rec.teamIdentifier
        attribution.bundleIdentifier = rec.bundleIdentifier ?? rec.associatedBundleIDs.first

        let path = rec.executablePath ?? rec.url?.replacingOccurrences(of: "file://", with: "")

        var notes = rec.teamIdentifier.map { ["Team ID (from BTM): \($0)"] } ?? []
        if let disposition = rec.dispositionRaw {
            notes.append("Private BTM disposition observed (\(disposition)); not used to derive effective state.")
        }

        return StartupItem(
            id: "btm:\(rec.uuid ?? label)",
            mechanism: mech,
            label: label,
            displayName: rec.name ?? label,
            sourcePath: path,
            state: state,
            attribution: attribution,
            actionClass: mech.tier == .core && (mech == .smAppServiceDaemon || mech == .smAppServiceAgent || mech == .smAppServiceLoginItem)
                ? .guidedAction : .readOnly,
            provenance: [Provenance(
                collector: name, parserVersion: BTMDumpParser.version,
                source: "sfltool dumpbtm", sourceQuality: .reproducible,
                osBuild: ctx.osBuild, permissions: "root")],
            notes: notes)
    }
}
