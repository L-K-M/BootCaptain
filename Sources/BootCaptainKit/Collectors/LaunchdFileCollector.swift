import Foundation
import BootCaptainCore

/// Walks the canonical launchd directories and app-bundle-embedded plists,
/// parses each job, and produces items with their trigger classification and
/// origin provenance (PLAN.md §2.1, §3 step 1). State axes beyond "configured"
/// are filled in later by the reconciler.
public struct LaunchdFileCollector: Collector {
    public let name = "launchd-files"
    public let mechanism: Mechanism = .launchDaemon

    public init() {}

    /// (directory, mechanism, domain-hint) for every scanned location.
    struct Location {
        let path: String
        let mechanism: Mechanism
        let isSystem: Bool
        let onSSV: Bool
        let appleControlled: Bool
    }

    func locations(_ ctx: ScanContext) -> [Location] {
        var out: [Location] = [
            Location(path: "/System/Library/LaunchDaemons", mechanism: .launchDaemon,
                     isSystem: true, onSSV: true, appleControlled: true),
            Location(path: "/System/Library/LaunchAgents", mechanism: .launchAgent,
                     isSystem: true, onSSV: true, appleControlled: true),
            Location(path: "/Library/LaunchDaemons", mechanism: .launchDaemon,
                     isSystem: true, onSSV: false, appleControlled: false),
            Location(path: "/Library/LaunchAgents", mechanism: .launchAgent,
                     isSystem: true, onSSV: false, appleControlled: false),
            Location(path: "/Library/Apple/System/Library/LaunchDaemons", mechanism: .launchDaemon,
                     isSystem: true, onSSV: false, appleControlled: true),
            Location(path: "/Library/Apple/System/Library/LaunchAgents", mechanism: .launchAgent,
                     isSystem: true, onSSV: false, appleControlled: true),
        ]
        for home in ctx.userHomes {
            out.append(Location(path: home + "/Library/LaunchAgents", mechanism: .launchAgent,
                                isSystem: false, onSSV: false, appleControlled: false))
        }
        return out
    }

    public func collect(_ ctx: ScanContext) -> CollectorResult {
        var items: [StartupItem] = []
        var warnings = 0

        for loc in locations(ctx) {
            guard let entries = try? ctx.fileManager.contentsOfDirectory(atPath: loc.path) else {
                continue // absent directory is normal
            }
            for entry in entries where entry.hasSuffix(".plist") {
                let full = loc.path + "/" + entry
                guard let data = ctx.fileManager.contents(atPath: full) else { continue }
                do {
                    let job = try LaunchdJobParser.parse(data: data)
                    items.append(makeItem(job: job, path: full, location: loc, ctx: ctx))
                } catch {
                    warnings += 1
                    items.append(makeUnparsable(path: full, location: loc, ctx: ctx))
                }
            }
        }

        // App-bundle-embedded SMAppService plists.
        items.append(contentsOf: collectBundleEmbedded(ctx))

        let status: CollectorCoverage.Status = warnings > 0 ? .partial : .ran
        return CollectorResult(
            items: items,
            coverage: coverage(status, count: items.count,
                               detail: warnings > 0 ? "\(warnings) plist(s) failed to parse" : nil))
    }

    func makeItem(job: LaunchdJob, path: String, location loc: Location, ctx: ScanContext) -> StartupItem {
        let (triggers, keepAlive) = TriggerClassifier.classify(job)
        let recipe = RecipeResolver.resolve(job)
        let label = job.label ?? (path as NSString).lastPathComponent
        let mech = loc.mechanism

        let state = StateAxes(configured: .yes)
        // The on-disk `Disabled` key is only a default; the override DB wins and
        // is filled in later. Leave override .unknown here.
        _ = job.disabledDefault

        var item = StartupItem(
            id: "\(mech.rawValue):\(label)",
            mechanism: mech,
            label: label,
            displayName: label,
            domain: loc.isSystem && mech == .launchDaemon ? "system" : nil,
            sourcePath: path,
            recipe: recipe,
            triggers: triggers,
            keepAlive: keepAlive,
            state: state,
            provenance: [Provenance(
                collector: name, parserVersion: LaunchdJobParser.version,
                source: path, sourceQuality: .reproducible,
                osBuild: ctx.osBuild,
                permissions: ctx.hasRoot ? "root" : "user")])
        item.notes = job.unknownKeys.isEmpty ? [] :
            ["Contains keys BootCaptain does not model: \(job.unknownKeys.joined(separator: ", "))"]
        if job.associatedBundleIdentifiers.isEmpty == false {
            item.attribution.bundleIdentifier = job.associatedBundleIdentifiers.first
        }
        _ = loc.onSSV; _ = loc.appleControlled  // consumed by the reconciler's trust step
        return item
    }

    func makeUnparsable(path: String, location loc: Location, ctx: ScanContext) -> StartupItem {
        let label = (path as NSString).lastPathComponent
        return StartupItem(
            id: "\(loc.mechanism.rawValue):\(label)",
            mechanism: loc.mechanism,
            label: label,
            displayName: label,
            sourcePath: path,
            state: StateAxes(configured: .yes),
            health: .broken,
            provenance: [Provenance(
                collector: name, source: path, sourceQuality: .reproducible,
                osBuild: ctx.osBuild, parseWarnings: ["plist failed to parse"])],
            notes: ["This launch item's property list could not be parsed; it cannot load as written."])
    }

    func collectBundleEmbedded(_ ctx: ScanContext) -> [StartupItem] {
        var items: [StartupItem] = []
        let appRoots = ["/Applications", "/Applications/Setapp"]
            + ctx.userHomes.map { $0 + "/Applications" }
        for root in appRoots {
            guard let apps = try? ctx.fileManager.contentsOfDirectory(atPath: root) else { continue }
            for app in apps where app.hasSuffix(".app") {
                let bundle = root + "/" + app
                for (sub, mech) in [("Contents/Library/LaunchDaemons", Mechanism.smAppServiceDaemon),
                                    ("Contents/Library/LaunchAgents", Mechanism.smAppServiceAgent)] {
                    let dir = bundle + "/" + sub
                    guard let plists = try? ctx.fileManager.contentsOfDirectory(atPath: dir) else { continue }
                    for plist in plists where plist.hasSuffix(".plist") {
                        let full = dir + "/" + plist
                        guard let data = ctx.fileManager.contents(atPath: full),
                              let job = try? LaunchdJobParser.parse(data: data) else { continue }
                        let (triggers, keepAlive) = TriggerClassifier.classify(job)
                        let recipe = RecipeResolver.resolve(job, bundleRoot: bundle)
                        let label = job.label ?? plist
                        items.append(StartupItem(
                            id: "\(mech.rawValue):\(label)",
                            mechanism: mech,
                            label: label,
                            displayName: label,
                            sourcePath: full,
                            recipe: recipe,
                            triggers: triggers,
                            keepAlive: keepAlive,
                            state: StateAxes(configured: .yes),
                            actionClass: .guidedAction,
                            provenance: [Provenance(
                                collector: name, source: full,
                                sourceQuality: .appleContract, osBuild: ctx.osBuild)],
                            notes: ["Registered from inside \(app) via SMAppService; disable through the app or System Settings."]))
                    }
                }
            }
        }
        return items
    }
}
