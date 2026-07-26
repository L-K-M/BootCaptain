import SwiftUI
import BootCaptainCore

/// The persistent coverage banner (PLAN.md §10): never let a denied/failed
/// collector read as "we covered everything".
struct CoverageBanner: View {
    @EnvironmentObject var scan: ScanViewModel
    @State private var expanded = false

    var body: some View {
        let gaps = scan.coverage.gaps
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                Image(systemName: gaps.isEmpty ? "checkmark.seal.fill" : "eye.trianglebadge.exclamationmark.fill")
                    .foregroundStyle(gaps.isEmpty ? .green : .orange)
                Text(scan.coverage.bannerSummary).font(.callout)
                Spacer()
                if !gaps.isEmpty {
                    Button(expanded ? "Hide" : "Details") { expanded.toggle() }
                        .buttonStyle(.borderless).font(.caption)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 7)

            if expanded {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(gaps) { gap in
                        HStack(spacing: 6) {
                            Image(systemName: symbol(gap.status)).foregroundStyle(.secondary).font(.caption)
                            Text("\(gap.collector): \(gap.status.rawValue)").font(.caption)
                            if let detail = gap.detail {
                                Text("— \(detail)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
        .background(.bar)
    }

    private func symbol(_ s: CollectorCoverage.Status) -> String {
        switch s {
        case .deniedPermission: return "lock.fill"
        case .skippedUnsupported: return "minus.circle"
        case .failed: return "xmark.circle"
        case .partial: return "circle.lefthalf.filled"
        case .notRun: return "pause.circle"
        case .ran, .ranEmpty: return "checkmark"
        }
    }
}
