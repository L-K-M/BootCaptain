import Foundation
import BootCaptainCore

/// Runs the PLAN.md §5 attribution pipeline for one item: collect every signal,
/// score vendor/product separately, surface conflicts. Signing is validated by
/// the caller (the Scanner) before this runs; the trust path drives it.
public struct AttributionEngine: Sendable {
    let catalog: Catalog
    let attributions: AttributionsPlistReader
    let receipts: ReceiptInspector
    let runner: CommandRunner

    public init(
        catalog: Catalog = .seed,
        attributions: AttributionsPlistReader = AttributionsPlistReader(),
        receipts: ReceiptInspector = ReceiptInspector(),
        runner: CommandRunner = ProcessRunner()
    ) {
        self.catalog = catalog
        self.attributions = attributions
        self.receipts = receipts
        self.runner = runner
    }

    public func attribute(_ item: StartupItem) -> (ResolvedAttribution, CatalogEntry?) {
        var signals: [AttributionSignal] = []

        // 1. Bundle containment / executable target → owning .app.
        if let trustPath = item.recipe?.trustPath ?? item.sourcePath,
           let app = Self.owningApp(of: trustPath) {
            signals.append(AttributionSignal(
                kind: .bundleContainment,
                vendorName: nil, productName: (app.name as NSString).deletingPathExtension,
                bundleIdentifier: app.bundleID, iconPath: app.path,
                weight: AttributionScorer.defaultWeight(for: .bundleContainment)))
        }

        // 2. Code signature Team ID / vendor.
        let team = item.signing.first(where: { $0.teamIdentifier != nil })
        if let team, let teamID = team.teamIdentifier {
            signals.append(AttributionSignal(
                kind: .codeSignatureTeamID, vendorName: team.vendorName,
                teamIdentifier: teamID,
                weight: AttributionScorer.defaultWeight(for: .codeSignatureTeamID)))
        }

        // 3. Existing BTM/associated-bundle claim carried on the item.
        if let bundleID = item.attribution.bundleIdentifier {
            signals.append(AttributionSignal(
                kind: .associatedBundleID, bundleIdentifier: bundleID,
                weight: AttributionScorer.defaultWeight(for: .associatedBundleID)))
        }
        // BTM developer name (historical hint).
        if let dev = item.attribution.vendorName, item.attribution.confidence == .low {
            signals.append(AttributionSignal(
                kind: .btmRecord, vendorName: dev,
                weight: AttributionScorer.defaultWeight(for: .btmRecord) * 0.7,
                note: "Developer name recorded by BTM (not verified)."))
        }

        // 4. Apple attributions.plist.
        if let name = attributions.productName(
            identifier: item.label,
            executablePath: item.recipe?.executablePath) {
            signals.append(AttributionSignal(
                kind: .appleAttributionsPlist, productName: name,
                weight: AttributionScorer.defaultWeight(for: .appleAttributionsPlist)))
        }

        // 5. Package receipt.
        if let path = item.sourcePath,
           let pkg = receipts.receiptPackage(for: path, runner: runner) {
            signals.append(AttributionSignal(
                kind: .packageReceipt, vendorName: Self.vendorFromPkgID(pkg),
                weight: AttributionScorer.defaultWeight(for: .packageReceipt),
                note: "Receipt \(pkg) records this path."))
        }

        // 6. Curated catalog (adds plain language; never authorizes actions).
        let catalogEntry = catalog.match(teamID: team?.teamIdentifier, label: item.label)
        if let entry = catalogEntry {
            signals.append(AttributionSignal(
                kind: .curatedCatalog, vendorName: entry.vendor, productName: entry.product,
                teamIdentifier: entry.teamIdentifier,
                weight: AttributionScorer.defaultWeight(for: .curatedCatalog)))
        }

        // 7. Label reverse-DNS heuristic (low confidence).
        if let label = item.label, let hint = Self.reverseDNSVendor(label) {
            signals.append(AttributionSignal(
                kind: .labelHeuristic, vendorName: hint,
                weight: AttributionScorer.defaultWeight(for: .labelHeuristic)))
        }

        var resolved = AttributionScorer.resolve(signals)
        // Preserve an already-known icon/bundle if scoring didn't surface one.
        if resolved.iconPath == nil { resolved.iconPath = item.attribution.iconPath }
        return (resolved, catalogEntry)
    }

    // MARK: helpers

    struct OwningApp { let name: String; let path: String; let bundleID: String? }

    /// Walk up to the outermost `.app` bundle containing `path`.
    static func owningApp(of path: String) -> OwningApp? {
        var components = (path as NSString).pathComponents
        var appIndex: Int?
        for (i, c) in components.enumerated() where c.hasSuffix(".app") {
            appIndex = i  // outermost wins (keep the last-found lowest index? we want first)
            break
        }
        guard let idx = appIndex else { return nil }
        components = Array(components[0...idx])
        let appPath = NSString.path(withComponents: components)
        let name = components[idx]
        let bundleID = bundleIdentifier(atAppPath: appPath)
        return OwningApp(name: name, path: appPath, bundleID: bundleID)
    }

    static func bundleIdentifier(atAppPath appPath: String) -> String? {
        let infoPath = appPath + "/Contents/Info.plist"
        guard let data = FileManager.default.contents(atPath: infoPath),
              let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return nil }
        return dict["CFBundleIdentifier"] as? String
    }

    static func vendorFromPkgID(_ pkg: String) -> String? {
        // com.microsoft.pkg.autoupdate -> "microsoft"
        let parts = pkg.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        return String(parts[1]).capitalized
    }

    static func reverseDNSVendor(_ label: String) -> String? {
        let parts = label.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        let vendor = String(parts[1])
        // Don't echo com.apple as a vendor hint; that's handled by trust.
        if parts[0] == "com" && vendor == "apple" { return nil }
        return vendor.capitalized
    }
}
