import Foundation

/// A parsed unified-log record from `log show --style ndjson`. Only the fields
/// BootCaptain reasons about are decoded.
public struct LogRecord: Sendable, Equatable, Codable {
    public var timestamp: String?
    public var eventMessage: String?
    public var subsystem: String?
    public var category: String?
    public var process: String?
    public var processID: Int?
    public var messageType: String?

    enum CodingKeys: String, CodingKey {
        case timestamp, eventMessage, subsystem, category
        case process, processID, messageType
    }
}

/// Version-fragile matchers for launchd/BTM/loginwindow log strings. PLAN.md §7:
/// "Log strings use build-tested matchers and fail soft." Each matcher is a
/// substring/label pair; the matched string is presented verbatim as raw
/// evidence, never as a universal rule.
public struct LogMatcher: Sendable, Equatable {
    public enum Signal: String, Sendable, Codable {
        case spawnFailedMissingExecutable
        case serviceCouldNotInitialize
        case exitedAbnormalCode
        case throttledRespawn
        case bootstrapDisabled
    }
    public var signal: Signal
    public var needles: [String]   // case-insensitive substrings (all-of? no: any-of)
    public var confidence: Confidence

    public init(signal: Signal, needles: [String], confidence: Confidence) {
        self.signal = signal
        self.needles = needles
        self.confidence = confidence
    }

    public func matches(_ message: String) -> Bool {
        let lower = message.lowercased()
        return needles.contains { lower.contains($0.lowercased()) }
    }
}

public enum UnifiedLogMatchers {
    public static let version = "1"

    /// The default corpus. On real hardware this is overridden per OS build
    /// (PLAN.md §12); shipping a corpus is fine as long as misses fail soft.
    public static let launchdCorpus: [LogMatcher] = [
        LogMatcher(signal: .serviceCouldNotInitialize,
                   needles: ["Service could not initialize", "could not find and/or execute"],
                   confidence: .medium),
        LogMatcher(signal: .exitedAbnormalCode,
                   needles: ["Service exited with abnormal code", "exited due to sig"],
                   confidence: .medium),
        LogMatcher(signal: .throttledRespawn,
                   needles: ["Pushing respawn out by", "Service only ran for"],
                   confidence: .medium),
        LogMatcher(signal: .bootstrapDisabled,
                   needles: ["Service is disabled"],
                   confidence: .medium),
    ]

    /// The NDJSON predicate subsystems worth querying (PLAN.md §7).
    public static let subsystems = [
        "com.apple.xpc.launchd",
        "com.apple.loginwindow",
        "com.apple.backgroundtaskmanagement",
        "com.apple.syspolicy",
    ]

    /// Decode `log show --style ndjson` output (one JSON object per line).
    public static func parseNDJSON(_ text: String) -> [LogRecord] {
        var out: [LogRecord] = []
        let decoder = JSONDecoder()
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = rawLine.data(using: .utf8) else { continue }
            if let rec = try? decoder.decode(LogRecord.self, from: data) {
                out.append(rec)
            }
        }
        return out
    }

    /// First matching signal for a message, if any.
    public static func classify(_ message: String, corpus: [LogMatcher] = launchdCorpus) -> LogMatcher.Signal? {
        for m in corpus where m.matches(message) { return m.signal }
        return nil
    }
}
