import Foundation

/// A curated catalog entry: plain-language identity and consequence text keyed
/// by Team ID and/or a *bounded* label prefix. PLAN.md §5: catalog data explains
/// consequences but never authorizes a privileged action, and matching must be
/// non-backtracking (no user-supplied regex) to avoid ReDoS (EVIDENCE C-01).
public struct CatalogEntry: Codable, Sendable, Equatable {
    public enum Category: String, Codable, Sendable {
        case updater, sync, backup, vpn, security, peripheral, menuBar, telemetry, other
    }
    public var vendor: String
    public var product: String
    public var purpose: String
    public var category: Category
    /// e.g. "Stops automatic Chrome updates."
    public var disableConsequence: String
    /// Optional pointer to the vendor's own off-switch.
    public var vendorOffSwitch: String?
    public var teamIdentifier: String?
    /// Literal reverse-DNS label prefixes, matched at component boundaries.
    public var labelPrefixes: [String]
    public var reviewDate: String
    public var sourceURL: String?

    public init(
        vendor: String, product: String, purpose: String, category: Category,
        disableConsequence: String, vendorOffSwitch: String? = nil,
        teamIdentifier: String? = nil, labelPrefixes: [String] = [],
        reviewDate: String, sourceURL: String? = nil
    ) {
        self.vendor = vendor
        self.product = product
        self.purpose = purpose
        self.category = category
        self.disableConsequence = disableConsequence
        self.vendorOffSwitch = vendorOffSwitch
        self.teamIdentifier = teamIdentifier
        self.labelPrefixes = labelPrefixes
        self.reviewDate = reviewDate
        self.sourceURL = sourceURL
    }
}

/// Bounded-matching catalog. Lookups use exact Team ID and literal component
/// prefixes only — no regular expressions.
public struct Catalog: Codable, Sendable {
    public var entries: [CatalogEntry]

    public init(entries: [CatalogEntry]) { self.entries = entries }

    /// Best product match for an item. A Team ID identifies a developer account,
    /// not a product, so a component-bounded label match is always required.
    /// When present, Team ID rejects conflicting catalog candidates.
    public func match(teamID: String?, label: String?) -> CatalogEntry? {
        guard let label, !label.isEmpty else { return nil }

        // Longest matching prefix wins for specificity.
        var best: (CatalogEntry, Int)?
        for entry in entries {
            if let expectedTeam = entry.teamIdentifier,
               let teamID, !teamID.isEmpty, expectedTeam != teamID {
                continue
            }
            for prefix in entry.labelPrefixes where matches(label: label, prefix: prefix) {
                if best == nil || prefix.count > best!.1 {
                    best = (entry, prefix.count)
                }
            }
        }
        return best?.0
    }

    private func matches(label: String, prefix: String) -> Bool {
        label == prefix || label.hasPrefix(prefix + ".")
    }

    /// A small seed catalog of common helpers (PLAN.md §5). Stored as data, not
    /// code; a signed, updatable file supersedes this at runtime.
    public static let seed = Catalog(entries: [
        CatalogEntry(vendor: "Google", product: "Google Software Update (Keystone)",
            purpose: "Keeps Chrome and other Google apps up to date.", category: .updater,
            disableConsequence: "Chrome will not update automatically.",
            vendorOffSwitch: "Chrome ▸ About Google Chrome",
            teamIdentifier: "EQHXZ8M8AV",
            labelPrefixes: ["com.google.keystone", "com.google.GoogleUpdater"],
            reviewDate: "2026-07-26"),
        CatalogEntry(vendor: "Microsoft", product: "Microsoft AutoUpdate",
            purpose: "Updates Microsoft 365 and other Microsoft apps.", category: .updater,
            disableConsequence: "Office apps will not update automatically.",
            teamIdentifier: "UBF8T346G9",
            labelPrefixes: ["com.microsoft.update", "com.microsoft.autoupdate",
                            "com.microsoft.OneDriveStandaloneUpdater"],
            reviewDate: "2026-07-26"),
        CatalogEntry(vendor: "Adobe", product: "Adobe Updater / Creative Cloud",
            purpose: "Keeps Adobe apps and Creative Cloud running and updated.",
            category: .updater,
            disableConsequence: "Adobe apps may not update or sync until relaunched.",
            labelPrefixes: ["com.adobe.ARMDC", "com.adobe.acc", "com.adobe.AdobeCreativeCloud"],
            reviewDate: "2026-07-26"),
        CatalogEntry(vendor: "Dropbox", product: "Dropbox",
            purpose: "Syncs your Dropbox folder in the background.", category: .sync,
            disableConsequence: "Files will stop syncing until Dropbox is reopened.",
            vendorOffSwitch: "Dropbox ▸ Preferences ▸ General ▸ Start on system startup",
            labelPrefixes: ["com.dropbox", "com.getdropbox"],
            reviewDate: "2026-07-26"),
        CatalogEntry(vendor: "Zoom", product: "Zoom",
            purpose: "Background helper for faster meeting joins.", category: .menuBar,
            disableConsequence: "Zoom may start more slowly; meetings still work.",
            labelPrefixes: ["us.zoom"],
            reviewDate: "2026-07-26"),
        CatalogEntry(vendor: "Docker", product: "Docker Desktop",
            purpose: "Privileged networking helper for Docker Desktop.", category: .other,
            disableConsequence: "Docker Desktop networking may not work until relaunched.",
            teamIdentifier: "9BNSXJN65R",
            labelPrefixes: ["com.docker"],
            reviewDate: "2026-07-26"),
    ])
}
