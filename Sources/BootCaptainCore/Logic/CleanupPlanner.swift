import Foundation

/// Plans the built-in "Clean Up" flow for broken/orphaned startup items.
///
/// Scope is deliberately narrow (this is NOT generic orphan deletion):
/// - Only items with concrete broken health are candidates.
/// - Mutation-forbidden, conflicting, unresolved, and read-only items are never
///   candidates.
/// - The only unprivileged action is a **reversible vault move** of a file the
///   current user owns under their own `~/Library/LaunchAgents`, or removal of
///   a classic "Open at Login" entry (System Events). Both have precomputed
///   inverses and are journaled by the caller.
/// - Root-owned sources are exposed only after the helper operation is enabled
///   in a qualified build.
public enum CleanupPlanner {
    public enum Eligibility: String, Codable, Sendable, Equatable {
        /// Move the source file to the user-level vault (reversible, no root).
        case userVaultMove
        /// Remove the classic login item via System Events (re-addable).
        case loginItemRemoval
        /// Actionable only via the privileged helper (currently disabled).
        case requiresHelper
    }

    public struct Candidate: Codable, Sendable, Equatable, Identifiable {
        public var itemID: String
        public var displayName: String
        public var reason: String
        public var eligibility: Eligibility
        public var sourcePath: String?
        public var id: String { itemID }

        public init(itemID: String, displayName: String, reason: String,
                    eligibility: Eligibility, sourcePath: String?) {
            self.itemID = itemID
            self.displayName = displayName
            self.reason = reason
            self.eligibility = eligibility
            self.sourcePath = sourcePath
        }
    }

    /// Which items qualify for the cleanup sheet, and how.
    public static func plan(items: [StartupItem], userHomes: [String]) -> [Candidate] {
        var out: [Candidate] = []
        for item in items {
            guard isBrokenEnough(item) else { continue }
            guard !item.trust.isMutationForbidden else { continue }
            guard item.actionClass == .reversibleMutation else { continue }
            guard item.recipe?.isUnresolved != true else { continue }
            guard !item.attribution.hasConflict else { continue }
            if item.isInert { continue }

            let reason = brokenReason(item)

            switch item.mechanism {
            case .classicLoginItem:
                out.append(Candidate(
                    itemID: item.id, displayName: item.displayName, reason: reason,
                    eligibility: .loginItemRemoval, sourcePath: item.sourcePath))
            case .launchAgent, .launchDaemon:
                guard let path = item.sourcePath else { continue }
                if isUserOwnedAgentPath(path, userHomes: userHomes) {
                    out.append(Candidate(
                        itemID: item.id, displayName: item.displayName, reason: reason,
                        eligibility: .userVaultMove, sourcePath: path))
                } else if (path.hasPrefix("/Library/LaunchDaemons/")
                            || path.hasPrefix("/Library/LaunchAgents/")),
                          ActionRequest.Operation.moveToVault.isEnabledInCurrentBuild {
                    out.append(Candidate(
                        itemID: item.id, displayName: item.displayName, reason: reason,
                        eligibility: .requiresHelper, sourcePath: path))
                }
            default:
                continue  // other mechanisms are out of cleanup scope for now
            }
        }
        // Actionable first, then helper-gated; stable by name within groups.
        return out.sorted { a, b in
            if a.eligibility != b.eligibility {
                return rank(a.eligibility) < rank(b.eligibility)
            }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }

    /// Only concrete brokenness qualifies. "Possibly orphaned" needs repeated
    /// observation and mounted-volume checks before it can authorize a change.
    static func isBrokenEnough(_ item: StartupItem) -> Bool {
        item.health == .broken
    }

    static func isUserOwnedAgentPath(_ path: String, userHomes: [String]) -> Bool {
        userHomes.contains { path.hasPrefix($0 + "/Library/LaunchAgents/") }
    }

    static func brokenReason(_ item: StartupItem) -> String {
        if item.health == .possiblyOrphaned {
            return "Its app appears to be gone — this leftover can trigger login errors."
        }
        if let exec = item.recipe?.executablePath {
            return "Its program no longer exists (\(exec))."
        }
        return "Its configuration is broken and it can never launch as written."
    }

    static func rank(_ e: Eligibility) -> Int {
        switch e {
        case .userVaultMove: return 0
        case .loginItemRemoval: return 1
        case .requiresHelper: return 2
        }
    }
}
