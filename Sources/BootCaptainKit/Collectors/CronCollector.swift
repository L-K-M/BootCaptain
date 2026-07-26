import Foundation
import BootCaptainCore

/// Collects cron entries from `/etc/crontab` and per-user tabs under
/// `/usr/lib/cron/tabs` (PLAN.md §2.4, §6.1). User tabs are root-readable, so
/// full coverage needs the helper.
public struct CronCollector: Collector {
    public let name = "cron"
    public let mechanism: Mechanism = .cron

    public init() {}

    public func collect(_ ctx: ScanContext) -> CollectorResult {
        var items: [StartupItem] = []
        var sawDeniedTabs = false

        // System crontab.
        if let data = ctx.fileManager.contents(atPath: "/etc/crontab"),
           let text = String(data: data, encoding: .utf8) {
            for entry in CronParser.parse(text, style: .systemCrontab) {
                items.append(makeItem(entry, tab: "/etc/crontab", user: entry.user, ctx: ctx))
            }
        }

        // Per-user crontabs.
        let tabsDir = "/usr/lib/cron/tabs"
        if let users = try? ctx.fileManager.contentsOfDirectory(atPath: tabsDir) {
            for user in users {
                let tab = tabsDir + "/" + user
                guard let data = ctx.fileManager.contents(atPath: tab),
                      let text = String(data: data, encoding: .utf8) else {
                    sawDeniedTabs = true; continue
                }
                for entry in CronParser.parse(text, style: .userCrontab) {
                    items.append(makeItem(entry, tab: tab, user: user, ctx: ctx))
                }
            }
        } else if !ctx.hasRoot {
            sawDeniedTabs = true
        }

        let status: CollectorCoverage.Status = sawDeniedTabs && items.isEmpty
            ? .deniedPermission : (items.isEmpty ? .ranEmpty : .ran)
        return CollectorResult(items: items, coverage: coverage(
            status, count: items.count,
            detail: sawDeniedTabs ? "Some user crontabs need root to read." : nil))
    }

    func makeItem(_ entry: CronEntry, tab: String, user: String?, ctx: ScanContext) -> StartupItem {
        let id = "cron:\(tab):\(entry.lineNumber)"
        var notes: [String] = []
        if entry.runsAtReboot { notes.append("Runs at every reboot (@reboot).") }
        notes.append("Command: \(entry.command)")
        var state = StateAxes(configured: .yes)
        state.override = entry.isDisabledByBootCaptain ? .disabled : .absentDefault
        return StartupItem(
            id: id,
            mechanism: .cron,
            label: entry.command,
            displayName: "cron: \(shortCommand(entry.command))",
            domain: user,
            sourcePath: tab,
            triggers: entry.runsAtReboot ? [.speculative] : [.scheduled],
            state: state,
            trust: .unknown,
            actionClass: .guidedAction,
            provenance: [Provenance(
                collector: name, parserVersion: CronParser.version, source: tab,
                sourceQuality: .appleContract, osBuild: ctx.osBuild,
                permissions: ctx.hasRoot ? "root" : "user")],
            notes: notes)
    }

    private func shortCommand(_ cmd: String) -> String {
        let first = cmd.split(separator: " ").first.map(String.init) ?? cmd
        return (first as NSString).lastPathComponent
    }
}
