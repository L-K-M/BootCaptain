import SwiftUI
import BootCaptainCore

struct ContentView: View {
    @EnvironmentObject var scan: ScanViewModel
    @EnvironmentObject var helper: HelperClient
    @EnvironmentObject var cleanup: CleanupService
    @State private var showCleanup = false

    private var cleanupCandidates: [CleanupPlanner.Candidate] {
        cleanup.candidates(from: scan.items)
    }

    var body: some View {
        NavigationSplitView {
            Sidebar()
        } detail: {
            if scan.isScanning && scan.items.isEmpty {
                ScanningDetail()
            } else if let item = scan.item(id: scan.selection) {
                ItemDetailView(item: item)
            } else {
                EmptyDetail(cleanupCount: cleanupCandidates.count,
                            showCleanup: $showCleanup)
            }
        }
        .toolbar { Toolbar(cleanupCount: cleanupCandidates.count, showCleanup: $showCleanup) }
        .safeAreaInset(edge: .bottom) { CoverageBanner() }
        .sheet(isPresented: $showCleanup) {
            CleanupSheet(candidates: cleanupCandidates)
        }
    }
}

private struct Sidebar: View {
    @EnvironmentObject var scan: ScanViewModel

    var body: some View {
        VStack(spacing: 0) {
            // A menu-style picker stays compact at any sidebar width; the
            // five-way segmented control overflowed and clipped its ends.
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.secondary)
                Picker("Show", selection: $scan.filter) {
                    ForEach(ScanViewModel.Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                Spacer()
                Text("\(scan.filteredItems.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            List(selection: $scan.selection) {
                ForEach(scan.groupedByTier, id: \.0) { tier, items in
                    Section(UIModel.tierTitle(tier)) {
                        ForEach(items) { item in
                            ItemRow(item: item).tag(item.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .searchable(text: $scan.searchText, placement: .sidebar, prompt: "Search items, vendors, paths")
        .frame(minWidth: 320)
    }
}

/// One sidebar row: real app icon, name, vendor · mechanism, and a status dot
/// only when there is something to say (broken/failing/orphaned/red-flag).
private struct ItemRow: View {
    let item: StartupItem

    var body: some View {
        HStack(spacing: 9) {
            ItemIcon(item: item, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName).lineLimit(1)
                Text(subtitle)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            trailingStatus
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        if let vendor = item.attribution.vendorName,
           !vendor.isEmpty, vendor != item.displayName {
            return "\(vendor) · \(item.mechanism.displayName)"
        }
        return item.mechanism.displayName
    }

    @ViewBuilder private var trailingStatus: some View {
        switch item.health {
        case .broken, .failing:
            StatusDot(color: .red)
        case .possiblyOrphaned:
            StatusDot(color: .orange)
        case .ok, .unknown:
            if item.trust == .brokenOrConflicting {
                StatusDot(color: .red)
            } else if item.state.running == .yes {
                StatusDot(color: .green)
            }
        }
    }
}

private struct StatusDot: View {
    let color: Color
    var body: some View {
        Circle().fill(color).frame(width: 7, height: 7)
            .padding(.trailing, 2)
    }
}

/// Shared item icon: the resolved app icon, else a tinted mechanism symbol.
struct ItemIcon: View {
    let item: StartupItem
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let image = IconStore.shared.icon(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size, height: size)
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(fallbackColor.opacity(0.16))
                    .overlay(
                        Image(systemName: fallbackSymbol)
                            .font(.system(size: size * 0.5, weight: .medium))
                            .foregroundStyle(fallbackColor)
                    )
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }

    private var isApple: Bool {
        item.trust == .applePlatform || item.trust == .appleDistributed
    }

    private var fallbackSymbol: String {
        if isApple { return "apple.logo" }
        switch item.mechanism {
        case .launchDaemon, .smAppServiceDaemon: return "gearshape.2"
        case .launchAgent, .smAppServiceAgent: return "person.crop.circle.badge.clock"
        case .classicLoginItem, .smAppServiceLoginItem: return "arrow.right.circle"
        case .windowRestoration: return "macwindow.on.rectangle"
        case .cron, .at, .periodic: return "clock.arrow.circlepath"
        case .kernelExtension, .systemExtension: return "puzzlepiece.extension"
        case .audioHALPlugin: return "waveform"
        case .authorizationPlugin: return "key"
        case .configurationProfile, .managedBackgroundTask: return "building.2"
        case .shellStartup, .sshStartup: return "terminal"
        default: return "shippingbox"
        }
    }

    private var fallbackColor: Color {
        if isApple { return .secondary }
        switch item.health {
        case .broken, .failing: return .red
        case .possiblyOrphaned: return .orange
        default: return .accentColor
        }
    }
}

private struct Toolbar: ToolbarContent {
    @EnvironmentObject var scan: ScanViewModel
    let cleanupCount: Int
    @Binding var showCleanup: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup {
            if cleanupCount > 0 {
                Button { showCleanup = true } label: {
                    Label("Clean Up (\(cleanupCount))", systemImage: "bandage")
                }
                .help("Review and fix broken startup leftovers")
            }
            // Scanning state lives INSIDE the Rescan button (its icon becomes a
            // spinner) — a bare ProgressView in a ToolbarItemGroup renders as
            // its own toolbar item and escapes the buttons' capsule.
            Button { scan.scan(diagnose: false) } label: {
                if scan.isScanning {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
            }
            .disabled(scan.isScanning)
            .help(scan.isScanning ? "Scanning…" : "Rescan startup items")
            Button { scan.scan(diagnose: true) } label: {
                Label("Boot Audit", systemImage: "stethoscope")
            }
            .disabled(scan.isScanning)
            .help("Scan and correlate boot/login failure evidence")
        }
    }
}

private struct EmptyDetail: View {
    @EnvironmentObject var scan: ScanViewModel
    let cleanupCount: Int
    @Binding var showCleanup: Bool

    private var brokenCount: Int {
        scan.items.filter { $0.health == .broken || $0.health == .failing
            || $0.health == .possiblyOrphaned }.count
    }
    private var runningCount: Int {
        scan.items.filter { $0.state.running == .yes }.count
    }
    private var loginCount: Int {
        scan.items.filter { $0.triggers.runsAtStartup }.count
    }

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Image(systemName: "sailboat.fill")
                    .font(.system(size: 46)).foregroundStyle(.tint)
                Text("BootCaptain").font(.title.bold())
                Text("Everything that starts with your Mac, explained.")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                StatTile(value: scan.items.count, label: "startup items", symbol: "list.bullet")
                StatTile(value: loginCount, label: "launch at login", symbol: "bolt.fill")
                StatTile(value: runningCount, label: "running now", symbol: "play.fill")
                StatTile(value: brokenCount, label: "broken", symbol: "bandage.fill",
                         tint: brokenCount > 0 ? .orange : .secondary)
            }

            if cleanupCount > 0 {
                Button {
                    showCleanup = true
                } label: {
                    Label("Clean Up \(cleanupCount) Broken Item\(cleanupCount == 1 ? "" : "s")…",
                          systemImage: "bandage.fill")
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }

            Text("Select an item to see who it belongs to, why it runs, and what its startup evidence says.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct StatTile: View {
    let value: Int
    let label: String
    let symbol: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(tint)
            Text("\(value)").font(.title2.bold().monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 108, height: 84)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ScanningDetail: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("Scanning startup items…").font(.title3.weight(.medium))
            Text("Reading launchd, Background Task Management, login items, and more.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
