import Foundation

/// A parsed crontab entry. PLAN.md §6.1: disabling means commenting a single
/// entry out and reinstalling the whole tab via `crontab`, preserving comments
/// and environment; never `crontab -r`.
public struct CronEntry: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case schedule([String])   // 5 time fields
        case special(String)      // @reboot, @daily, …
    }
    public var kind: Kind
    public var command: String
    /// For `/etc/crontab` (system) the user column; nil for a user crontab.
    public var user: String?
    /// Raw source line (used for exact round-trip / commenting).
    public var rawLine: String
    /// Index within the file, for stable identity.
    public var lineNumber: Int
    public var isDisabledByBootCaptain: Bool

    public init(
        kind: Kind, command: String, user: String? = nil,
        rawLine: String, lineNumber: Int, isDisabledByBootCaptain: Bool = false
    ) {
        self.kind = kind
        self.command = command
        self.user = user
        self.rawLine = rawLine
        self.lineNumber = lineNumber
        self.isDisabledByBootCaptain = isDisabledByBootCaptain
    }

    public var runsAtReboot: Bool {
        if case .special(let s) = kind { return s == "@reboot" }
        return false
    }
}

public enum CronParseStyle: Sendable {
    case userCrontab    // /usr/lib/cron/tabs/<user> — no user column
    case systemCrontab  // /etc/crontab — has a user column
}

public enum CronParser {
    public static let version = "1"
    static let disableMarker = "# BOOTCAPTAIN-DISABLED: "

    public static func parse(_ text: String, style: CronParseStyle) -> [CronEntry] {
        var entries: [CronEntry] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (i, raw) in lines.enumerated() {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // A BootCaptain-disabled entry is the original commented behind a marker.
            var effective = trimmed
            var disabled = false
            if trimmed.hasPrefix(disableMarker) {
                effective = String(trimmed.dropFirst(disableMarker.count))
                disabled = true
            } else if trimmed.hasPrefix("#") {
                continue // ordinary comment / env
            }
            // Environment assignments (FOO=bar) aren't entries.
            if !effective.hasPrefix("@") && effective.range(of: "^[A-Za-z_][A-Za-z0-9_]*=", options: .regularExpression) != nil {
                continue
            }

            if let entry = parseEntry(effective, style: style, rawLine: line,
                                      lineNumber: i, disabled: disabled) {
                entries.append(entry)
            }
        }
        return entries
    }

    private static func parseEntry(
        _ text: String, style: CronParseStyle, rawLine: String,
        lineNumber: Int, disabled: Bool
    ) -> CronEntry? {
        let fields = text.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard !fields.isEmpty else { return nil }

        if fields[0].hasPrefix("@") {
            let special = fields[0]
            var rest = Array(fields.dropFirst())
            var user: String? = nil
            if style == .systemCrontab, !rest.isEmpty { user = rest.removeFirst() }
            guard !rest.isEmpty else { return nil }
            return CronEntry(
                kind: .special(special), command: rest.joined(separator: " "),
                user: user, rawLine: rawLine, lineNumber: lineNumber,
                isDisabledByBootCaptain: disabled)
        }

        // 5 time fields, then (system: user) then command.
        let timeFieldCount = 5
        guard fields.count > timeFieldCount else { return nil }
        let timeFields = Array(fields[0..<timeFieldCount])
        var rest = Array(fields[timeFieldCount...])
        var user: String? = nil
        if style == .systemCrontab, !rest.isEmpty { user = rest.removeFirst() }
        guard !rest.isEmpty else { return nil }
        return CronEntry(
            kind: .schedule(timeFields), command: rest.joined(separator: " "),
            user: user, rawLine: rawLine, lineNumber: lineNumber,
            isDisabledByBootCaptain: disabled)
    }

    /// Produce a new crontab body with `target` commented out behind the marker,
    /// preserving every other line exactly. Reversible: re-running with the same
    /// line un-comments it. This is the body handed to `crontab <file>`.
    public static func toggle(_ text: String, lineNumber: Int, disable: Bool) -> String {
        var lines = text.components(separatedBy: "\n")
        guard lineNumber >= 0, lineNumber < lines.count else { return text }
        let line = lines[lineNumber]
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if disable {
            guard !trimmed.hasPrefix(disableMarker) else { return text }
            lines[lineNumber] = disableMarker + trimmed
        } else {
            guard trimmed.hasPrefix(disableMarker) else { return text }
            lines[lineNumber] = String(trimmed.dropFirst(disableMarker.count))
        }
        return lines.joined(separator: "\n")
    }
}
