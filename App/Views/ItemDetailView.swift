import SwiftUI
import BootCaptainCore

struct ItemDetailView: View {
    let item: StartupItem
    @EnvironmentObject var helper: HelperClient
    @EnvironmentObject var scan: ScanViewModel
    @EnvironmentObject var cleanup: CleanupService
    @State private var actionMessage: String?
    @State private var working = false

    /// The cleanup plan for just this item, when it's broken enough to qualify.
    private var cleanupCandidate: CleanupPlanner.Candidate? {
        cleanup.candidates(from: [item]).first
    }

    private func cleanupButtonTitle(_ c: CleanupPlanner.Candidate) -> String {
        switch c.eligibility {
        case .userVaultMove: return "Move LaunchAgent File to Vault"
        case .loginItemRemoval: return "Remove Login Item (session undo)"
        case .requiresHelper: return "Review Administrator Action"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                badges
                if !item.triggerChips.isEmpty { triggers }
                if let d = item.diagnosis { diagnosis(d) }
                actions
                facts
                if !item.notes.isEmpty { notes }
                signing
                provenance
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ItemIcon(item: item, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName).font(.title2.bold())
                Text(item.mechanism.displayName).foregroundStyle(.secondary)
                if let vendor = item.attribution.vendorName, vendor != item.displayName {
                    Text("by \(vendor)").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var badges: some View {
        HStack(spacing: 10) {
            Badge(text: item.trust.displayName, color: UIModel.trustColor(item.trust),
                  systemImage: "checkmark.seal")
            Badge(text: item.health.displayName, color: UIModel.healthColor(item.health),
                  systemImage: UIModel.healthSymbol(item.health))
            Badge(text: item.actionClass.displayName, color: UIModel.actionColor(item.actionClass),
                  systemImage: "hand.raised")
            if item.attribution.hasConflict {
                Badge(text: "Conflicting identity", color: .orange, systemImage: "exclamationmark.bubble")
            }
        }
    }

    private var triggers: some View {
        Section2("Why it runs") {
            HStack {
                ForEach(item.triggerChips, id: \.self) { chip in
                    Text(chip).font(.caption).padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
            }
        }
    }

    private func diagnosis(_ d: Diagnosis) -> some View {
        Section2("Startup evidence") {
            HStack {
                Circle().fill(UIModel.evidenceColor(d.state)).frame(width: 9, height: 9)
                Text(d.state.displayName).bold()
                Text("· \(d.confidence.rawValue) confidence").foregroundStyle(.secondary).font(.caption)
            }
            ForEach(Array(d.evidence.enumerated()), id: \.offset) { _, e in
                VStack(alignment: .leading, spacing: 1) {
                    Text("• \(e.summary)").font(.callout)
                    if let raw = e.rawObservation {
                        Text(raw).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(d.coverageGaps, id: \.self) { gap in
                Label(gap, systemImage: "eye.slash").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var actions: some View {
        Section2("Actions") {
            // Built-in cleanup for provably-broken items the user can fix
            // without root: reversible vault move / login-item removal.
            if let candidate = cleanupCandidate, !cleanup.completedItemIDs.contains(candidate.itemID) {
                if candidate.eligibility == .requiresHelper {
                    Label(cleanupButtonTitle(candidate), systemImage: "lock.shield")
                        .foregroundStyle(.secondary)
                    Text("Use the Clean Up review to see the prototype warning and explicitly confirm any helper-backed action.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack {
                        Button {
                            Task {
                                await cleanup.perform([candidate], helper: helper)
                                actionMessage = cleanup.performed.last?.outcome.message
                                scan.scan(diagnose: false)
                            }
                        } label: {
                            Label(cleanupButtonTitle(candidate), systemImage: "bandage.fill")
                        }
                        .buttonStyle(.borderedProminent).tint(.orange)
                        .disabled(cleanup.isWorking)
                        if cleanup.isWorking { ProgressView().controlSize(.small) }
                    }
                    Text("\(candidate.reason) In-app undo history lasts only for this session.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider().padding(.vertical, 2)
            }
            switch item.actionClass {
            case .reversibleMutation:
                HStack {
                    Button {
                        Task { await perform(disable: item.state.effectivelyEnabled != .no) }
                    } label: {
                        Label(item.state.effectivelyEnabled == .no ? "Enable at Startup" : "Disable (reversible)",
                              systemImage: "switch.2")
                    }
                    .disabled(working)
                    if working { ProgressView().controlSize(.small) }
                }
                Text("BootCaptain records an undo before changing anything. Nothing is deleted.")
                    .font(.caption).foregroundStyle(.secondary)
            case .guidedAction:
                Button {
                    helper.openLoginItemsSettings()
                } label: {
                    Label("Open in System Settings", systemImage: "arrow.up.forward.app")
                }
                Text("This item is controlled by its owning app or the system; BootCaptain sends you to the right place.")
                    .font(.caption).foregroundStyle(.secondary)
            case .readOnly:
                Label("Read-only", systemImage: "lock").foregroundStyle(.secondary)
                if let reason = item.notes.first(where: { $0.contains("policy") || $0.contains("system") || $0.contains("Managed") }) {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let msg = actionMessage {
                Text(msg).font(.caption).foregroundStyle(.secondary).padding(.top, 2)
            }
        }
    }

    private var facts: some View {
        Section2("Details") {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                if let label = item.label { Fact("Label", label) }
                if let domain = item.domain { Fact("Domain", domain) }
                if let path = item.sourcePath { Fact("Source", path) }
                if let exec = item.recipe?.executablePath { Fact("Executable", exec) }
                if let team = item.attribution.teamIdentifier { Fact("Team ID", team) }
                Fact("Effective state", item.state.effectivelyEnabled.rawValue)
                Fact("Loaded", item.state.loaded.rawValue)
                Fact("Running", item.state.running.rawValue)
            }
        }
    }

    private var notes: some View {
        Section2("Notes") {
            ForEach(item.notes, id: \.self) { note in
                Text("• \(note)").font(.callout).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var signing: some View {
        if !item.signing.isEmpty {
            Section2("Code signature") {
                ForEach(Array(item.signing.enumerated()), id: \.offset) { _, s in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.authority ?? (s.isValid == .yes ? "Signed" : "Unsigned"))
                            .font(.callout)
                        HStack(spacing: 10) {
                            if let arch = s.architecture { Text(arch).font(.caption).foregroundStyle(.secondary) }
                            Text("valid: \(s.isValid.rawValue)").font(.caption).foregroundStyle(.secondary)
                            if s.isPlatformBinary { Text("platform").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }
    }

    private var provenance: some View {
        Section2("Where this came from") {
            ForEach(Array(item.provenance.enumerated()), id: \.offset) { _, p in
                Text("\(p.collector): \(p.source)")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
    }

    private func perform(disable: Bool) async {
        working = true; defer { working = false }
        let op: ActionRequest.Operation = item.mechanism == .cron ? .cronToggleEntry
            : (disable ? .launchdDisable : .launchdEnable)
        let request = ActionRequest(
            operation: op, itemID: item.id, label: item.label,
            domain: item.domain ?? "system", sourcePath: item.sourcePath)
        let outcome = await helper.perform(request)
        actionMessage = outcome.message
        if outcome.status == .committed { scan.scan(diagnose: false) }
    }
}

// MARK: small components

private struct Badge: View {
    let text: String; let color: Color; let systemImage: String
    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

private struct Section2<Content: View>: View {
    let title: String; @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content
        }
    }
}

private struct Fact: View {
    let key: String; let value: String
    init(_ key: String, _ value: String) { self.key = key; self.value = value }
    var body: some View {
        GridRow {
            Text(key).foregroundStyle(.secondary).gridColumnAlignment(.leading)
            Text(value).textSelection(.enabled).font(.callout)
        }
    }
}
