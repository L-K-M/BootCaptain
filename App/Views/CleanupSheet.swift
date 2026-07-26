import SwiftUI
import BootCaptainCore

/// The built-in "Clean Up" flow: broken and orphaned startup leftovers, with a
/// reversible one-click fix for everything the current user can act on.
struct CleanupSheet: View {
    let candidates: [CleanupPlanner.Candidate]
    @EnvironmentObject var scan: ScanViewModel
    @EnvironmentObject var cleanup: CleanupService
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var ran = false

    private var actionable: [CleanupPlanner.Candidate] {
        candidates.filter { $0.eligibility != .requiresHelper }
    }
    private var helperGated: [CleanupPlanner.Candidate] {
        candidates.filter { $0.eligibility == .requiresHelper }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !actionable.isEmpty { actionableSection }
                    if !helperGated.isEmpty { gatedSection }
                    if ran && !cleanup.performed.isEmpty { resultsSection }
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 520)
        .onAppear {
            selected = Set(actionable.map(\.itemID))
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

    private var actionableSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fix now (reversible)").font(.headline)
            Text("Files are moved to BootCaptain's vault — nothing is deleted, and every change can be undone.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(actionable) { candidate in
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
        }
    }

    private var gatedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Needs the privileged helper", systemImage: "lock.fill")
                .font(.headline)
            Text("These live in system locations and need root. Privileged cleanup is disabled in this prototype until the safety work in PLAN.md is complete.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(helperGated) { candidate in
                VStack(alignment: .leading, spacing: 1) {
                    Text(candidate.displayName).foregroundStyle(.secondary)
                    if let path = candidate.sourcePath {
                        Text(path).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                .padding(.leading, 2)
            }
        }
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
                        Button("Undo") { Task { await cleanup.undo(action) } }
                            .controlSize(.small)
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
                    let chosen = actionable.filter { selected.contains($0.itemID) }
                    await cleanup.perform(chosen)
                    ran = true
                    scan.scan(diagnose: false)
                }
            } label: {
                Text(selected.isEmpty ? "Clean Up" : "Clean Up \(selected.count) Item\(selected.count == 1 ? "" : "s")")
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selected.isEmpty || cleanup.isWorking)
        }
        .padding(16)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selected.contains(id) },
            set: { on in if on { selected.insert(id) } else { selected.remove(id) } })
    }
}
