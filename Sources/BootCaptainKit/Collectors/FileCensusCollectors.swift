import Foundation
import BootCaptainCore

/// "Reopen windows" relaunch list (PLAN.md §2.3) — apps that relaunch at login
/// without being login items. Read via `defaults -currentHost`.
public struct WindowRestorationCollector: Collector {
    public let name = "window-restoration"
    public let mechanism: Mechanism = .windowRestoration
    public init() {}

    public func collect(_ ctx: ScanContext) -> CollectorResult {
        let res = ctx.runner.run("/usr/bin/defaults",
            ["-currentHost", "read", "com.apple.loginwindow", "TALAppsToRelaunchAtLogin"],
            timeout: 15)
        guard res.succeeded else {
            // Absent key just means nothing pending; that's not a gap.
            return CollectorResult(items: [], coverage: coverage(.ranEmpty))
        }
        // The value is an old-style plist array dump; extract BundleID/Path lines.
        var items: [StartupItem] = []
        var currentBundle: String?
        var currentPath: String?
        func flush() {
            if let path = currentPath {
                let name = (path as NSString).lastPathComponent
                items.append(StartupItem(
                    id: "windowRestoration:\(currentBundle ?? path)",
                    mechanism: .windowRestoration,
                    label: currentBundle ?? name, displayName: name,
                    sourcePath: path, triggers: [.speculative],
                    state: StateAxes(configured: .yes),
                    actionClass: .guidedAction,
                    provenance: [Provenance(collector: self.name,
                        source: "TALAppsToRelaunchAtLogin", sourceQuality: .reproducible,
                        osBuild: ctx.osBuild)],
                    notes: ["Reopens at login because \"Reopen windows when logging back in\" was set; not a login item."]))
            }
            currentBundle = nil; currentPath = nil
        }
        for raw in res.stdout.split(separator: "\n") {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("BundleID") { currentBundle = quotedValue(t) }
            else if t.hasPrefix("Path") { currentPath = quotedValue(t) }
            else if t == "}" || t == "{" { if t == "{" { flush() } }
        }
        flush()
        return CollectorResult(items: items, coverage: coverage(
            items.isEmpty ? .ranEmpty : .ran, count: items.count))
    }

    private func quotedValue(_ line: String) -> String? {
        guard let eq = line.firstIndex(of: "=") else { return nil }
        return String(line[line.index(after: eq)...])
            .trimmingCharacters(in: CharacterSet(charactersIn: " ;\""))
    }
}

/// Legacy / lingering mechanisms as a census (PLAN.md §2.4). Each is reported
/// with its trigger/scope and an honest "inert" flag where applicable.
public struct LegacyCensusCollector: Collector {
    public let name = "legacy-census"
    public let mechanism: Mechanism = .startupItem
    public init() {}

    struct Probe {
        let path: String
        let mechanism: Mechanism
        let inert: Bool
        let note: String
        let isDirectory: Bool
    }

    let probes: [Probe] = [
        Probe(path: "/Library/StartupItems", mechanism: .startupItem, inert: true,
              note: "SystemStarter was removed in OS X 10.10; contents are inert leftovers.", isDirectory: true),
        Probe(path: "/System/Library/StartupItems", mechanism: .startupItem, inert: true,
              note: "Legacy StartupItems location; not executed on modern macOS.", isDirectory: true),
        Probe(path: "/etc/launchd.conf", mechanism: .launchdConf, inert: true,
              note: "Ignored by launchd since OS X 10.10.", isDirectory: false),
        Probe(path: "/etc/emond.d/rules", mechanism: .emond, inert: false,
              note: "emond was removed in Ventura; rules here are a red flag on modern macOS.", isDirectory: true),
        Probe(path: "/etc/periodic", mechanism: .periodic, inert: false,
              note: "periodic scripts; third-party scripts here run on schedule.", isDirectory: true),
        Probe(path: "/Library/Audio/Plug-Ins/HAL", mechanism: .audioHALPlugin, inert: false,
              note: "Audio HAL plug-ins load with coreaudiod at boot.", isDirectory: true),
        Probe(path: "/Library/Security/SecurityAgentPlugins", mechanism: .authorizationPlugin, inert: false,
              note: "Runs at the login window; disabling wrongly can lock you out.", isDirectory: true),
    ]

    public func collect(_ ctx: ScanContext) -> CollectorResult {
        var items: [StartupItem] = []
        for probe in probes {
            var isDir: ObjCBool = false
            guard ctx.fileManager.fileExists(atPath: probe.path, isDirectory: &isDir) else { continue }
            let children: [String]
            if probe.isDirectory {
                children = (try? ctx.fileManager.contentsOfDirectory(atPath: probe.path)) ?? []
            } else {
                children = [probe.path]
            }
            // Skip empty legacy dirs so we don't clutter the list with nothing.
            let meaningful = children.filter { $0 != ".DS_Store" }
            guard !meaningful.isEmpty else { continue }
            for child in meaningful {
                let full = probe.isDirectory ? probe.path + "/" + child : probe.path
                items.append(StartupItem(
                    id: "\(probe.mechanism.rawValue):\(full)",
                    mechanism: probe.mechanism,
                    label: child, displayName: child, sourcePath: full,
                    triggers: probe.inert ? [] : [.speculative],
                    state: StateAxes(configured: .yes),
                    health: probe.inert ? .ok : .unknown,
                    isInert: probe.inert,
                    actionClass: .readOnly,
                    provenance: [Provenance(collector: self.name, source: full,
                        sourceQuality: .independent, osBuild: ctx.osBuild)],
                    notes: [probe.note]))
            }
        }
        return CollectorResult(items: items, coverage: coverage(
            items.isEmpty ? .ranEmpty : .ran, count: items.count))
    }
}
