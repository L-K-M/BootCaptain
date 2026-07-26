import Foundation

/// Which privileged operations are enabled in the current build.
///
/// PLAN.md §6 gates privileged mutation behind a durable journal, an
/// authorization boundary, descriptor-safe target handling, and the Phase-0
/// hardware matrix. Rather than a single all-or-nothing switch, enablement is
/// per-operation so the **reversible, file-move-only** Clean Up path can ship
/// while the launchd-state and cron mutations — which are not reversible by a
/// simple file move and need their full qualification — stay disabled.
public extension ActionRequest.Operation {
    var isEnabledInCurrentBuild: Bool {
        switch self {
        case .moveToVault, .restoreFromVault:
            // Reversible: the source file is relocated to a same-volume vault
            // and can be moved back verbatim. This is the Clean Up action.
            return true
        case .launchdDisable, .launchdEnable, .launchdBootout, .cronToggleEntry:
            // Not yet qualified (PLAN.md §6): these change launchd/cron state,
            // not just file location, and need the full journal + authorization
            // + hardware matrix before they can be enabled.
            return false
        }
    }
}
