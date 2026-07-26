import Foundation

/// PLAN.md §3: the action engine must consume the individual state facts and
/// their provenance, never a single collapsed Boolean. Each axis is a tri-state
/// so "we did not observe it" is distinct from "we observed it to be false".
public enum Tristate: String, Codable, Sendable {
    case yes
    case no
    case unknown

    public init(_ b: Bool?) {
        switch b {
        case .some(true): self = .yes
        case .some(false): self = .no
        case .none: self = .unknown
        }
    }
}

/// The launchd persistent-override state, read from `launchctl print-disabled`.
/// PLAN.md §6.1: an "unknown" pre-state blocks mutation because no safe inverse
/// can be established.
public enum OverrideState: String, Codable, Sendable {
    /// No override recorded — the plist's own `Disabled` default applies.
    case absentDefault
    /// Explicitly enabled by an override.
    case explicitEnabled
    /// Explicitly disabled by an override.
    case disabled
    /// State could not be determined.
    case unknown
}

/// The separate state axes for one item. The UI may summarise these; the action
/// engine must not.
public struct StateAxes: Codable, Sendable, Equatable {
    /// A configured source (plist, crontab line, BTM record) exists on disk.
    public var configured: Tristate
    /// Registered with launchd / BTM / ServiceManagement.
    public var registered: Tristate
    /// Authorised to run by the user or by management policy.
    public var authorized: Tristate
    /// launchd override state for the domain the service lives in.
    public var override: OverrideState
    /// Currently loaded into a launchd domain.
    public var loaded: Tristate
    /// A process is currently running.
    public var running: Tristate

    public init(
        configured: Tristate = .unknown,
        registered: Tristate = .unknown,
        authorized: Tristate = .unknown,
        override: OverrideState = .unknown,
        loaded: Tristate = .unknown,
        running: Tristate = .unknown
    ) {
        self.configured = configured
        self.registered = registered
        self.authorized = authorized
        self.override = override
        self.loaded = loaded
        self.running = running
    }

    /// A conservative "is it effectively on" summary for display badges only.
    /// Returns `.unknown` whenever the inputs are ambiguous rather than
    /// guessing, per PLAN.md's refusal to collapse axes.
    public var effectivelyEnabled: Tristate {
        if override == .disabled { return .no }
        if running == .yes || loaded == .yes { return .yes }
        if override == .explicitEnabled { return .yes }
        if configured == .yes && override == .absentDefault { return .yes }
        return .unknown
    }
}
