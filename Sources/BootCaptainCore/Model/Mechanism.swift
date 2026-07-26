import Foundation

/// The persistence/startup mechanism a discovered item belongs to.
///
/// PLAN.md §2 draws a hard line between the **core startup/background** surface
/// (things that genuinely run at boot or GUI login) and the **advanced
/// execution surface** (extensions, shell/SSH/PAM, on-demand plugin hosts).
/// The `tier` property carries that distinction so the UI can present them
/// separately and never imply a shell rc file "runs at login".
public enum Mechanism: String, Codable, Sendable, CaseIterable {
    // Core startup/background
    case launchDaemon
    case launchAgent
    case smAppServiceDaemon
    case smAppServiceAgent
    case smAppServiceLoginItem
    case classicLoginItem
    case backgroundTaskManagement
    case windowRestoration
    case cron
    case at
    case periodic
    case managedBackgroundTask   // MDM / DDM services.background-tasks

    // Legacy / lingering
    case startupItem             // SystemStarter (inert)
    case launchdConf             // inert
    case rcScript
    case loginLogoutHook
    case emond

    // Advanced execution surface
    case kernelExtension
    case systemExtension
    case audioHALPlugin
    case authorizationPlugin
    case appExtension            // pluginkit-managed
    case dockTilePlugin
    case configurationProfile
    case cryptexJob
    case shellStartup            // zsh/bash rc, /etc/paths.d
    case sshStartup              // ~/.ssh/rc, forced commands
    case pamModule
    case folderAction
    case persistentEnvironment

    case unknown

    /// Product tier per PLAN.md §2.4.
    public enum Tier: String, Codable, Sendable {
        case core
        case legacy
        case advanced
    }

    public var tier: Tier {
        switch self {
        case .launchDaemon, .launchAgent, .smAppServiceDaemon, .smAppServiceAgent,
             .smAppServiceLoginItem, .classicLoginItem, .backgroundTaskManagement,
             .windowRestoration, .cron, .at, .periodic, .managedBackgroundTask:
            return .core
        case .startupItem, .launchdConf, .rcScript, .loginLogoutHook, .emond:
            return .legacy
        case .kernelExtension, .systemExtension, .audioHALPlugin, .authorizationPlugin,
             .appExtension, .dockTilePlugin, .configurationProfile, .cryptexJob,
             .shellStartup, .sshStartup, .pamModule, .folderAction,
             .persistentEnvironment, .unknown:
            return .advanced
        }
    }

    /// Human label for the UI.
    public var displayName: String {
        switch self {
        case .launchDaemon: return "Launch Daemon"
        case .launchAgent: return "Launch Agent"
        case .smAppServiceDaemon: return "Background Daemon (SMAppService)"
        case .smAppServiceAgent: return "Background Agent (SMAppService)"
        case .smAppServiceLoginItem: return "Login Item Helper"
        case .classicLoginItem: return "Open at Login"
        case .backgroundTaskManagement: return "Background Task"
        case .windowRestoration: return "Reopened Window"
        case .cron: return "cron Job"
        case .at: return "at Job"
        case .periodic: return "periodic Script"
        case .managedBackgroundTask: return "Managed Background Task"
        case .startupItem: return "Legacy Startup Item"
        case .launchdConf: return "launchd.conf (inert)"
        case .rcScript: return "rc Script"
        case .loginLogoutHook: return "Login/Logout Hook"
        case .emond: return "emond Rule"
        case .kernelExtension: return "Kernel Extension"
        case .systemExtension: return "System Extension"
        case .audioHALPlugin: return "Audio Plug-in"
        case .authorizationPlugin: return "Authorization Plug-in"
        case .appExtension: return "App Extension"
        case .dockTilePlugin: return "Dock Tile Plug-in"
        case .configurationProfile: return "Configuration Profile"
        case .cryptexJob: return "Cryptex Job (Apple)"
        case .shellStartup: return "Shell Startup File"
        case .sshStartup: return "SSH Startup"
        case .pamModule: return "PAM Module"
        case .folderAction: return "Folder Action"
        case .persistentEnvironment: return "Persistent Environment"
        case .unknown: return "Unknown"
        }
    }
}
