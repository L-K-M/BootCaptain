import SwiftUI
import BootCaptainCore

/// The built-in "Clean Up" flow: broken and orphaned startup leftovers, with a
/// reversible one-click fix. User-owned items are moved by the app; system
/// (`/Library`) items are moved by the privileged helper after admin approval.
/// Already-cleaned items are excluded, so repeated runs never re-attempt them.
struct CleanupSheet: View {
    let candidates: [CleanupPlanner.Candidate]
    @EnvironmentObject var scan: ScanViewModel
    @EnvironmentObject var cleanup: CleanupService
    @EnvironmentObject var helper: HelperClient
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var didInit = false

    /// Candidates that have not already been cleaned this session.
    private var pending: [CleanupPlanner.Candidate] {
        cleanup.pending(from: candidates)
    }
    private var userActionable: [CleanupPlanner.Candidate] {
        pending.filter { $0.eligibility == .userVaultMove || $0.eligibility == .loginItemRemoval }
    }
    private var systemActionable: [CleanupPlanner.Candidate] {
        pending.filter { $0.eligibility == .requiresHelper }
    }
    /// Selected IDs that are still pending (stale selections drop out).
    private var effectiveSelection: [CleanupPlanner.Candidate] {
        pending.filter { selected.contains($0.itemID) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !userActionable.isEmpty { userSection }
                    if !systemActionable.isEmpty { systemSection }
                    if pending.isEmpty && !cleanup.performed.isEmpty { allDoneNote }
                    if !cleanup.performed.isEmpty { resultsSection }
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 540)
        .onAppear {
            guard !didInit else { return }
            didInit = true
            selected = Set(pending.map(\.itemID))
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "bandage.fill")
                .font(.system(size: 26)).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Clean Up Broken Startup Items").font(.title3.bold())
                Text("Leftovers that can't run anymore — the usual source of mystery login errors.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private var userSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fix now (reversible)").font(.headline)
            Text("Moved to BootCaptain's vault — nothing is deleted, and every change can be undone.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(userActionable) { row($0) }
        }
    }

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("System items — needs administrator approval", systemImage: "lock.shield")
                .font(.headline)
            Text("These live in /Library and need root. BootCaptain's helper asks for admin approval once, then moves them to a protected, reversible vault. Nothing is deleted.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(systemActionable) { row($0) }
        }
    }

    private func row(_ candidate: CleanupPlanner.Candidate) -> some View {
        Toggle(isOn: binding(for: candidate.itemID)) {
            VStack(alignment: .leading, spacing: 1) {
                Text(candidate.displayName).fontWeight(.medium)
                Text(candidate.reason).font(.caption).foregroundStyle(.secondary)
                if let path = candidate.sourcePath {
                    Text(path).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
        }
        .toggleStyle(.checkbox)
    }

    private var allDoneNote: some View {
        Label("All broken items handled.", systemImage: "checkmark.seal.fill")
            .foregroundStyle(.green)
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Results").font(.headline)
            ForEach(cleanup.performed) { action in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: action.outcome.status == .committed
                          ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(action.outcome.status == .committed ? .green : .orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(action.candidate.displayName).fontWeight(.medium)
                        Text(action.outcome.message).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if action.inverse != nil && !action.undone {
                        Button("Undo") { Task { await cleanup.undo(action, helper: helper) } }
                            .controlSize(.small)
                            .disabled(cleanup.isWorking)
                    } else if action.undone {
                        Text("Undone").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if cleanup.isWorking { ProgressView().controlSize(.small) }
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button {
                Task {
                    await cleanup.perform(effectiveSelection, helper: helper)
                    scan.scan(diagnose: false)
                }
            } label: {
                let n = effectiveSelection.count
                Text(n == 0 ? "Clean Up" : "Clean Up \(n) Item\(n == 1 ? "" : "s")")
            }
            .keyboardShortcut(.defaultAction)
            .disabled(effectiveSelection.isEmpty || cleanup.isWorking)
        }
        .padding(16)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selected.contains(id) },
            set: { on in if on { selected.insert(id) } else { selected.remove(id) } })
    }
}
