import Foundation

/// A record parsed from `sfltool dumpbtm` text. The format is undocumented and
/// drifts between releases, so parsing is tolerant and every field optional
/// (PLAN.md §2.2, EVIDENCE B-02/B-03).
public struct BTMRecord: Sendable, Equatable {
    public var uuid: String?
    public var name: String?
    public var developerName: String?
    public var teamIdentifier: String?
    public var typeRaw: Int?
    public var dispositionRaw: Int?
    public var identifier: String?
    public var url: String?          // file://… of the plist/app
    public var executablePath: String?
    public var bundleIdentifier: String?
    public var associatedBundleIDs: [String]
    public var parentIdentifier: String?
    public var generation: Int?

    public init() {
        associatedBundleIDs = []
    }

    // Type bit-flags (PLAN.md §2.2, from Objective-See DumpBTM).
    public var isApp: Bool { (typeRaw ?? 0) & 0x2 != 0 }
    public var isLoginItem: Bool { (typeRaw ?? 0) & 0x4 != 0 }
    public var isAgent: Bool { (typeRaw ?? 0) & 0x8 != 0 }
    public var isDaemon: Bool { (typeRaw ?? 0) & 0x10 != 0 }
    public var isDeveloperGroup: Bool { (typeRaw ?? 0) & 0x20 != 0 }
    public var isLegacy: Bool { (typeRaw ?? 0) & 0x10000 != 0 }
    public var isCurated: Bool { (typeRaw ?? 0) & 0x80000 != 0 }

    // Disposition bits.
    public var dispEnabled: Bool { (dispositionRaw ?? 0) & 0x1 != 0 }
    public var dispAllowed: Bool { (dispositionRaw ?? 0) & 0x2 != 0 }
    public var dispHidden: Bool { (dispositionRaw ?? 0) & 0x4 != 0 }
    public var dispNotified: Bool { (dispositionRaw ?? 0) & 0x8 != 0 }

    /// Maps the record's type bits to a `Mechanism`.
    public var mechanism: Mechanism {
        if isDaemon { return isLegacy ? .launchDaemon : .smAppServiceDaemon }
        if isAgent { return isLegacy ? .launchAgent : .smAppServiceAgent }
        if isLoginItem { return .smAppServiceLoginItem }
        if isApp { return .classicLoginItem }
        return .backgroundTaskManagement
    }
}

public enum BTMDumpParser {
    public static let version = "1"

    /// Parse the text produced by `sudo sfltool dumpbtm`. Records are separated
    /// by lines that start a new numbered entry (e.g. "#57" or "UUID:"). This
    /// tolerant parser keys off `Key: value` lines and starts a fresh record on
    /// a `UUID:` line or a bare `#<n>` marker.
    public static func parse(_ text: String) -> [BTMRecord] {
        var records: [BTMRecord] = []
        var current: BTMRecord?

        func flush() {
            if let c = current, c.uuid != nil || c.identifier != nil || c.name != nil {
                records.append(c)
            }
            current = nil
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            // New-record markers.
            if line.hasPrefix("#"), Int(line.dropFirst()) != nil {
                flush(); current = BTMRecord(); continue
            }
            guard let (key, value) = splitKeyValue(line) else { continue }
            let k = key.lowercased()
            if k == "uuid" {
                // A UUID line always starts a fresh record.
                flush(); current = BTMRecord(); current?.uuid = value
                continue
            }
            if current == nil { current = BTMRecord() }
            switch k {
            case "name": current?.name = value
            case "developer name", "developername": current?.developerName = value
            case "team identifier", "teamidentifier": current?.teamIdentifier = value
            case "type": current?.typeRaw = parseHexTrailing(value)
            case "disposition": current?.dispositionRaw = parseHexTrailing(value)
            case "identifier": current?.identifier = value
            case "url": current?.url = value
            case "executable path", "executablepath": current?.executablePath = value
            case "bundle identifier", "bundleidentifier": current?.bundleIdentifier = value
            case "generation": current?.generation = Int(value)
            case "assoc. bundle ids", "associated bundle identifiers", "assoc bundle ids":
                current?.associatedBundleIDs = parseBundleList(value)
            case "parent identifier", "parentidentifier": current?.parentIdentifier = value
            default: break
            }
        }
        flush()
        return records
    }

    // MARK: helpers

    private static func splitKeyValue(_ line: String) -> (String, String)? {
        guard let idx = line.firstIndex(of: ":") else { return nil }
        let key = String(line[..<idx]).trimmingCharacters(in: .whitespaces)
        let value = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        return (key, value)
    }

    /// Extracts the trailing "(0x1b)" hex from a `Type: daemon (0x10)` line, or
    /// falls back to a bare hex/decimal token.
    private static func parseHexTrailing(_ value: String) -> Int? {
        if let open = value.lastIndex(of: "("), let close = value.lastIndex(of: ")"),
           open < close {
            let inner = String(value[value.index(after: open)..<close])
            if inner.hasPrefix("0x"), let v = Int(inner.dropFirst(2), radix: 16) { return v }
            if let v = Int(inner) { return v }
        }
        if value.hasPrefix("0x"), let v = Int(value.dropFirst(2), radix: 16) { return v }
        return Int(value)
    }

    private static func parseBundleList(_ value: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
        guard !trimmed.isEmpty else { return [] }
        return trimmed.split(whereSeparator: { $0 == "," || $0 == " " })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"")) }
            .filter { !$0.isEmpty }
    }
}
