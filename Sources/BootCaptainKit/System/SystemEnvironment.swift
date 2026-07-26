import Foundation
import BootCaptainCore

/// Probes the runtime environment to build a `ScanContext`. Kept small and
/// side-effect-light; the real permission story is enforced per collector.
public enum SystemEnvironment {
    public static func makeContext(runner: CommandRunner = ProcessRunner()) -> ScanContext {
        let fm = FileManager.default
        let uid = Int(getuid())
        let hasRoot = uid == 0

        // Enumerate real user homes under /Users (skip Shared/Guest).
        var homes: [String] = []
        if let users = try? fm.contentsOfDirectory(atPath: "/Users") {
            for user in users where user != "Shared" && user != "Guest" && !user.hasPrefix(".") {
                let home = "/Users/\(user)"
                if fm.fileExists(atPath: home + "/Library") { homes.append(home) }
            }
        }
        if homes.isEmpty, let home = ProcessInfo.processInfo.environment["HOME"] {
            homes = [home]
        }

        let build = osBuild(runner: runner)
        let fda = probeFullDiskAccess(fileManager: fm, homes: homes)

        return ScanContext(
            runner: runner, fileManager: fm, userHomes: homes,
            currentUID: uid, osBuild: build,
            hasRoot: hasRoot, hasFullDiskAccess: fda)
    }

    static func osBuild(runner: CommandRunner) -> String? {
        let res = runner.run("/usr/bin/sw_vers", ["-buildVersion"], timeout: 10)
        guard res.succeeded else { return nil }
        let build = res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return build.isEmpty ? nil : build
    }

    /// Best-effort FDA probe: try reading a TCC-protected location. A successful
    /// read of another user's Library or the BTM dir suggests FDA is granted.
    static func probeFullDiskAccess(fileManager fm: FileManager, homes: [String]) -> Bool {
        // Reading the Mail directory is a classic FDA gate.
        let probe = (homes.first ?? "/var/root") + "/Library/Mail"
        if fm.fileExists(atPath: probe) {
            return (try? fm.contentsOfDirectory(atPath: probe)) != nil
        }
        // Fall back to the BTM directory existence + readability.
        let btm = "/private/var/db/com.apple.backgroundtaskmanagement"
        if fm.fileExists(atPath: btm) {
            return (try? fm.contentsOfDirectory(atPath: btm)) != nil
        }
        return false
    }
}
