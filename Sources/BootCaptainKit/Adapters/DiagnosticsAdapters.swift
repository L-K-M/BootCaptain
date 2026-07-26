import Foundation
import BootCaptainCore

/// Runs `log show` over a bounded window and returns parsed records plus honest
/// coverage (PLAN.md §7). A zero-match result means "no accessible match", never
/// "did not run"; the query's own success is reported separately from evidence
/// coverage.
public struct UnifiedLogAdapter: Sendable {
    public init() {}

    public struct Query: Sendable {
        public var lastBoot: Bool
        public var subsystems: [String]
        public init(lastBoot: Bool = true,
                    subsystems: [String] = UnifiedLogMatchers.subsystems) {
            self.lastBoot = lastBoot
            self.subsystems = subsystems
        }
    }

    public struct Outcome: Sendable {
        public var records: [LogRecord]
        public var querySucceeded: Bool
        public var coverageNote: String
    }

    public func fetch(_ query: Query, runner: CommandRunner) -> Outcome {
        let predicate = query.subsystems
            .map { "subsystem == \"\($0)\"" }
            .joined(separator: " OR ")
        var args = ["show", "--style", "ndjson", "--info", "--predicate", predicate]
        if query.lastBoot { args.append(contentsOf: ["--last", "boot"]) }
        let res = runner.run("/usr/bin/log", args, timeout: 120)
        guard res.succeeded else {
            return Outcome(records: [], querySucceeded: false,
                coverageNote: "log show failed (exit \(res.status)); standard users get no entries.")
        }
        let records = UnifiedLogMatchers.parseNDJSON(res.stdout)
        let note = records.isEmpty
            ? "Query ran but returned no accessible entries for the window (not proof of no execution)."
            : "\(records.count) log records over the last boot."
        return Outcome(records: records, querySucceeded: true, coverageNote: note)
    }
}

/// Reads `.ips` crash reports from the user and (admin-readable) system
/// DiagnosticReports directories (PLAN.md §7). Admin-readable, so the app
/// process can read the system dir without the root helper.
public struct DiagnosticReportsAdapter: Sendable {
    public init() {}

    public func reports(userHome: String, fileManager: FileManager = .default) -> [CrashReport] {
        var out: [CrashReport] = []
        let dirs = [
            userHome + "/Library/Logs/DiagnosticReports",
            "/Library/Logs/DiagnosticReports",
        ]
        for dir in dirs {
            guard let entries = try? fileManager.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where entry.hasSuffix(".ips") {
                let full = dir + "/" + entry
                guard let data = fileManager.contents(atPath: full),
                      let report = CrashReportParser.parse(data) else { continue }
                out.append(report)
            }
        }
        return out
    }
}
