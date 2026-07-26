import Foundation

/// Derives the independent trigger dimensions of a launchd job (PLAN.md §2.1).
///
/// A job launches speculatively at load when `RunAtLoad` is set, when any
/// `KeepAlive` value is present (Apple documents that `KeepAlive`, including its
/// dictionary form, implies `RunAtLoad` — EVIDENCE L-04), or via the legacy
/// `OnDemand == false`. On-demand is the *derived fallback*: it only applies
/// when Mach services / sockets are declared and no stronger trigger exists.
public enum TriggerClassifier {
    public static func classify(_ job: LaunchdJob) -> (TriggerSet, KeepAliveKind) {
        var set: TriggerSet = []
        let keepAlive = job.keepAlive ?? .none

        let speculative = job.runAtLoad
            || job.keepAlive != nil          // any KeepAlive value implies RunAtLoad
            || job.onDemand == false          // legacy OnDemand=false == KeepAlive
        if speculative { set.insert(.speculative) }

        if job.startInterval || job.startCalendarInterval { set.insert(.scheduled) }
        if job.watchPaths || job.queueDirectories || job.startOnMount || job.launchEvents {
            set.insert(.event)
        }

        let registersEndpoints = job.machServices || job.sockets
        // On-demand is only the classification when nothing else provokes it.
        if registersEndpoints && set.isEmpty {
            set.insert(.onDemand)
        } else if set.isEmpty {
            // No triggers at all: still registered, effectively on-demand/manual.
            set.insert(.onDemand)
        }

        return (set, keepAlive)
    }
}
