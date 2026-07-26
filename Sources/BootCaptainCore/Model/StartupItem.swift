import Foundation

/// The launch recipe resolved from a launchd job or equivalent (PLAN.md §4).
/// Kept explicit so the interpreter trap and unresolved exec chains can be
/// represented rather than guessed.
public struct LaunchRecipe: Codable, Sendable, Equatable {
    /// The executable actually spawned (resolved `Program`, `ProgramArguments[0]`
    /// via `_PATH_STDPATH`, or `BundleProgram`), if it could be resolved.
    public var executablePath: String?
    public var arguments: [String]
    /// True when argv[0] is an Apple interpreter (bash/python/osascript…) and the
    /// real payload is a script argument — trust must come from the script.
    public var isInterpreter: Bool
    /// The script path when `isInterpreter` and it could be resolved.
    public var scriptPath: String?
    /// True when the exec chain could not be resolved (shell string, dynamic
    /// wrapper); such items fail closed for mutation.
    public var isUnresolved: Bool

    public init(
        executablePath: String? = nil,
        arguments: [String] = [],
        isInterpreter: Bool = false,
        scriptPath: String? = nil,
        isUnresolved: Bool = false
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.isInterpreter = isInterpreter
        self.scriptPath = scriptPath
        self.isUnresolved = isUnresolved
    }

    /// The path whose signature/trust actually matters for this item.
    public var trustPath: String? {
        if isInterpreter { return scriptPath ?? executablePath }
        return executablePath
    }
}

/// One discovered thing that can run at startup/login. The reconciler produces
/// these; the UI and action engine consume them.
public struct StartupItem: Codable, Sendable, Identifiable, Equatable {
    /// Stable identity: mechanism + label/path so re-scans align.
    public var id: String
    public var mechanism: Mechanism
    /// The launchd Label, crontab key, BTM UUID, etc. — the mechanism's primary key.
    public var label: String?
    /// Human display name once attributed; falls back to label/path.
    public var displayName: String
    /// The domain a launchd item lives in (e.g. "gui/501", "system"), if known.
    public var domain: String?
    /// The origin file on disk (plist path, crontab path, bundle path), if any.
    public var sourcePath: String?

    public var recipe: LaunchRecipe?
    public var triggers: TriggerSet
    public var keepAlive: KeepAliveKind

    public var state: StateAxes
    public var trust: TrustClass
    public var health: HealthState
    public var signing: [SigningIdentity]
    public var attribution: ResolvedAttribution
    public var diagnosis: Diagnosis?

    /// Whether this item is inert on the running OS (e.g. StartupItems residue).
    public var isInert: Bool
    /// Whether BootCaptain is permitted to offer a supported reversible action.
    public var actionClass: ActionClass

    public var provenance: [Provenance]
    /// Free-form notes surfaced in the detail view (e.g. "installed from a disk
    /// image that is no longer mounted").
    public var notes: [String]

    public init(
        id: String,
        mechanism: Mechanism,
        label: String? = nil,
        displayName: String,
        domain: String? = nil,
        sourcePath: String? = nil,
        recipe: LaunchRecipe? = nil,
        triggers: TriggerSet = [],
        keepAlive: KeepAliveKind = .none,
        state: StateAxes = StateAxes(),
        trust: TrustClass = .unknown,
        health: HealthState = .unknown,
        signing: [SigningIdentity] = [],
        attribution: ResolvedAttribution = ResolvedAttribution(),
        diagnosis: Diagnosis? = nil,
        isInert: Bool = false,
        actionClass: ActionClass = .readOnly,
        provenance: [Provenance] = [],
        notes: [String] = []
    ) {
        self.id = id
        self.mechanism = mechanism
        self.label = label
        self.displayName = displayName
        self.domain = domain
        self.sourcePath = sourcePath
        self.recipe = recipe
        self.triggers = triggers
        self.keepAlive = keepAlive
        self.state = state
        self.trust = trust
        self.health = health
        self.signing = signing
        self.attribution = attribution
        self.diagnosis = diagnosis
        self.isInert = isInert
        self.actionClass = actionClass
        self.provenance = provenance
        self.notes = notes
    }

    /// "runs when" chips for the UI.
    public var triggerChips: [String] { triggers.chips(keepAlive: keepAlive) }
}

/// PLAN.md §6: three action classes. An item enters `reversibleMutation` only
/// after its whole lifecycle passes the hardware matrix.
public enum ActionClass: String, Codable, Sendable {
    case reversibleMutation   // supported, behaviourally reversible
    case guidedAction         // route to vendor / System Settings / admin
    case readOnly             // evidence only

    public var displayName: String {
        switch self {
        case .reversibleMutation: return "Reversible"
        case .guidedAction: return "Guided"
        case .readOnly: return "Read-only"
        }
    }
}
