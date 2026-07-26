import Foundation
import BootCaptainCore

/// Runtime facts a collector needs, injected so collectors stay testable.
public struct ScanContext: @unchecked Sendable {
    public var runner: CommandRunner
    // FileManager.default is thread-safe per Apple docs; we store only the
    // shared instance, so @unchecked Sendable is sound here.
    public var fileManager: FileManager
    /// Home directories to scan for per-user agents / login artifacts.
    public var userHomes: [String]
    /// The current user's uid (for `gui/<uid>` domain targeting).
    public var currentUID: Int
    public var osBuild: String?
    /// Whether the scan has root (via the helper); gates root-only collectors.
    public var hasRoot: Bool
    /// Whether the process holds Full Disk Access (best-effort probe result).
    public var hasFullDiskAccess: Bool

    public init(
        runner: CommandRunner = ProcessRunner(),
        fileManager: FileManager = .default,
        userHomes: [String] = [],
        currentUID: Int = 0,
        osBuild: String? = nil,
        hasRoot: Bool = false,
        hasFullDiskAccess: Bool = false
    ) {
        self.runner = runner
        self.fileManager = fileManager
        self.userHomes = userHomes
        self.currentUID = currentUID
        self.osBuild = osBuild
        self.hasRoot = hasRoot
        self.hasFullDiskAccess = hasFullDiskAccess
    }
}

/// What a collector returns: discovered items plus its own coverage status.
public struct CollectorResult: Sendable {
    public var items: [StartupItem]
    public var coverage: CollectorCoverage
    public init(items: [StartupItem], coverage: CollectorCoverage) {
        self.items = items
        self.coverage = coverage
    }
}

/// One source of startup items. Collectors never mutate; they observe.
public protocol Collector: Sendable {
    var name: String { get }
    var mechanism: Mechanism { get }
    func collect(_ context: ScanContext) -> CollectorResult
}

extension Collector {
    /// Helper to build a coverage record.
    func coverage(_ status: CollectorCoverage.Status, count: Int = 0, detail: String? = nil) -> CollectorCoverage {
        CollectorCoverage(collector: name, mechanism: mechanism,
                          status: status, itemCount: count, detail: detail)
    }
}
