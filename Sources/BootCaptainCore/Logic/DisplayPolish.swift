import Foundation

/// Display-name and list-noise helpers. Pure string logic, fully unit-tested;
/// nothing here affects trust, state, or actions — presentation only.
public enum DisplayPolish {
    /// Transient launchd registrations that are NOT startup items and must not
    /// be listed. Launch Services registers every running GUI app in the gui
    /// domain under `application.<bundle-id>.<asn>.<asn>` (documented launchctl
    /// clutter — PLAN.md §3's "several legitimate explanations" for live-only
    /// records). They vanish at logout and carry no persistence.
    public static func isTransientLaunchdLabel(_ label: String) -> Bool {
        // A UUID is legal in persistent labels and is not evidence of transience.
        label.hasPrefix("application.")
    }

    /// A friendlier fallback title for a raw reverse-DNS label when attribution
    /// found nothing better. Never used for identity — display only.
    /// "2BUA8C4S2C.com.1password.browser-helper" -> "1password browser-helper"
    /// "com.foo.helperd" -> "foo helperd"
    public static func prettifyLabel(_ label: String) -> String {
        var parts = label.split(separator: ".").map(String.init)
        // Drop a leading 10-char Team-ID-looking component (A-Z/0-9).
        if let first = parts.first, first.count == 10,
           first.allSatisfy({ $0.isUppercase || $0.isNumber }) {
            parts.removeFirst()
        }
        // Drop reverse-DNS TLD-ish components from the front.
        let tlds: Set<String> = ["com", "org", "net", "io", "ch", "de", "us", "co", "app", "ai"]
        while let first = parts.first, tlds.contains(first.lowercased()), parts.count > 1 {
            parts.removeFirst()
        }
        // Drop trailing pure-numeric components (ASN-style suffixes).
        while let last = parts.last, last.allSatisfy(\.isNumber), parts.count > 1 {
            parts.removeLast()
        }
        guard !parts.isEmpty else { return label }
        // First remaining component is usually the vendor; keep it and the rest.
        return parts.joined(separator: " ")
    }
}
