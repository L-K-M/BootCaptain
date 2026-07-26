import SwiftUI
import BootCaptainCore

struct ContentView: View {
    @EnvironmentObject var scan: ScanViewModel
    @EnvironmentObject var helper: HelperClient

    var body: some View {
        NavigationSplitView {
            Sidebar()
        } detail: {
            if scan.isScanning && scan.items.isEmpty {
                ScanningDetail()
            } else if let item = scan.item(id: scan.selection) {
                ItemDetailView(item: item)
            } else {
                EmptyDetail()
            }
        }
        .toolbar { Toolbar() }
        .safeAreaInset(edge: .bottom) { CoverageBanner() }
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

private struct ItemRow: View {
    let item: StartupItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: UIModel.healthSymbol(item.health))
                .foregroundStyle(UIModel.healthColor(item.health))
                .font(.system(size: 12))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName).lineLimit(1)
                Text(item.mechanism.displayName)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if item.actionClass == .reversibleMutation {
                Image(systemName: "switch.2").foregroundStyle(.green).font(.caption)
            }
            if item.trust == .brokenOrConflicting {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.red).font(.caption)
            }
        }
        .padding(.vertical, 1)
    }
}

private struct Toolbar: ToolbarContent {
    @EnvironmentObject var scan: ScanViewModel

    var body: some ToolbarContent {
        ToolbarItemGroup {
            if scan.isScanning { ProgressView().controlSize(.small) }
            Button { scan.scan(diagnose: false) } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .disabled(scan.isScanning)
            Button { scan.scan(diagnose: true) } label: {
                Label("Boot Audit", systemImage: "stethoscope")
            }
            .disabled(scan.isScanning)
        }
    }
}

private struct EmptyDetail: View {
    @EnvironmentObject var scan: ScanViewModel
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sailboat.fill").font(.system(size: 44)).foregroundStyle(.tint)
            Text("BootCaptain").font(.title2.bold())
            Text("\(scan.items.count) startup items across \(scan.groupedByTier.count) tiers.")
                .foregroundStyle(.secondary)
            Text("Select an item to see who it belongs to, why it runs, and whether it's safe to disable.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
