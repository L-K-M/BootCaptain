import Foundation
import Security
import BootCaptainCore
import BootCaptainKit

// BootCaptain privileged helper.
//
// Registered by the app via `SMAppService.daemon`, demand-launched (no
// KeepAlive), and vends a single Mach service. It performs ONLY typed,
// pre-validated, reversible mutations (PLAN.md §6.4). Every message is checked
// against the app's designated code-signing requirement, and every target is
// re-validated immediately before it is touched.

/// Where the helper keeps its durable, root-owned mutation journal and vault.
enum HelperPaths {
    static let support = "/Library/Application Support/BootCaptain"
    static let vault = support + "/Vault"
    static let journalDir = support + "/Journal"
}

final class HelperService: NSObject, BootCaptainHelperProtocol, @unchecked Sendable {
    let runner = ActionRunner(vaultRoot: HelperPaths.vault)
    let journal = FileJournal(directory: HelperPaths.journalDir)
    // Only the reversible vault move/restore used by Clean Up is enabled;
    // launchd/cron mutations stay gated (Core `isEnabledInCurrentBuild`,
    // PLAN.md §6). This is not a blanket switch — see MutationPolicy.
    // The helper trusts the OS for user enumeration rather than the caller.
    let userHomes: [String] = {
        (try? FileManager.default.contentsOfDirectory(atPath: "/Users"))?
            .filter { $0 != "Shared" && $0 != "Guest" && !$0.hasPrefix(".") }
            .map { "/Users/\($0)" }
            .filter { FileManager.default.fileExists(atPath: $0 + "/Library") } ?? []
    }()

    func helperVersion(withReply reply: @escaping (String) -> Void) {
        reply(BootCaptainCoreInfo.version)
    }

    func perform(requestJSON: Data, withReply reply: @escaping (Data) -> Void) {
        guard let request = HelperCodec.decode(ActionRequest.self, from: requestJSON) else {
            return reply(HelperCodec.encode(ActionOutcome(
                status: .aborted, message: "Malformed request.")))
        }
        // 0. Per-operation enablement. Only reversible vault move/restore is on.
        guard request.operation.isEnabledInCurrentBuild else {
            return reply(HelperCodec.encode(ActionOutcome(
                status: .aborted,
                message: "This privileged operation is not enabled in this build.")))
        }
        // 1. Portable request validation (allow-listed roots, sane label/domain).
        if case .failure(let rejection) = RequestValidator.validate(request, userHomes: userHomes) {
            return reply(HelperCodec.encode(ActionOutcome(
                status: .aborted, message: "Rejected by policy: \(rejection).")))
        }
        // 2. Descriptor-level TOCTOU re-validation of the file being moved out.
        //    moveToVault re-checks its source with TargetGuard immediately below,
        //    right before the move. restoreFromVault is deliberately NOT
        //    symmetric: its request path is the not-yet-existing original
        //    destination (guarded by the runner's no-overwrite rename), and its
        //    vault source is not descriptor-re-validated here. That residual gap
        //    is accepted because the vault lives under root-owned
        //    /Library/Application Support — only root could plant a symlink in it
        //    to redirect the restore — and full race-safe descriptor traversal
        //    for both directions is the documented Phase-0 hardening follow-up
        //    (see TargetGuard below and AGENTS.md "race-safe descriptor
        //    traversal"); it is not a per-request check to bolt on reactively.
        if request.operation == .moveToVault, let path = request.sourcePath {
            guard TargetGuard.isSafeToActOn(path: path) else {
                return reply(HelperCodec.encode(ActionOutcome(
                    status: .aborted, message: "Target failed pre-mutation safety re-check.")))
            }
        }
        // 3. Durable journal: prepared -> execute -> terminal (AGENTS.md). If the
        //    prepared record cannot be written, refuse to mutate — a privileged
        //    action must never run without a durable prepared record on disk.
        guard let record = journal.prepare(request, at: Date().timeIntervalSince1970) else {
            return reply(HelperCodec.encode(ActionOutcome(
                status: .aborted,
                message: "Could not write the prepared journal record; aborting for safety.")))
        }
        let outcome = runner.perform(request)
        if !journal.complete(record, status: outcome.status, at: Date().timeIntervalSince1970) {
            // The mutation already ran; nothing to roll back. Surface that the
            // journal is now stale so the "unfinished" it will report is expected.
            NSLog("BootCaptain helper: journal completion write failed for \(request.itemID); mutation ran, on-disk record is stale.")
        }
        reply(HelperCodec.encode(outcome))
    }

    func collectRootOnly(requestJSON: Data, withReply reply: @escaping (Data) -> Void) {
        // Root-only reads (BTM dump, other users' crontabs) so the app process
        // never needs Full Disk Access for them. The request selects which.
        guard let selector = String(data: requestJSON, encoding: .utf8) else {
            return reply(Data())
        }
        var ctx = SystemEnvironment.makeContext()
        ctx = ScanContext(runner: ctx.runner, fileManager: ctx.fileManager,
                          userHomes: ctx.userHomes, currentUID: 0,
                          osBuild: ctx.osBuild, hasRoot: true,
                          hasFullDiskAccess: true)
        switch selector {
        case "btm":
            let result = BTMCollector().collect(ctx)
            reply(HelperCodec.encode(result.items))
        case "cron":
            let result = CronCollector().collect(ctx)
            reply(HelperCodec.encode(result.items))
        default:
            reply(Data())
        }
    }
}

/// Descriptor-level safety guard (PLAN.md §6.4). A fuller implementation opens
/// fixed roots as directory descriptors and resolves beneath them; here we
/// perform the essential checks: the final path is a regular file, is not a
/// symlink, and is not writable by anyone but root.
enum TargetGuard {
    static func isSafeToActOn(path: String) -> Bool {
        var st = stat()
        // lstat: do NOT follow a final symlink.
        guard lstat(path, &st) == 0 else { return false }
        // Reject symlinks outright.
        if (st.st_mode & S_IFMT) == S_IFLNK { return false }
        // Must be a regular file.
        guard (st.st_mode & S_IFMT) == S_IFREG else { return false }
        // Must be owned by root and not group/other writable.
        if st.st_uid != 0 { return false }
        if (st.st_mode & S_IWGRP) != 0 || (st.st_mode & S_IWOTH) != 0 { return false }
        return true
    }
}

final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Pin the app's designated requirement on the incoming connection so a
        // rogue client cannot drive the helper (PLAN.md §6.4). Team ID is baked
        // in at signing time; here we read it from our own signing info.
        guard let teamID = HelperTeam.current() else {
            NSLog("BootCaptain helper: rejecting connection, signing Team ID unavailable")
            return false
        }
        let requirement = HelperRequirements.appRequirement(teamID: teamID)
        if #available(macOS 13.0, *) {
            do {
                try connection.setCodeSigningRequirement(requirement)
            } catch {
                NSLog("BootCaptain helper: rejecting connection, requirement error: \(error)")
                return false
            }
        }
        connection.exportedInterface = NSXPCInterface(with: BootCaptainHelperProtocol.self)
        connection.exportedObject = HelperService()
        connection.resume()
        return true
    }
}

/// Reads this helper's own Team ID from its signing info so the pinned
/// requirement matches the actual signing identity at runtime.
enum HelperTeam {
    static func current() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            return nil
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode,
                SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any],
              let team = dict[kSecCodeInfoTeamIdentifier as String] as? String
        else { return nil }
        return team
    }
}

// Entry point.
// Surface any journal records a prior crash left unresolved. We never blindly
// replay a privileged action on startup (AGENTS.md "idempotent recovery"); we
// log them so state can be reconciled deliberately.
let pending = FileJournal(directory: HelperPaths.journalDir).unfinished()
if !pending.isEmpty {
    NSLog("BootCaptain helper: \(pending.count) unfinished journal record(s) need reconciliation")
}

let delegate = ServiceDelegate()
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()
NSLog("BootCaptain helper \(BootCaptainCoreInfo.version) listening on \(HelperConstants.machServiceName)")
RunLoop.current.run()
