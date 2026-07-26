import Foundation

/// A parsed launchd property list. Keys per `launchd.plist(5)`. Only the fields
/// BootCaptain reasons about are modelled; unknown keys are preserved in
/// `unknownKeys` so a newer OS cannot silently turn an item into a misleading
/// partial record (PLAN.md §2.1).
public struct LaunchdJob: Sendable, Equatable {
    public var label: String?
    public var program: String?
    public var programArguments: [String]
    public var bundleProgram: String?

    public var runAtLoad: Bool
    /// nil = key absent; .some for either boolean or dictionary form.
    public var keepAlive: KeepAliveKind?
    /// Legacy inverse of KeepAlive.
    public var onDemand: Bool?

    public var startInterval: Bool
    public var startCalendarInterval: Bool
    public var watchPaths: Bool
    public var queueDirectories: Bool
    public var startOnMount: Bool
    public var launchEvents: Bool
    public var machServices: Bool
    public var sockets: Bool

    public var disabledDefault: Bool
    public var limitLoadToSessionType: [String]
    public var associatedBundleIdentifiers: [String]
    public var userName: String?
    public var enableGlobbing: Bool

    public var unknownKeys: [String]

    public init() {
        label = nil
        program = nil
        programArguments = []
        bundleProgram = nil
        runAtLoad = false
        keepAlive = nil
        onDemand = nil
        startInterval = false
        startCalendarInterval = false
        watchPaths = false
        queueDirectories = false
        startOnMount = false
        launchEvents = false
        machServices = false
        sockets = false
        disabledDefault = false
        limitLoadToSessionType = []
        associatedBundleIdentifiers = []
        userName = nil
        enableGlobbing = false
        unknownKeys = []
    }

    static let knownKeys: Set<String> = [
        "Label", "Program", "ProgramArguments", "BundleProgram", "RunAtLoad",
        "KeepAlive", "OnDemand", "StartInterval", "StartCalendarInterval",
        "WatchPaths", "QueueDirectories", "StartOnMount", "LaunchEvents",
        "MachServices", "Sockets", "Disabled", "LimitLoadToSessionType",
        "AssociatedBundleIdentifiers", "UserName", "EnableGlobbing",
    ]
}

public enum LaunchdParseError: Error, Equatable {
    case notADictionary
    case malformed(String)
}

public enum LaunchdJobParser {
    public static let version = "1"

    /// Parse a launchd plist (XML or binary) into a `LaunchdJob`.
    public static func parse(data: Data) throws -> LaunchdJob {
        let obj: Any
        do {
            obj = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw LaunchdParseError.malformed("\(error)")
        }
        guard let dict = obj as? [String: Any] else {
            throw LaunchdParseError.notADictionary
        }
        return parse(dictionary: dict)
    }

    /// Parse an already-deserialised plist dictionary.
    public static func parse(dictionary dict: [String: Any]) -> LaunchdJob {
        var job = LaunchdJob()
        job.label = dict["Label"] as? String
        job.program = dict["Program"] as? String
        if let args = dict["ProgramArguments"] as? [String] {
            job.programArguments = args
        } else if let anyArgs = dict["ProgramArguments"] as? [Any] {
            job.programArguments = anyArgs.compactMap { $0 as? String }
        }
        job.bundleProgram = dict["BundleProgram"] as? String
        job.runAtLoad = boolValue(dict["RunAtLoad"])

        if let ka = dict["KeepAlive"] {
            if ka is [String: Any] {
                job.keepAlive = .conditional
            } else if boolValue(ka) {
                job.keepAlive = .always
            } else {
                job.keepAlive = KeepAliveKind.none
            }
        }
        if let od = dict["OnDemand"] { job.onDemand = boolValue(od) }

        job.startInterval = dict["StartInterval"] != nil
        job.startCalendarInterval = dict["StartCalendarInterval"] != nil
        job.watchPaths = arrayNonEmpty(dict["WatchPaths"])
        job.queueDirectories = arrayNonEmpty(dict["QueueDirectories"])
        job.startOnMount = boolValue(dict["StartOnMount"])
        job.launchEvents = dict["LaunchEvents"] is [String: Any]
        job.machServices = dict["MachServices"] is [String: Any]
        job.sockets = dict["Sockets"] is [String: Any]

        job.disabledDefault = boolValue(dict["Disabled"])
        job.limitLoadToSessionType = stringList(dict["LimitLoadToSessionType"])
        job.associatedBundleIdentifiers = stringList(dict["AssociatedBundleIdentifiers"])
        job.userName = dict["UserName"] as? String
        job.enableGlobbing = boolValue(dict["EnableGlobbing"])

        job.unknownKeys = dict.keys.filter { !LaunchdJob.knownKeys.contains($0) }.sorted()
        return job
    }

    // MARK: helpers

    private static func boolValue(_ any: Any?) -> Bool {
        switch any {
        case let b as Bool: return b
        case let n as NSNumber: return n.boolValue
        case let i as Int: return i != 0
        default: return false
        }
    }

    private static func arrayNonEmpty(_ any: Any?) -> Bool {
        if let a = any as? [Any] { return !a.isEmpty }
        return false
    }

    private static func stringList(_ any: Any?) -> [String] {
        if let s = any as? String { return [s] }
        if let a = any as? [String] { return a }
        if let a = any as? [Any] { return a.compactMap { $0 as? String } }
        return []
    }
}
