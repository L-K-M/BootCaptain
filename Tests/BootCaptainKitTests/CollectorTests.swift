import XCTest
@testable import BootCaptainKit
import BootCaptainCore

/// A scripted command runner: returns canned output keyed by the first argument.
struct FakeRunner: CommandRunner {
    let responses: [String: ProcessResult]
    let fallback: ProcessResult

    init(_ responses: [String: ProcessResult],
         fallback: ProcessResult = ProcessResult(status: 1, stdout: "", stderr: "", timedOut: false)) {
        self.responses = responses
        self.fallback = fallback
    }

    func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval) -> ProcessResult {
        let key = arguments.first ?? launchPath
        return responses[key] ?? fallback
    }

    static func ok(_ stdout: String) -> ProcessResult {
        ProcessResult(status: 0, stdout: stdout, stderr: "", timedOut: false)
    }
}

final class ProcessRunnerTests: XCTestCase {
    func testRunsRealSubprocess() throws {
        // echo exists on Linux CI and macOS.
        let echo = FileManager.default.fileExists(atPath: "/bin/echo") ? "/bin/echo" : "/usr/bin/echo"
        let result = ProcessRunner().run(echo, ["hello"])
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
    }

    func testNonexistentBinaryFailsCleanly() {
        let result = ProcessRunner().run("/no/such/binary", [])
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.status, -1)
    }
}

final class SystemExtensionCollectorTests: XCTestCase {
    func testParsesExtensions() {
        let output = """
        1 extension(s)
        --- com.apple.system_extension.network_extension
        enabled\tactive\tteamID\tbundleID (version)\tname\t[activated enabled]
        *\t*\t9BNSXJN65R\tcom.acme.vpn (1.0)\tACME VPN\t[activated enabled]
        """
        let ctx = ScanContext(runner: FakeRunner(["list": FakeRunner.ok(output)]))
        let result = SystemExtensionCollector().collect(ctx)
        XCTAssertFalse(result.items.isEmpty)
        let vpn = result.items.first { $0.label == "com.acme.vpn" }
        XCTAssertNotNil(vpn)
        XCTAssertEqual(vpn?.attribution.teamIdentifier, "9BNSXJN65R")
        XCTAssertEqual(vpn?.actionClass, .guidedAction)
    }

    func testMissingToolIsSkipped() {
        let ctx = ScanContext(runner: FakeRunner([:],
            fallback: ProcessResult(status: -1, stdout: "", stderr: "", timedOut: false)))
        let result = SystemExtensionCollector().collect(ctx)
        XCTAssertEqual(result.coverage.status, .skippedUnsupported)
    }
}

final class LoginItemsCollectorTests: XCTestCase {
    func testParsesPaths() {
        let out = "/Applications/Dropbox.app, /Applications/Rectangle.app"
        let ctx = ScanContext(runner: FakeRunner(["-e": FakeRunner.ok(out)]))
        let result = LoginItemsCollector().collect(ctx)
        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(result.items[0].actionClass, .guidedAction)
    }

    func testDeniedAutomation() {
        let ctx = ScanContext(runner: FakeRunner([:]))
        let result = LoginItemsCollector().collect(ctx)
        XCTAssertEqual(result.coverage.status, .deniedPermission)
    }
}

final class LegacyCensusCollectorTests: XCTestCase {
    func testVersionSensitiveArtifactsDoNotClaimExecutionTrigger() {
        let probes = LegacyCensusCollector().probes
        let emond = probes.first { $0.mechanism == .emond }
        let periodic = probes.first { $0.mechanism == .periodic }

        XCTAssertNotNil(emond, "emond probe should exist")
        XCTAssertNotNil(periodic, "periodic probe should exist")
        XCTAssertTrue(emond?.triggers.isEmpty ?? false,
                      "emond file presence should not imply a trigger")
        XCTAssertTrue(periodic?.triggers.isEmpty ?? false,
                      "periodic file presence should not imply a trigger")
        XCTAssertTrue(emond?.note.contains("does not establish") == true)
        XCTAssertTrue(periodic?.note.contains("does not establish") == true)
    }
}

final class LaunchctlStateCollectorTests: XCTestCase {
    func testBuildsServiceAndOverrideMaps() {
        let printOut = """
        com.apple.xpc.launchd.domain.system = {
            services = {
                42  0   com.acme.daemon
                -   78  com.acme.broken
            }
        }
        """
        let disabledOut = """
        disabled services = {
            "com.acme.broken" => disabled
        }
        """
        let runner = FakeRunner([
            "print": FakeRunner.ok(printOut),
            "print-disabled": FakeRunner.ok(disabledOut),
            "list": FakeRunner.ok("PID\tStatus\tLabel\n42\t0\tcom.acme.daemon"),
        ])
        let ctx = ScanContext(runner: runner, currentUID: 501)
        let state = LaunchctlStateCollector().collect(ctx)
        XCTAssertEqual(state.services["com.acme.daemon"]?.pid, 42)
        XCTAssertEqual(state.overrideState(domain: "system", label: "com.acme.broken"), .disabled)
    }
}

final class BTMCollectorTests: XCTestCase {
    func testNeedsRoot() {
        let ctx = ScanContext(runner: FakeRunner([:]), hasRoot: false)
        let result = BTMCollector().collect(ctx)
        XCTAssertEqual(result.coverage.status, .deniedPermission)
        XCTAssertTrue(result.items.isEmpty)
    }

    func testParsesWhenRoot() {
        let dump = """
        #1
            UUID: ABCD-1
            Name: com.acme.helper
            Team Identifier: ACME123456
            Type: daemon (0x10)
            Disposition: [enabled, allowed, visible, notified] (0xb)
            Identifier: com.acme.helper
        """
        let ctx = ScanContext(runner: FakeRunner(["dumpbtm": FakeRunner.ok(dump)]), hasRoot: true)
        let result = BTMCollector().collect(ctx)
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].state.override, .absentDefault)  // willRun == true
    }
}

final class ScanExportTests: XCTestCase {
    func testRedactsUserPaths() throws {
        let item = StartupItem(
            id: "x", mechanism: .launchAgent, label: "com.foo",
            displayName: "Foo", sourcePath: "/Users/alice/Library/LaunchAgents/com.foo.plist")
        let result = ScanResult(items: [item],
            coverage: CoverageReport(collectors: []), generatedAt: 0)
        let data = try ScanExport().json(result, redact: true, homes: ["/Users/alice"])
        // Normalise the Linux-Foundation forward-slash escaping before asserting.
        let text = String(data: data, encoding: .utf8)!.replacingOccurrences(of: "\\/", with: "/")
        XCTAssertFalse(text.contains("alice"))
        XCTAssertFalse(text.contains("/Users/alice"))
        XCTAssertTrue(text.contains("~/Library") || text.contains("/Users/<user>"))
    }
}

final class AttributionEngineHelperTests: XCTestCase {
    func testOwningAppWalk() {
        let app = AttributionEngine.owningApp(
            of: "/Applications/Dropbox.app/Contents/Library/LaunchAgents/x.plist")
        XCTAssertEqual(app?.name, "Dropbox.app")
        XCTAssertEqual(app?.path, "/Applications/Dropbox.app")
    }

    func testReverseDNSSkipsApple() {
        XCTAssertNil(AttributionEngine.reverseDNSVendor("com.apple.foo"))
        XCTAssertEqual(AttributionEngine.reverseDNSVendor("com.dropbox.agent"), "Dropbox")
    }

    func testVendorFromPkgID() {
        XCTAssertEqual(AttributionEngine.vendorFromPkgID("com.microsoft.pkg.autoupdate"), "Microsoft")
    }

    func testReceiptWorthCheckingExcludesSystemPaths() {
        XCTAssertFalse(AttributionEngine.receiptWorthChecking("/System/Library/LaunchDaemons/com.apple.x.plist"))
        XCTAssertFalse(AttributionEngine.receiptWorthChecking("/Library/Apple/System/Library/LaunchDaemons/x.plist"))
        XCTAssertFalse(AttributionEngine.receiptWorthChecking("/usr/libexec/foo"))
        XCTAssertTrue(AttributionEngine.receiptWorthChecking("/Library/LaunchDaemons/com.acme.helper.plist"))
        XCTAssertTrue(AttributionEngine.receiptWorthChecking("/Users/alice/Library/LaunchAgents/x.plist"))
    }
}

/// A runner that records every invocation so we can assert pkgutil is not spawned
/// for OS-shipped items (the scan performance fix).
final class RecordingRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var calls: [(String, [String])] = []
    func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval) -> ProcessResult {
        lock.lock(); calls.append((launchPath, arguments)); lock.unlock()
        return ProcessResult(status: 1, stdout: "", stderr: "", timedOut: false)
    }
}

final class AttributionEnginePerfTests: XCTestCase {
    func testNoPkgutilForSystemItem() {
        let runner = RecordingRunner()
        let engine = AttributionEngine(
            attributions: AttributionsPlistReader(path: "/nonexistent"),
            receipts: ReceiptInspector(), runner: runner)
        let item = StartupItem(
            id: "launchDaemon:com.apple.foo", mechanism: .launchDaemon,
            label: "com.apple.foo", displayName: "com.apple.foo",
            sourcePath: "/System/Library/LaunchDaemons/com.apple.foo.plist")
        _ = engine.attribute(item)
        XCTAssertFalse(runner.calls.contains { $0.0.contains("pkgutil") },
                       "pkgutil must not be spawned for a /System item")
    }

    func testPkgutilForThirdPartyItem() {
        let runner = RecordingRunner()
        let engine = AttributionEngine(
            attributions: AttributionsPlistReader(path: "/nonexistent"),
            receipts: ReceiptInspector(), runner: runner)
        let item = StartupItem(
            id: "launchDaemon:com.acme", mechanism: .launchDaemon,
            label: "com.acme.helper", displayName: "com.acme.helper",
            sourcePath: "/Library/LaunchDaemons/com.acme.helper.plist")
        _ = engine.attribute(item)
        XCTAssertTrue(runner.calls.contains { $0.0.contains("pkgutil") },
                      "pkgutil should be consulted for a /Library item")
    }
}
