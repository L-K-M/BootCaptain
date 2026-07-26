import Foundation
import BootCaptainCore

/// Validates an `ActionRequest` before the privileged helper touches anything
/// (PLAN.md §6.4 "no confused deputy"). This is the portable half — path
/// allow-listing and request sanity; the helper adds the descriptor-level
/// TOCTOU hardening (openat / O_NOFOLLOW / fstat) on top.
public enum RequestValidator {
    /// Canonical roots a source/destination path may live under.
    public static let allowedSourceRoots = [
        "/Library/LaunchDaemons/",
        "/Library/LaunchAgents/",
        "/usr/lib/cron/tabs/",
        "/etc/crontab",
    ]
    public static let allowedUserAgentSuffix = "/Library/LaunchAgents/"

    public enum Rejection: Error, Equatable {
        case pathNotAllowed(String)
        case missingField(String)
        case badLabel(String)
        case badDomain(String)
        case pathEscapesRoot(String)
    }

    /// Validate the request's shape and paths. `userHomes` bounds the acceptable
    /// per-user LaunchAgents locations.
    public static func validate(_ request: ActionRequest, userHomes: [String]) -> Result<Void, Rejection> {
        switch request.operation {
        case .launchdDisable, .launchdEnable, .launchdBootout:
            guard let label = request.label, isValidLabel(label) else {
                return .failure(.badLabel(request.label ?? "nil"))
            }
            guard let domain = request.domain, isValidDomain(domain) else {
                return .failure(.badDomain(request.domain ?? "nil"))
            }
            // bootout/bootstrap need the source plist; it must be allow-listed.
            if let path = request.sourcePath {
                guard isAllowedSource(path, userHomes: userHomes) else {
                    return .failure(.pathNotAllowed(path))
                }
            }
            return .success(())

        case .cronToggleEntry:
            guard let path = request.sourcePath else { return .failure(.missingField("sourcePath")) }
            guard path == "/etc/crontab" || path.hasPrefix("/usr/lib/cron/tabs/") else {
                return .failure(.pathNotAllowed(path))
            }
            guard request.cronLineNumber != nil else { return .failure(.missingField("cronLineNumber")) }
            return .success(())

        case .moveToVault, .restoreFromVault:
            guard let path = request.sourcePath else { return .failure(.missingField("sourcePath")) }
            guard isAllowedSource(path, userHomes: userHomes) else {
                return .failure(.pathNotAllowed(path))
            }
            // No path traversal in the item ID (used to build the vault subdir).
            if request.itemID.contains("..") {
                return .failure(.pathEscapesRoot(request.itemID))
            }
            return .success(())
        }
    }

    public static func isAllowedSource(_ path: String, userHomes: [String]) -> Bool {
        // No traversal or symlink games in the string itself.
        if path.contains("..") || path.contains("//") { return false }
        for root in allowedSourceRoots {
            if root.hasSuffix("/"), path.hasPrefix(root) { return true }
            if path == root { return true }
        }
        for home in userHomes {
            if path.hasPrefix(home + allowedUserAgentSuffix) { return true }
        }
        return false
    }

    /// A launchd label: reverse-DNS-ish, no whitespace or path separators.
    public static func isValidLabel(_ label: String) -> Bool {
        guard !label.isEmpty, label.count <= 512 else { return false }
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
        return label.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// A domain target: "system", "gui/<uid>", or "user/<uid>".
    public static func isValidDomain(_ domain: String) -> Bool {
        if domain == "system" { return true }
        let parts = domain.split(separator: "/")
        guard parts.count == 2, parts[0] == "gui" || parts[0] == "user",
              Int(parts[1]) != nil else { return false }
        return true
    }
}
