import Foundation
import ServiceManagement
import BootCaptainCore
import BootCaptainKit

/// Manages the privileged helper: registration via `SMAppService.daemon` and a
/// hardened XPC connection to it. The app defaults to **zero persistent
/// components** — the helper is registered only on the first privileged action
/// (PLAN.md §6.4 "the irony guard").
@MainActor
final class HelperClient: ObservableObject {
    static let plistName = "ch.lkmc.bootcaptain.helper.plist"

    enum HelperStatus: Equatable {
        case notRegistered
        case requiresApproval
        case enabled
        case unknown
    }

    @Published var status: HelperStatus = .notRegistered

    private var connection: NSXPCConnection?

    private var service: SMAppService {
        SMAppService.daemon(plistName: Self.plistName)
    }

    func refreshStatus() {
        switch service.status {
        case .notRegistered: status = .notRegistered
        case .enabled: status = .enabled
        case .requiresApproval: status = .requiresApproval
        case .notFound: status = .notRegistered
        @unknown default: status = .unknown
        }
    }

    /// Register the helper (prompts for admin approval). Idempotent.
    func register() throws {
        if service.status == .enabled { return }
        try service.register()
        refreshStatus()
    }

    /// Remove the helper entirely — the user-facing "Uninstall helper".
    func unregister() async {
        try? await service.unregister()
        connection?.invalidate()
        connection = nil
        refreshStatus()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: XPC

    private func makeConnection() -> NSXPCConnection {
        if let existing = connection { return existing }
        let conn = NSXPCConnection(machServiceName: HelperConstants.machServiceName,
                                   options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: BootCaptainHelperProtocol.self)
        // Pin the helper's designated requirement so the app only ever talks to
        // our signed helper (PLAN.md §6.4, mutual authentication).
        if #available(macOS 13.0, *) {
            try? conn.setCodeSigningRequirement(
                HelperRequirements.helperRequirement(teamID: currentTeamID()))
        }
        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in self?.connection = nil }
        }
        conn.resume()
        connection = conn
        return conn
    }

    /// Perform a typed action through the helper. Registers on demand.
    func perform(_ request: ActionRequest) async -> ActionOutcome {
        if status != .enabled {
            do { try register() } catch {
                return ActionOutcome(status: .aborted,
                    message: "Could not register helper: \(error.localizedDescription)")
            }
        }
        guard status == .enabled else {
            return ActionOutcome(status: .aborted,
                message: "The helper needs approval in System Settings ▸ Login Items.")
        }
        return await withCheckedContinuation { continuation in
            let proxy = makeConnection().remoteObjectProxyWithErrorHandler { error in
                continuation.resume(returning: ActionOutcome(
                    status: .indeterminate,
                    message: "Helper connection error: \(error.localizedDescription)"))
            } as? BootCaptainHelperProtocol
            guard let proxy else {
                continuation.resume(returning: ActionOutcome(
                    status: .aborted, message: "Helper unavailable."))
                return
            }
            proxy.perform(requestJSON: HelperCodec.encode(request)) { data in
                let outcome = HelperCodec.decode(ActionOutcome.self, from: data)
                    ?? ActionOutcome(status: .indeterminate, message: "No reply from helper.")
                continuation.resume(returning: outcome)
            }
        }
    }

    private func currentTeamID() -> String {
        // The app's own Team ID is used to build the helper requirement; both
        // are signed with the same identity.
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              let info = try? copySigningInfo(code),
              let team = info[kSecCodeInfoTeamIdentifier as String] as? String
        else { return HelperConstants.teamIdentifier }
        return team
    }

    private func copySigningInfo(_ code: SecCode) throws -> [String: Any]? {
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode,
                SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return nil }
        return info as? [String: Any]
    }
}

import Security
