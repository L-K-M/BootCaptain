import Foundation

/// `launchctl` output is explicitly **not API** (`launchctl(1)` CAVEATS), so
/// every field is optional and parse failure is reported, never treated as a
/// missing job (PLAN.md §3, EVIDENCE L-05).

/// One row of `launchctl list`: `PID<TAB>Status<TAB>Label`.
public struct LaunchctlListEntry: Sendable, Equatable {
    public var pid: Int?          // nil when "-"
    public var lastExitStatus: Int?
    public var label: String
    public init(pid: Int?, lastExitStatus: Int?, label: String) {
        self.pid = pid
        self.lastExitStatus = lastExitStatus
        self.label = label
    }
    public var isRunning: Bool { pid != nil }
}

public enum LaunchctlListParser {
    public static let version = "1"

    public static func parse(_ text: String) -> [LaunchctlListEntry] {
        var out: [LaunchctlListEntry] = []
        for (i, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(rawLine)
            if line.isEmpty { continue }
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard cols.count >= 3 else { continue }
            // Header row: PID  Status  Label
            if i == 0 && cols[0] == "PID" { continue }
            let pid = cols[0] == "-" ? nil : Int(cols[0])
            let status = Int(cols[1])
            let label = cols[2...].joined(separator: "\t")
            if label.isEmpty { continue }
            out.append(LaunchctlListEntry(pid: pid, lastExitStatus: status, label: label))
        }
        return out
    }
}

/// A service extracted from a `launchctl print <domain>` dump.
public struct LaunchctlPrintService: Sendable, Equatable {
    public var label: String
    public var pid: Int?
    public var lastExitCode: Int?
    public var path: String?      // origin plist, when present
    public var runs: Int?
    public var state: String?
    public init(
        label: String, pid: Int? = nil, lastExitCode: Int? = nil,
        path: String? = nil, runs: Int? = nil, state: String? = nil
    ) {
        self.label = label
        self.pid = pid
        self.lastExitCode = lastExitCode
        self.path = path
        self.runs = runs
        self.state = state
    }
}

/// Parses the `services = { ... }` block of `launchctl print <domain>` plus the
/// per-service detail form `launchctl print <domain>/<label>`.
public enum LaunchctlPrintParser {
    public static let version = "1"

    /// Parse the domain-level `services = { pid status label }` table.
    public static func parseServices(_ text: String) -> [LaunchctlPrintService] {
        var out: [LaunchctlPrintService] = []
        var inServices = false
        var depth = 0
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if !inServices {
                if line.hasPrefix("services = {") { inServices = true; depth = 1 }
                continue
            }
            if line == "}" { depth -= 1; if depth == 0 { break }; continue }
            if line.isEmpty { continue }
            // Rows look like: "  12345   0   com.example.agent"
            //             or: "  -        78  com.example.broken"
            let cols = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                .map(String.init).filter { !$0.isEmpty }
            guard cols.count >= 3 else { continue }
            let pid = cols[0] == "-" ? nil : Int(cols[0])
            let status = cols[1] == "-" ? nil : Int(cols[1])
            let label = cols[2...].joined(separator: " ")
            out.append(LaunchctlPrintService(
                label: label, pid: pid, lastExitCode: status))
        }
        return out
    }

    /// Parse a per-service detail dump into one service record.
    public static func parseDetail(_ text: String) -> LaunchctlPrintService? {
        var label: String?
        var pid: Int?
        var lastExit: Int?
        var path: String?
        var runs: Int?
        var state: String?
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let v = value(after: "=", in: line, key: "path") { path = v }
            else if let v = value(after: "=", in: line, key: "state") { state = v }
            else if let v = value(after: "=", in: line, key: "pid") { pid = Int(v) }
            else if let v = value(after: "=", in: line, key: "runs") { runs = Int(v) }
            else if let v = value(after: "=", in: line, key: "last exit code") { lastExit = Int(v) }
            else if line.hasSuffix("= {"), label == nil {
                // The dump opens with `com.example.foo = {`
                let name = line.replacingOccurrences(of: "= {", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if name.contains(".") { label = name }
            }
        }
        guard let label else { return nil }
        return LaunchctlPrintService(
            label: label, pid: pid, lastExitCode: lastExit,
            path: path, runs: runs, state: state)
    }

    private static func value(after sep: String, in line: String, key: String) -> String? {
        guard line.hasPrefix(key) else { return nil }
        let rest = line.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
        guard rest.hasPrefix(sep) else { return nil }
        return String(rest.dropFirst(sep.count)).trimmingCharacters(in: .whitespaces)
    }
}

/// Parses `launchctl print-disabled <domain>` — lines like
/// `"com.example.agent" => disabled` / `=> enabled`.
public enum LaunchctlDisabledParser {
    public static let version = "1"

    /// Returns label -> OverrideState for every listed entry.
    public static func parse(_ text: String) -> [String: OverrideState] {
        var out: [String: OverrideState] = [:]
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.contains("=>") else { continue }
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let label = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: " \t\""))
            let value = parts[1].trimmingCharacters(in: .whitespaces).lowercased()
            guard !label.isEmpty else { continue }
            if value.contains("disabled") || value == "true" {
                out[label] = .disabled
            } else if value.contains("enabled") || value == "false" {
                out[label] = .explicitEnabled
            } else {
                out[label] = .unknown
            }
        }
        return out
    }
}
