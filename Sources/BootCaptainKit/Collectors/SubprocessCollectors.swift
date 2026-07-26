import Foundation
import BootCaptainCore

/// Login items ("Open at Login") via System Events. Read-only enumeration here;
/// mutation of these is the one AppleScript path (PLAN.md §6.1) and is handled
/// by the ActionRunner, not the collector.
public struct LoginItemsCollector: Collector {
    public let name = "login-items"
    public let mechanism: Mechanism = .classicLoginItem
    public init() {}

    public func collect(_ ctx: ScanContext) -> CollectorResult {
        let script = "tell application \"System Events\" to get the path of every login item"
        let res = ctx.runner.run("/usr/bin/osascript", ["-e", script], timeout: 20)
        guard res.succeeded else {
            return CollectorResult(items: [], coverage: coverage(
                .deniedPermission, detail: "System Events automation not authorized."))
        }
        let paths = res.stdout
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let items = paths.map { path -> StartupItem in
            let name = (path as NSString).lastPathComponent
            return StartupItem(
                id: "classicLoginItem:\(path)",
                mechanism: .classicLoginItem,
                label: name, displayName: name, sourcePath: path,
                triggers: [.speculative],
                state: StateAxes(configured: .yes, registered: .yes, authorized: .yes),
                actionClass: .reversibleMutation,
                provenance: [Provenance(collector: self.name, source: "System Events",
                                        sourceQuality: .reproducible, osBuild: ctx.osBuild)])
        }
        return CollectorResult(items: items, coverage: coverage(
            items.isEmpty ? .ranEmpty : .ran, count: items.count))
    }
}

/// System / Network / Endpoint Security / DriverKit extensions via
/// `systemextensionsctl list`. Read-only + guided (never `uninstall`, which
/// needs SIP off — PLAN.md §2.4/§6.1).
public struct SystemExtensionCollector: Collector {
    public let name = "system-extensions"
    public let mechanism: Mechanism = .systemExtension
    public init() {}

    public func collect(_ ctx: ScanContext) -> CollectorResult {
        let res = ctx.runner.run("/usr/bin/systemextensionsctl", ["list"], timeout: 20)
        guard res.succeeded else {
            return CollectorResult(items: [], coverage: coverage(
                res.status == -1 ? .skippedUnsupported : .failed))
        }
        var items: [StartupItem] = []
        for line in res.stdout.split(separator: "\n") {
            // Rows contain a teamID and bundle id in brackets/columns; extract a
            // bundle-id-looking token. Tolerant: the format is not contractual.
            let tokens = line.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init)
            guard let bundleID = tokens.first(where: { $0.contains(".") && !$0.hasPrefix("[") }),
                  bundleID.split(separator: ".").count >= 2 else { continue }
            let teamID = tokens.first(where: { $0.count == 10 && $0.uppercased() == $0 })
            let enabled = line.contains("[activated enabled]") || line.lowercased().contains("activated")
            items.append(StartupItem(
                id: "systemExtension:\(bundleID)",
                mechanism: .systemExtension,
                label: bundleID, displayName: bundleID,
                triggers: [.speculative],
                state: StateAxes(configured: .yes, registered: .yes,
                                 loaded: Tristate(enabled)),
                attribution: ResolvedAttribution(teamIdentifier: teamID),
                actionClass: .guidedAction,
                provenance: [Provenance(collector: self.name, source: "systemextensionsctl list",
                                        sourceQuality: .appleContract, osBuild: ctx.osBuild)],
                notes: ["Disable through the owning app or System Settings; CLI removal requires SIP disabled."]))
        }
        return CollectorResult(items: items, coverage: coverage(
            items.isEmpty ? .ranEmpty : .ran, count: items.count))
    }
}

/// App extensions / Finder Sync / widgets via `pluginkit -mAvvv`. Trigger-labeled
/// honestly; most are on-demand, so they land in the advanced tier.
public struct PluginKitCollector: Collector {
    public let name = "pluginkit"
    public let mechanism: Mechanism = .appExtension
    public init() {}

    public func collect(_ ctx: ScanContext) -> CollectorResult {
        let res = ctx.runner.run("/usr/bin/pluginkit", ["-mAvvv"], timeout: 30)
        guard res.succeeded else {
            return CollectorResult(items: [], coverage: coverage(.failed))
        }
        var items: [StartupItem] = []
        for line in res.stdout.split(separator: "\n") {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            // Format: "+   com.vendor.ext(1.0)   ...   /path".  First column is
            // the enabled marker (+ enabled, - disabled, ? unknown).
            guard let first = parts.first, !first.isEmpty else { continue }
            let marker = first.trimmingCharacters(in: .whitespaces).first
            let idField = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
            let bundleID = idField.split(separator: "(").first.map(String.init) ?? idField
            guard bundleID.contains(".") else { continue }
            let isFinderSync = line.contains("com.apple.FinderSync")
            let isFileProvider = line.contains("fileprovider")
            let runsNearLogin = isFinderSync || isFileProvider
            items.append(StartupItem(
                id: "appExtension:\(bundleID)",
                mechanism: .appExtension,
                label: bundleID, displayName: bundleID,
                triggers: runsNearLogin ? [.speculative] : [.onDemand],
                state: StateAxes(configured: .yes,
                                 authorized: Tristate(marker == "+")),
                actionClass: .guidedAction,
                provenance: [Provenance(collector: self.name, source: "pluginkit -mAvvv",
                                        sourceQuality: .appleContract, osBuild: ctx.osBuild)],
                notes: runsNearLogin ? ["Runs around login (Finder Sync / File Provider)."]
                    : ["On-demand extension; runs only when its host is invoked."]))
        }
        return CollectorResult(items: items, coverage: coverage(
            items.isEmpty ? .ranEmpty : .ran, count: items.count))
    }
}

/// Configuration profiles (`profiles show`). Read-only; explains managed items.
public struct ProfilesCollector: Collector {
    public let name = "profiles"
    public let mechanism: Mechanism = .configurationProfile
    public init() {}

    public func collect(_ ctx: ScanContext) -> CollectorResult {
        guard ctx.hasRoot else {
            return CollectorResult(items: [], coverage: coverage(
                .deniedPermission, detail: "profiles show needs root."))
        }
        let res = ctx.runner.run("/usr/bin/profiles", ["show", "-type", "configuration"], timeout: 30)
        guard res.succeeded else {
            return CollectorResult(items: [], coverage: coverage(
                res.status == -1 ? .failed : .ranEmpty))
        }
        // Count profiles; each is surfaced as a read-only managed item.
        var items: [StartupItem] = []
        var currentName: String?
        for line in res.stdout.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("name:") {
                currentName = t.replacingOccurrences(of: "name:", with: "").trimmingCharacters(in: .whitespaces)
            } else if t.hasPrefix("profileIdentifier:"), let name = currentName {
                let ident = t.replacingOccurrences(of: "profileIdentifier:", with: "").trimmingCharacters(in: .whitespaces)
                items.append(StartupItem(
                    id: "configurationProfile:\(ident)",
                    mechanism: .configurationProfile,
                    label: ident, displayName: name,
                    state: StateAxes(configured: .yes, authorized: .yes),
                    trust: .managed,
                    actionClass: .readOnly,
                    provenance: [Provenance(collector: self.name, source: "profiles show",
                                            sourceQuality: .appleContract, osBuild: ctx.osBuild,
                                            permissions: "root")],
                    notes: ["Installed by your organization; remove via your administrator or MDM."]))
                currentName = nil
            }
        }
        return CollectorResult(items: items, coverage: coverage(
            items.isEmpty ? .ranEmpty : .ran, count: items.count))
    }
}
