import Foundation
import BootCaptainCore

/// The Mach service name the privileged helper vends and the app connects to.
public enum HelperConstants {
    public static let machServiceName = "ch.lkmc.bootcaptain.helper"
    public static let helperIdentifier = "ch.lkmc.bootcaptain.helper"
    public static let appIdentifier = "ch.lkmc.bootcaptain"
}

#if os(macOS)
/// The XPC contract between the app and the privileged helper.
///
/// Requests and replies cross as JSON-encoded `Data` (an `ActionRequest` in,
/// an `ActionOutcome` out) so the wire type is a plain byte blob and the typed
/// contract is enforced at the `Codable` layer — no `NSObject` graph to attack
/// (PLAN.md §6.4 "typed operations … never shell fragments").
@objc public protocol BootCaptainHelperProtocol {
    /// Perform one typed, pre-authorized mutation. `requestJSON` is a JSON
    /// `ActionRequest`; the reply is a JSON `ActionOutcome`.
    func perform(requestJSON: Data, withReply reply: @escaping (Data) -> Void)

    /// Return the helper's version so the app can detect a stale install.
    func helperVersion(withReply reply: @escaping (String) -> Void)

    /// Read root-only state (BTM dump, other users' crontabs) as JSON, so the
    /// app process itself never needs Full Disk Access for those sources.
    func collectRootOnly(requestJSON: Data, withReply reply: @escaping (Data) -> Void)
}

/// Encoding helpers shared by both ends of the connection.
public enum HelperCodec {
    public static func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }
}

/// The designated code-signing requirement each side pins on the other. The
/// helper requires the app; the app requires the helper. Both check bundle ID +
/// Team ID (Team ID alone is too broad — PLAN.md §6.4).
public enum HelperRequirements {
    public static func appRequirement(teamID: String) -> String {
        "identifier \"\(HelperConstants.appIdentifier)\" and anchor apple generic "
        + "and certificate leaf[subject.OU] = \"\(teamID)\""
    }
    public static func helperRequirement(teamID: String) -> String {
        "identifier \"\(HelperConstants.helperIdentifier)\" and anchor apple generic "
        + "and certificate leaf[subject.OU] = \"\(teamID)\""
    }
}
#endif
