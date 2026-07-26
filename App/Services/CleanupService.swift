import Foundation
import SwiftUI
import BootCaptainCore
import BootCaptainKit

/// Executes the built-in "Clean Up" flow — entirely as the current user, with
/// no root and no privileged helper:
///
/// - `userVaultMove`: moves a broken plist the user owns from their
///   `~/Library/LaunchAgents` into a reversible vault under Application
///   Support, journaled with a precomputed inverse. Nothing is deleted.
/// - `loginItemRemoval`: removes a classic "Open at Login" entry via System
///   Events (the quasi-supported path); undo re-adds it by path.
///
/// Root-owned candidates (`requiresHelper`) are surfaced but not acted on —
/// privileged mutations stay disabled until the Phase-0 work in PLAN.md.
@MainActor
final class CleanupService: ObservableObject {
    struct PerformedAction: Identifiable {
        let id = UUID()
        let candidate: CleanupPlanner.Candidate
        let outcome: ActionOutcome
        let inverse: ActionRequest?
        var undone = false
    }

    @Published var performed: [PerformedAction] = []
    @Published var isWorking = false

    private let home = NSHomeDirectory()
    private var vaultRoot: String { home + "/Library/Application Support/BootCaptain/Vault" }
    private var journalDir: String { home + "/Library/Application Support/BootCaptain/Journal" }

    var userHomes: [String] { [home] }

    func candidates(from items: [StartupItem]) -> [CleanupPlanner.Candidate] {
        CleanupPlanner.plan(items: items, userHomes: userHomes)
    }

    /// Perform the selected candidates. Only actionable eligibilities run.
    func perform(_ selected: [CleanupPlanner.Candidate]) async {
        isWorking = true
        defer { isWorking = false }
        for candidate in selected {
            switch candidate.eligibility {
            case .userVaultMove: await vaultMove(candidate)
            case .loginItemRemoval: await removeLoginItem(candidate)
            case .requiresHelper: continue
            }
        }
    }

    /// Undo one performed action. Dispatch on what was actually done: vault
    /// moves invert through the runner; login-item removals re-add by path.
    func undo(_ action: PerformedAction) async {
        guard !action.undone, let inverse = action.inverse else { return }
        isWorking = true
        defer { isWorking = false }
        let outcome: ActionOutcome
        switch action.candidate.eligibility {
        case .userVaultMove:
            outcome = await runVaultOperation(inverse)
        case .loginItemRemoval:
            outcome = await addLoginItemBack(path: action.candidate.sourcePath)
        case .requiresHelper:
            outcome = ActionOutcome(status: .aborted, message: "Nothing to undo.")
        }
        if let idx = performed.firstIndex(where: { $0.id == action.id }) {
            performed[idx] = PerformedAction(
                candidate: action.candidate,
                outcome: outcome,
                inverse: nil,
                undone: outcome.status == .committed)
        }
    }

    // MARK: vault moves

    private func vaultMove(_ candidate: CleanupPlanner.Candidate) async {
        let request = ActionRequest(
            operation: .moveToVault, itemID: candidate.itemID,
            sourcePath: candidate.sourcePath)
        // Journal prepared → run → committed/indeterminate (PLAN.md §6.3 shape,
        // user-level scope).
        let record = journalPrepare(request)
        let outcome = await runVaultOperation(request)
        journalComplete(record, status: outcome.status)
        performed.append(PerformedAction(
            candidate: candidate, outcome: outcome,
            inverse: outcome.status == .committed
                ? ActionJournalLogic.inverse(of: request) : nil))
    }

    private func runVaultOperation(_ request: ActionRequest) async -> ActionOutcome {
        let runner = ActionRunner(vaultRoot: vaultRoot)
        return await Task.detached(priority: .userInitiated) {
            runner.perform(request)
        }.value
    }

    // MARK: classic login items (System Events)

    private func removeLoginItem(_ candidate: CleanupPlanner.Candidate) async {
        guard let path = candidate.sourcePath else { return }
        let script = "tell application \"System Events\" to delete (every login item whose path is \"\(path)\")"
        let outcome = await runAppleScript(script,
            success: "Removed the login item. Undo re-adds it.",
            failure: "Could not remove the login item (System Events automation may need approval).")
        performed.append(PerformedAction(
            candidate: candidate, outcome: outcome,
            inverse: outcome.status == .committed
                ? ActionRequest(operation: .restoreFromVault, itemID: candidate.itemID,
                                sourcePath: path)  // marker; undo re-adds by path
                : nil))
    }

    private func addLoginItemBack(path: String?) async -> ActionOutcome {
        guard let path else {
            return ActionOutcome(status: .aborted, message: "No path recorded.")
        }
        let script = "tell application \"System Events\" to make login item at end with properties {path:\"\(path)\", hidden:false}"
        return await runAppleScript(script,
            success: "Login item restored.",
            failure: "Could not restore the login item.")
    }

    private func runAppleScript(_ script: String, success: String, failure: String) async -> ActionOutcome {
        await Task.detached(priority: .userInitiated) {
            let result = ProcessRunner().run("/usr/bin/osascript", ["-e", script], timeout: 20)
            return result.succeeded
                ? ActionOutcome(status: .committed, message: success)
                : ActionOutcome(status: .indeterminate,
                                message: failure + " (\(result.stderr.prefix(80)))")
        }.value
    }

    // MARK: journal (user-level)

    private func journalPrepare(_ request: ActionRequest) -> JournalRecord {
        let record = JournalRecord(
            id: UUID().uuidString,
            request: request,
            status: .prepared,
            inverse: ActionJournalLogic.inverse(of: request),
            preparedAt: Date().timeIntervalSince1970)
        writeJournal(record)
        return record
    }

    private func journalComplete(_ record: JournalRecord, status: JournalStatus) {
        var updated = record
        updated.status = status
        updated.completedAt = Date().timeIntervalSince1970
        writeJournal(updated)
    }

    private func writeJournal(_ record: JournalRecord) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: journalDir, withIntermediateDirectories: true)
        let url = URL(fileURLWithPath: journalDir + "/\(record.id).json")
        if let data = try? JSONEncoder().encode(record) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
