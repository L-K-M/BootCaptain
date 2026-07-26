import Foundation

/// A parsed `.ips` crash report (PLAN.md §7). Since Monterey these are **two
/// concatenated JSON documents** — a header line then the body — so the file as
/// a whole is not valid JSON and must be split on the first newline. Not every
/// `.ips` shape is a crash (`bug_type`), so the type is detected first.
public struct CrashReport: Sendable, Equatable {
    public var bugType: String?
    public var procName: String?
    public var procPath: String?
    public var parentPid: Int?
    public var responsiblePid: Int?
    public var captureTime: String?
    public var terminationNamespace: String?
    /// Human-readable termination detail (e.g. "Library not loaded: /path").
    public var terminationReason: String?
    public var exceptionType: String?
    public var signal: String?

    public init() {}

    public var isCrash: Bool { bugType == "309" || bugType == "crash" }
    /// A crash whose parent is launchd (pid 1) is likely an agent/daemon — but
    /// pid 1 can also be a reparented orphan, so this is correlation only.
    public var parentIsLaunchd: Bool { parentPid == 1 }
}

public enum CrashReportParser {
    public static let version = "1"

    /// Parse the header + body of an `.ips` file.
    public static func parse(_ data: Data) -> CrashReport? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return parse(text)
    }

    public static func parse(_ text: String) -> CrashReport? {
        // Split into the first-line header JSON and the remaining body JSON.
        guard let newline = text.firstIndex(of: "\n") else { return nil }
        let headerStr = String(text[..<newline])
        let bodyStr = String(text[text.index(after: newline)...])

        var report = CrashReport()

        if let headerData = headerStr.data(using: .utf8),
           let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any] {
            report.bugType = stringify(header["bug_type"])
            report.procName = header["app_name"] as? String ?? header["name"] as? String
            report.captureTime = header["timestamp"] as? String
        }

        guard let bodyData = bodyStr.data(using: .utf8),
              let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        else {
            // Header alone is still a usable (if thin) record.
            return report.procName != nil || report.bugType != nil ? report : nil
        }

        report.procName = report.procName ?? (body["procName"] as? String)
        report.procPath = body["procPath"] as? String
        report.parentPid = intValue(body["parentPid"])
        report.responsiblePid = intValue(body["responsiblePid"])
        report.captureTime = report.captureTime ?? (body["captureTime"] as? String)

        if let termination = body["termination"] as? [String: Any] {
            report.terminationNamespace = termination["namespace"] as? String
            report.terminationReason = termination["indicator"] as? String
                ?? stringify(termination["code"])
        }
        if let exception = body["exception"] as? [String: Any] {
            report.exceptionType = exception["type"] as? String
            report.signal = exception["signal"] as? String
        }
        return report
    }

    private static func stringify(_ any: Any?) -> String? {
        switch any {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        case let i as Int: return String(i)
        default: return nil
        }
    }

    private static func intValue(_ any: Any?) -> Int? {
        switch any {
        case let i as Int: return i
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s)
        default: return nil
        }
    }
}
