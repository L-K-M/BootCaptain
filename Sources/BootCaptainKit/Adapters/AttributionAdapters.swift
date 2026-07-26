import Foundation
import BootCaptainCore

/// Reads a package receipt for a file path via `pkgutil --file-info`. This means
/// a receipt *records* the path, not that the current bytes were installed by
/// or remain owned by that package (PLAN.md §5, EVIDENCE A-02).
public struct ReceiptInspector: Sendable {
    public init() {}

    public func receiptPackage(for path: String, runner: CommandRunner) -> String? {
        let res = runner.run("/usr/sbin/pkgutil", ["--file-info", path], timeout: 15)
        guard res.succeeded else { return nil }
        for line in res.stdout.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("pkgid:") {
                return t.replacingOccurrences(of: "pkgid:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}

/// Reads Apple's host attribution table (`attributions.plist`) — the same data
/// System Settings uses to pretty-name helpers (PLAN.md §5). Private-framework
/// resource: path and schema are unsupported, so failure is silent.
public struct AttributionsPlistReader: Sendable {
    public static let defaultPath =
        "/System/Library/PrivateFrameworks/BackgroundTaskManagement.framework/Versions/A/Resources/attributions.plist"

    private let entries: [String: String]  // identifier/path -> product name

    public init(path: String = AttributionsPlistReader.defaultPath,
                fileManager: FileManager = .default) {
        guard let data = fileManager.contents(atPath: path),
              let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        else { entries = [:]; return }
        entries = Self.flatten(obj)
    }

    /// Look up a product name by identifier or executable path.
    public func productName(identifier: String?, executablePath: String?) -> String? {
        if let id = identifier, let hit = entries[id] { return hit }
        if let path = executablePath, let hit = entries[path] { return hit }
        return nil
    }

    public var isEmpty: Bool { entries.isEmpty }

    /// Best-effort flatten of the (undocumented) structure into id/path -> name.
    static func flatten(_ obj: Any) -> [String: String] {
        var out: [String: String] = [:]
        func walk(_ any: Any) {
            if let dict = any as? [String: Any] {
                let name = dict["name"] as? String ?? dict["productName"] as? String
                if let name {
                    for key in ["bundleIdentifier", "identifier", "executablePath", "path"] {
                        if let v = dict[key] as? String { out[v] = name }
                    }
                }
                for value in dict.values { walk(value) }
            } else if let arr = any as? [Any] {
                for value in arr { walk(value) }
            }
        }
        walk(obj)
        return out
    }
}
