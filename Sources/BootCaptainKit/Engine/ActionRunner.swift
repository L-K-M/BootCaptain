import Foundation
import BootCaptainCore

/// Outcome of attempting one action.
public struct ActionOutcome: Sendable {
    public var status: JournalStatus
    public var message: String
    public var journalRecordID: String?
    public init(status: JournalStatus, message: String, journalRecordID: String? = nil) {
        self.status = status
        self.message = message
        self.journalRecordID = journalRecordID
    }
}

/// Executes typed, pre-authorized mutations (PLAN.md §6). The runner is what the
/// privileged helper drives; it never accepts shell fragments, only
/// `ActionRequest`s whose target it re-validates immediately before acting.
///
/// This type owns the launchctl/crontab/vault mechanics. Journaling (durable
/// prepared→committed writes) is layered by the helper using
/// `ActionJournalLogic`; the runner reports the achieved status honestly,
/// including `.indeterminate` when it cannot prove the effect.
public struct ActionRunner: Sendable {
    let runner: CommandRunner
    let fileManager: FileManager
    let vaultRoot: String

    public init(
        runner: CommandRunner = ProcessRunner(),
        fileManager: FileManager = .default,
        vaultRoot: String = "/Library/Application Support/BootCaptain/Vault"
    ) {
        self.runner = runner
        self.fileManager = fileManager
        self.vaultRoot = vaultRoot
    }

    public func perform(_ request: ActionRequest) -> ActionOutcome {
        switch request.operation {
        case .launchdDisable:  return launchd(request, verb: "disable")
        case .launchdEnable:   return launchd(request, verb: "enable")
        case .launchdBootout:  return bootout(request)
        case .cronToggleEntry: return cronToggle(request)
        case .moveToVault:     return moveToVault(request)
        case .restoreFromVault:return restoreFromVault(request)
        }
    }

    // MARK: launchd

    func launchd(_ request: ActionRequest, verb: String) -> ActionOutcome {
        guard let label = request.label, let domain = request.domain else {
            return ActionOutcome(status: .aborted, message: "Missing domain/label.")
        }
        let target = "\(domain)/\(label)"
        let res = runner.run("/bin/launchctl", [verb, target])
        if res.succeeded {
            return ActionOutcome(status: .committed, message: "launchctl \(verb) \(target)")
        }
        // `disable`/`enable` are idempotent; a nonzero status here is ambiguous
        // (already in that state vs. real failure), so report indeterminate.
        return ActionOutcome(status: .indeterminate,
            message: "launchctl \(verb) \(target) exited \(res.status): \(res.stderr.prefix(120))")
    }

    func bootout(_ request: ActionRequest) -> ActionOutcome {
        guard let label = request.label, let domain = request.domain else {
            return ActionOutcome(status: .aborted, message: "Missing domain/label.")
        }
        let res = runner.run("/bin/launchctl", ["bootout", "\(domain)/\(label)"])
        // A job that was not loaded returns nonzero; that's still "not running".
        if res.succeeded {
            return ActionOutcome(status: .committed, message: "Stopped \(label).")
        }
        return ActionOutcome(status: .indeterminate,
            message: "bootout \(label) exited \(res.status) (may already be stopped).")
    }

    // MARK: cron

    func cronToggle(_ request: ActionRequest) -> ActionOutcome {
        guard let tab = request.sourcePath, let line = request.cronLineNumber else {
            return ActionOutcome(status: .aborted, message: "Missing crontab path/line.")
        }
        guard let data = fileManager.contents(atPath: tab),
              let text = String(data: data, encoding: .utf8) else {
            return ActionOutcome(status: .aborted, message: "Cannot read crontab \(tab).")
        }
        // Determine current marker state to decide direction (idempotent).
        let lines = text.components(separatedBy: "\n")
        guard line < lines.count else {
            return ActionOutcome(status: .aborted, message: "Line \(line) out of range.")
        }
        let currentlyDisabled = lines[line].trimmingCharacters(in: .whitespaces)
            .hasPrefix("# BOOTCAPTAIN-DISABLED: ")
        let newBody = CronParser.toggle(text, lineNumber: line, disable: !currentlyDisabled)

        // Reinstall the whole tab via `crontab <file>` (never crontab -r).
        let tmp = NSTemporaryDirectory() + "bootcaptain-cron-\(line)"
        do {
            try newBody.write(toFile: tmp, atomically: true, encoding: .utf8)
        } catch {
            return ActionOutcome(status: .aborted, message: "Could not stage crontab: \(error)")
        }
        defer { try? fileManager.removeItem(atPath: tmp) }
        var args = [tmp]
        if let user = request.cronUser { args = ["-u", user, tmp] }
        let res = runner.run("/usr/bin/crontab", args)
        if res.succeeded {
            return ActionOutcome(status: .committed,
                message: currentlyDisabled ? "Re-enabled cron entry." : "Disabled cron entry.")
        }
        return ActionOutcome(status: .indeterminate,
            message: "crontab reinstall exited \(res.status): \(res.stderr.prefix(120))")
    }

    // MARK: vault (safe file move)

    /// Move a source file into the vault with an exclusive, no-overwrite rename.
    /// The full TOCTOU-hardened path lives in the helper (§6.4); this is the
    /// mechanism used once the target has been validated.
    func moveToVault(_ request: ActionRequest) -> ActionOutcome {
        guard let source = request.sourcePath else {
            return ActionOutcome(status: .aborted, message: "Missing source path.")
        }
        let stamp = request.itemID.replacingOccurrences(of: "/", with: "_")
        let dest = vaultRoot + "/" + stamp + "/" + (source as NSString).lastPathComponent
        do {
            try fileManager.createDirectory(atPath: (dest as NSString).deletingLastPathComponent,
                                            withIntermediateDirectories: true)
            guard !fileManager.fileExists(atPath: dest) else {
                return ActionOutcome(status: .aborted, message: "Vault destination already exists.")
            }
            try fileManager.moveItem(atPath: source, toPath: dest)
            return ActionOutcome(status: .committed, message: "Moved to vault.")
        } catch {
            return ActionOutcome(status: .indeterminate, message: "Vault move failed: \(error)")
        }
    }

    func restoreFromVault(_ request: ActionRequest) -> ActionOutcome {
        guard let source = request.sourcePath else {
            return ActionOutcome(status: .aborted, message: "Missing source path.")
        }
        let stamp = request.itemID.replacingOccurrences(of: "/", with: "_")
        let vaulted = vaultRoot + "/" + stamp + "/" + (source as NSString).lastPathComponent
        do {
            guard fileManager.fileExists(atPath: vaulted) else {
                return ActionOutcome(status: .aborted, message: "Nothing in the vault to restore.")
            }
            try fileManager.moveItem(atPath: vaulted, toPath: source)
            return ActionOutcome(status: .committed, message: "Restored from vault.")
        } catch {
            return ActionOutcome(status: .indeterminate, message: "Restore failed: \(error)")
        }
    }
}
