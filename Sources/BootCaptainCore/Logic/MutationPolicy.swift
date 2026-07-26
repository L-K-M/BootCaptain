import Foundation

/// Which privileged operations are enabled in the current build.
///
/// PLAN.md §6 gates privileged mutation behind a durable journal, an
/// authorization boundary, descriptor-safe target handling, and the Phase-0
/// hardware matrix. None of those mechanisms is qualified yet, including the
/// vault move/restore path.
public extension ActionRequest.Operation {
    var isEnabledInCurrentBuild: Bool {
        false
    }
}
