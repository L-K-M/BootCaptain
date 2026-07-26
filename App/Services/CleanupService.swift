import Foundation
import SwiftUI
import BootCaptainCore
import BootCaptainKit

/// Executes the built-in "Clean Up" flow for provably-broken startup leftovers.
///
/// - `userVaultMove`: moves a broken plist the user owns from their
///   `~/Library/LaunchAgents` into a reversible user-scope vault, journaled.
/// - `loginItemRemoval`: removes a classic "Open at Login" entry via System
///   Events; undo re-adds it by path.
/// - `requiresHelper`: for broken `/Library/Launch{Daemons,Agents}` plists, the
///   move is performed by the privileged helper (admin approval once), into a
///   root-owned vault. Only the reversible move/restore is enabled
///   (`ActionRequest.Operation.isEnabledInCurrentBuild`); nothing is deleted.
///
/// All actions are **idempotent**: an item that has already been cleaned is
/// never re-attempted (`completedItemIDs`), which is what made repeated
/// "Clean Up" clicks fail with "vault destination already exists".
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
    /// Items successfully cleaned this session — excluded from any re-run.
    @Published private(set) var completedItemIDs: Set<String> = []

    private let home = NSHomeDirectory()
    private var vaultRoot: String { home + "/Library/Application Support/BootCaptain/Vault" }
    private var journal: FileJournal {
        FileJournal(directory: home + "/Library/Application Support/BootCaptain/Journal")
    }

    var userHomes: [String] { [home] }

    func candidates(from items: [StartupItem]) -> [CleanupPlanner.Candidate] {
        CleanupPlanner.plan(items: items, userHomes: userHomes)
    }

    /// Candidates minus anything already cleaned — what the UI should offer.
    func pending(from candidates: [CleanupPlanner.Candidate]) -> [CleanupPlanner.Candidate] {
        candidates.filter { !completedItemIDs.contains($0.itemID) }
    }

    /// Perform the selected candidates. Already-completed items are skipped, so
    /// this is safe to call repeatedly.
    func perform(_ selected: [CleanupPlanner.Candidate], helper: HelperClient) async {
        isWorking = true
        defer { isWorking = false }
        for candidate in selected where !completedItemIDs.contains(candidate.itemID) {
            switch candidate.eligibility {
            case .userVaultMove: await vaultMove(candidate)
            case .loginItemRemoval: await removeLoginItem(candidate)
            case .requiresHelper: await helperVaultMove(candidate, helper: helper)
            }
        }
    }

    /// Undo one performed action. Dispatches on what was actually done.
    func undo(_ action: PerformedAction, helper: HelperClient) async {
        // `!isWorking` rejects a second concurrent undo (e.g. a rapid double
        // tap) before `performed` is updated, which would otherwise run the
        // same inverse twice and corrupt the row's undone/inverse state. The
        // Undo button is also disabled while working; this is the guard behind
        // it.
        guard !isWorking, !action.undone, let inverse = action.inverse else { return }
        isWorking = true
        defer { isWorking = false }
        let outcome: ActionOutcome
        switch action.candidate.eligibility {
        case .userVaultMove:
            // Undo is itself a file mutation (vault -> original), so it is
            // journaled exactly like the forward move: no prepared record, no
            // move. (loginItemRemoval undo is unjournaled by design — System
            // Events is the source of truth and no vault file is involved; the
            // requiresHelper path is journaled inside the helper.)
            outcome = await journaledVaultOperation(inverse)
        case .loginItemRemoval:
            outcome = await addLoginItemBack(path: action.candidate.sourcePath)
        case .requiresHelper:
            outcome = await helper.perform(inverse)
        }
        if outcome.status == .committed {
            completedItemIDs.remove(action.candidate.itemID)
        }
        if let idx = performed.firstIndex(where: { $0.id == action.id }) {
            // Preserve the inverse when the undo did not commit, so the Undo
            // button stays live and the user can retry. Clearing it only on a
            // committed undo is what flips the row to "Undone".
            performed[idx] = PerformedAction(
                candidate: action.candidate, outcome: outcome,
                inverse: outcome.status == .committed ? nil : action.inverse,
                undone: outcome.status == .committed)
        }
    }

    // MARK: user-scope vault moves

    private func vaultMove(_ candidate: CleanupPlanner.Candidate) async {
        let request = ActionRequest(
            operation: .moveToVault, itemID: candidate.itemID,
            sourcePath: candidate.sourcePath)
        let outcome = await journaledVaultOperation(request)
        recordResult(candidate, request: request, outcome: outcome)
    }

    /// Run a user-scope vault operation under prepare -> run -> complete
    /// journaling, so the "every mutation is preceded by a durable prepared
    /// record" invariant holds for both the forward move and its undo. If the
    /// prepared record cannot be written, nothing is moved.
    private func journaledVaultOperation(_ request: ActionRequest) async -> ActionOutcome {
        guard let record = journal.prepare(request, at: Date().timeIntervalSince1970) else {
            return ActionOutcome(
                status: .aborted,
                message: "Could not write the prepared journal record; nothing was changed.")
        }
        let outcome = await runVaultOperation(request)
        if !journal.complete(record, status: outcome.status, at: Date().timeIntervalSince1970) {
            // Mutation already ran; only surface that the record is now stale.
            NSLog("BootCaptain: journal completion write failed for \(request.itemID); file operation ran, on-disk record is stale.")
        }
        return outcome
    }

    private func runVaultOperation(_ request: ActionRequest) async -> ActionOutcome {
        let runner = ActionRunner(vaultRoot: vaultRoot)
        return await Task.detached(priority: .userInitiated) {
            runner.perform(request)
        }.value
    }

    // MARK: privileged (helper) vault moves — /Library items

    private func helperVaultMove(_ candidate: CleanupPlanner.Candidate, helper: HelperClient) async {
        let request = ActionRequest(
            operation: .moveToVault, itemID: candidate.itemID,
            sourcePath: candidate.sourcePath)
        // The helper journals its own root-scope prepared/committed record.
        let outcome = await helper.perform(request)
        recordResult(candidate, request: request, outcome: outcome)
    }

    // MARK: classic login items (System Events)

    private func removeLoginItem(_ candidate: CleanupPlanner.Candidate) async {
        guard let path = candidate.sourcePath else { return }
        let script = "tell application \"System Events\" to delete (every login item whose path is \"\(path)\")"
        let outcome = await runAppleScript(script,
            success: "Removed the login item. Undo re-adds it.",
            failure: "Could not remove the login item (System Events automation may need approval).")
        let inverse = ActionRequest(operation: .restoreFromVault, itemID: candidate.itemID,
                                    sourcePath: path)  // marker; undo re-adds by path
        recordResult(candidate, inverse: inverse, outcome: outcome)
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

    // MARK: result bookkeeping

    /// Record an outcome and mark the item completed on success, deriving the
    /// inverse from the request.
    private func recordResult(_ candidate: CleanupPlanner.Candidate,
                              request: ActionRequest, outcome: ActionOutcome) {
        recordResult(candidate,
                     inverse: outcome.status == .committed
                        ? ActionJournalLogic.inverse(of: request) : nil,
                     outcome: outcome)
    }

    private func recordResult(_ candidate: CleanupPlanner.Candidate,
                              inverse: ActionRequest?, outcome: ActionOutcome) {
        if outcome.status == .committed {
            completedItemIDs.insert(candidate.itemID)
        }
        performed.append(PerformedAction(
            candidate: candidate, outcome: outcome,
            inverse: outcome.status == .committed ? inverse : nil))
    }
}
