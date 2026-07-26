import Foundation

/// How an item is provoked into running. Dimensions are **independent** — a
/// launchd job routinely has several — so this is an `OptionSet`, not an enum.
/// PLAN.md §2.1: "On-demand only" is the derived fallback when no speculative,
/// scheduled, or event trigger applies.
public struct TriggerSet: OptionSet, Codable, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// RunAtLoad, any KeepAlive, or legacy OnDemand==false: the item is launched
    /// speculatively when its domain/session is bootstrapped.
    public static let speculative = TriggerSet(rawValue: 1 << 0)
    /// StartInterval / StartCalendarInterval.
    public static let scheduled = TriggerSet(rawValue: 1 << 1)
    /// WatchPaths / QueueDirectories / StartOnMount / LaunchEvents.
    public static let event = TriggerSet(rawValue: 1 << 2)
    /// MachServices / Sockets registration with no other trigger: registered at
    /// bootstrap, but no process runs until a client asks for it.
    public static let onDemand = TriggerSet(rawValue: 1 << 3)

    /// Whether the item is expected to execute at boot/login without external
    /// stimulus. Disabling non-speculative items rarely saves login time.
    public var runsAtStartup: Bool { contains(.speculative) }

    /// One-line, human "runs when" summary for the UI (PLAN.md §5).
    public func chips(keepAlive: KeepAliveKind = .none) -> [String] {
        var out: [String] = []
        if contains(.speculative) {
            switch keepAlive {
            case .always: out.append("Kept running")
            case .conditional: out.append("Kept alive on conditions")
            case .none: out.append("Starts when loaded")
            }
        }
        if contains(.scheduled) { out.append("Scheduled") }
        if contains(.event) { out.append("When files or devices change") }
        if contains(.onDemand) && !contains(.speculative) {
            out.append("On demand — only when a client asks")
        }
        return out
    }
}

/// Distinguishes the two speculative KeepAlive shapes for display only.
public enum KeepAliveKind: String, Codable, Sendable {
    case none
    case always        // KeepAlive == true
    case conditional   // KeepAlive is a dictionary of conditions
}
