import Foundation
import BootCaptainCore

/// Snapshots live launchd state and the disabled-override database, keyed by
/// label so the reconciler can join it onto file-based items (PLAN.md §3 steps
/// 2 and 4). Output is treated as unstable — parse failure is reported, never
/// taken as a missing job.
public struct LaunchctlState: Sendable {
    /// label -> running/loaded/exit info from `launchctl print`/`list`.
    public var services: [String: LaunchctlPrintService]
    /// (domain, label) -> override state from `print-disabled`.
    public var overrides: [String: OverrideState]  // key: "domain\tlabel"
    public var coverage: [CollectorCoverage]

    public init() {
        services = [:]
        overrides = [:]
        coverage = []
    }

    public func overrideState(domain: String, label: String) -> OverrideState {
        overrides["\(domain)\t\(label)"] ?? .absentDefault
    }
}

public struct LaunchctlStateCollector: Sendable {
    public let name = "launchctl-state"
    public init() {}

    public func collect(_ ctx: ScanContext) -> LaunchctlState {
        var state = LaunchctlState()
        let launchctl = "/bin/launchctl"

        // System domain (needs root for full detail, but print system works
        // without root for the service table on many builds).
        var domains = ["system", "gui/\(ctx.currentUID)", "user/\(ctx.currentUID)"]
        domains = Array(Set(domains))

        for domain in domains {
            let res = ctx.runner.run(launchctl, ["print", domain])
            if res.succeeded {
                for svc in LaunchctlPrintParser.parseServices(res.stdout) {
                    state.services[svc.label] = svc
                }
                state.coverage.append(CollectorCoverage(
                    collector: "\(name):\(domain)", mechanism: .launchDaemon,
                    status: .ran, itemCount: 0))
            } else {
                state.coverage.append(CollectorCoverage(
                    collector: "\(name):\(domain)", mechanism: .launchDaemon,
                    status: res.status == -1 ? .failed : .deniedPermission,
                    detail: "launchctl print \(domain) exited \(res.status)"))
            }

            let disabled = ctx.runner.run(launchctl, ["print-disabled", domain])
            if disabled.succeeded {
                for (label, override) in LaunchctlDisabledParser.parse(disabled.stdout) {
                    state.overrides["\(domain)\t\(label)"] = override
                }
            }
        }

        // `launchctl list` as a cheap cross-check for running PIDs.
        let list = ctx.runner.run(launchctl, ["list"])
        if list.succeeded {
            for entry in LaunchctlListParser.parse(list.stdout) {
                if state.services[entry.label] == nil {
                    state.services[entry.label] = LaunchctlPrintService(
                        label: entry.label, pid: entry.pid, lastExitCode: entry.lastExitStatus)
                }
            }
        }
        return state
    }
}
