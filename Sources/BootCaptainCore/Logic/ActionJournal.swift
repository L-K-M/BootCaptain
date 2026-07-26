import Foundation

/// A single mutation the action engine may perform. Kept as **typed** data, not
/// shell fragments (PLAN.md §6.4 "no confused deputy").
public struct ActionRequest: Codable, Sendable, Equatable {
    public enum Operation: String, Codable, Sendable {
        case launchdDisable      // disable + record inverse `enable`
        case launchdEnable
        case launchdBootout      // stop now; inverse is bootstrap
        case cronToggleEntry     // comment/uncomment one entry, reinstall tab
        case moveToVault         // move a source file into the disable vault
        case restoreFromVault
    }
    public var operation: Operation
    public var itemID: String
    public var label: String?
    public var domain: String?
    public var sourcePath: String?
    /// For cron: the entry's line number within the tab.
    public var cronLineNumber: Int?
    public var cronUser: String?

    public init(
        operation: Operation, itemID: String, label: String? = nil,
        domain: String? = nil, sourcePath: String? = nil,
        cronLineNumber: Int? = nil, cronUser: String? = nil
    ) {
        self.operation = operation
        self.itemID = itemID
        self.label = label
        self.domain = domain
        self.sourcePath = sourcePath
        self.cronLineNumber = cronLineNumber
        self.cronUser = cronUser
    }
}

/// A journal record's lifecycle (PLAN.md §6.3). `indeterminate` is the honest
/// outcome when we cannot prove whether the mutation took effect; recovery must
/// reconcile it against live state, never blindly repeat or reverse it.
public enum JournalStatus: String, Codable, Sendable {
    case prepared
    case committed
    case aborted
    case indeterminate
}

/// One durable journal entry. `undo` carries everything needed to reverse the
/// mutation without re-deriving it.
public struct JournalRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String              // unique, immutable
    public var request: ActionRequest
    public var status: JournalStatus
    /// Verified preconditions captured before mutating (idempotent undo data).
    public var preconditions: [String: String]
    /// The inverse operation, precomputed.
    public var inverse: ActionRequest?
    /// Seconds since 1970.
    public var preparedAt: Double
    public var completedAt: Double?

    public init(
        id: String,
        request: ActionRequest,
        status: JournalStatus = .prepared,
        preconditions: [String: String] = [:],
        inverse: ActionRequest? = nil,
        preparedAt: Double,
        completedAt: Double? = nil
    ) {
        self.id = id
        self.request = request
        self.status = status
        self.preconditions = preconditions
        self.inverse = inverse
        self.preparedAt = preparedAt
        self.completedAt = completedAt
    }
}

/// Pure state-machine logic for the journal. The macOS `ActionRunner` owns the
/// durable writes (F_FULLFSYNC, exclusive rename); this type owns the decisions
/// so they can be unit-tested off a Mac.
public enum ActionJournalLogic {
    /// Compute the inverse of a request (PLAN.md §6.1/§6.3). Returns nil when the
    /// operation is not exactly reversible; callers must then disclose residue.
    public static func inverse(of request: ActionRequest) -> ActionRequest? {
        switch request.operation {
        case .launchdDisable:
            return ActionRequest(operation: .launchdEnable, itemID: request.itemID,
                                 label: request.label, domain: request.domain,
                                 sourcePath: request.sourcePath)
        case .launchdEnable:
            return ActionRequest(operation: .launchdDisable, itemID: request.itemID,
                                 label: request.label, domain: request.domain,
                                 sourcePath: request.sourcePath)
        case .launchdBootout:
            // Inverse requires the origin plist path to bootstrap.
            guard request.sourcePath != nil else { return nil }
            return ActionRequest(operation: .launchdDisable, itemID: request.itemID,
                                 label: request.label, domain: request.domain,
                                 sourcePath: request.sourcePath)
        case .cronToggleEntry:
            return ActionRequest(operation: .cronToggleEntry, itemID: request.itemID,
                                 sourcePath: request.sourcePath,
                                 cronLineNumber: request.cronLineNumber,
                                 cronUser: request.cronUser)
        case .moveToVault:
            return ActionRequest(operation: .restoreFromVault, itemID: request.itemID,
                                 sourcePath: request.sourcePath)
        case .restoreFromVault:
            return ActionRequest(operation: .moveToVault, itemID: request.itemID,
                                 sourcePath: request.sourcePath)
        }
    }

    /// On startup, decide what to do with an unfinished record (PLAN.md §6.3).
    public enum RecoveryAction: String, Sendable, Equatable {
        case none              // committed/aborted: settled
        case reconcile         // prepared/indeterminate: verify live state first
    }

    public static func recoveryAction(for record: JournalRecord) -> RecoveryAction {
        switch record.status {
        case .committed, .aborted: return .none
        case .prepared, .indeterminate: return .reconcile
        }
    }

    /// Records that need reconciliation on next launch.
    public static func unfinished(_ records: [JournalRecord]) -> [JournalRecord] {
        records.filter { recoveryAction(for: $0) == .reconcile }
    }
}
