import Foundation
import BootCaptainCore

#if canImport(Security)
import Security

/// Extracts per-architecture signing identity via the Security framework
/// (PLAN.md §4/§5). Metadata is collected *after* an explicit validity check;
/// `SecCodeCopySigningInformation` alone does not validate code.
public struct CodeSigningInspector: Sendable {
    public init() {}

    public func inspect(path: String) -> [SigningIdentity] {
        let url = URL(fileURLWithPath: path)
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else {
            return [SigningIdentity(isValid: .unknown)]
        }

        // Explicit validity across all architectures.
        var validity: Tristate = .unknown
        let checkFlags = SecCSFlags(rawValue:
            kSecCSCheckAllArchitectures | kSecCSStrictValidate)
        let checkStatus = SecStaticCodeCheckValidityWithErrors(code, checkFlags, nil, nil)
        switch checkStatus {
        case errSecSuccess: validity = .yes
        case errSecCSUnsigned: return [SigningIdentity(isValid: .no)]
        default: validity = .no
        }

        var info: CFDictionary?
        let infoFlags = SecCSFlags(rawValue: kSecCSSigningInformation | kSecCSRequirementInformation)
        guard SecCodeCopySigningInformation(code, infoFlags, &info) == errSecSuccess,
              let dict = info as? [String: Any] else {
            return [SigningIdentity(isValid: validity)]
        }

        var identity = SigningIdentity(isValid: validity)
        identity.teamIdentifier = dict[kSecCodeInfoTeamIdentifier as String] as? String
        identity.signingIdentifier = dict[kSecCodeInfoIdentifier as String] as? String
        if let platform = dict[kSecCodeInfoPlatformIdentifier as String] as? Int {
            identity.isPlatformBinary = platform != 0
        }
        if let cd = dict[kSecCodeInfoUnique as String] as? Data {
            identity.cdHash = cd.map { String(format: "%02x", $0) }.joined()
        }
        if let certs = dict[kSecCodeInfoCertificates as String] as? [SecCertificate],
           let leaf = certs.first {
            var cn: CFString?
            SecCertificateCopyCommonName(leaf, &cn)
            identity.authority = cn as String?
            identity.vendorName = Self.vendor(from: identity.authority)
        }

        identity.anchorApple = Self.satisfies(code, requirement: "anchor apple")
        identity.anchorAppleGeneric = Self.satisfies(code, requirement: "anchor apple generic")
        return [identity]
    }

    /// Vendor org from a "Developer ID Application: Vendor Name (TEAMID)" CN.
    static func vendor(from authority: String?) -> String? {
        guard let authority else { return nil }
        guard let colon = authority.firstIndex(of: ":") else { return authority }
        var name = String(authority[authority.index(after: colon)...])
            .trimmingCharacters(in: .whitespaces)
        if let paren = name.range(of: " (") { name = String(name[..<paren.lowerBound]) }
        return name.isEmpty ? nil : name
    }

    static func satisfies(_ code: SecStaticCode, requirement text: String) -> Tristate {
        var req: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &req) == errSecSuccess,
              let requirement = req else { return .unknown }
        let status = SecStaticCodeCheckValidity(code, [], requirement)
        return status == errSecSuccess ? .yes : .no
    }
}
#else
/// Non-macOS stub so the package compiles in CI. Returns "unknown" signing.
public struct CodeSigningInspector: Sendable {
    public init() {}
    public func inspect(path: String) -> [SigningIdentity] {
        [SigningIdentity(isValid: .unknown)]
    }
}
#endif
