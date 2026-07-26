import XCTest
@testable import BootCaptainCore

final class LaunchctlParsingTests: XCTestCase {
    func testListParsesRunningAndStopped() {
        let text = """
        PID\tStatus\tLabel
        1234\t0\tcom.example.running
        -\t78\tcom.example.configrejected
        -\t-\tcom.example.idle
        """
        let entries = LaunchctlListParser.parse(text)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].pid, 1234)
        XCTAssertTrue(entries[0].isRunning)
        XCTAssertEqual(entries[1].lastExitStatus, 78)
        XCTAssertFalse(entries[1].isRunning)
        XCTAssertNil(entries[2].pid)
    }

    func testPrintDisabledParses() {
        let text = """
        disabled services = {
            "com.example.off" => disabled
            "com.example.on" => enabled
        }
        """
        let map = LaunchctlDisabledParser.parse(text)
        XCTAssertEqual(map["com.example.off"], .disabled)
        XCTAssertEqual(map["com.example.on"], .explicitEnabled)
    }

    func testPrintServicesBlock() {
        let text = """
        com.apple.xpc.launchd.domain.system = {
            services = {
                12  0   com.example.a
                -   78  com.example.b
            }
        }
        """
        let services = LaunchctlPrintParser.parseServices(text)
        XCTAssertEqual(services.count, 2)
        XCTAssertEqual(services[0].pid, 12)
        XCTAssertEqual(services[1].lastExitCode, 78)
    }

    func testPrintDetailExtractsPath() {
        let text = """
        com.example.foo = {
            state = running
            pid = 4242
            path = /Library/LaunchDaemons/com.example.foo.plist
            runs = 3
            last exit code = 0
        }
        """
        let svc = LaunchctlPrintParser.parseDetail(text)
        XCTAssertEqual(svc?.label, "com.example.foo")
        XCTAssertEqual(svc?.path, "/Library/LaunchDaemons/com.example.foo.plist")
        XCTAssertEqual(svc?.pid, 4242)
        XCTAssertEqual(svc?.runs, 3)
    }
}

final class BTMDumpParsingTests: XCTestCase {
    let sample = """
    #57
        UUID: 9C7A9A2C-1111-2222-3333-444455556666
        Name: com.docker.vmnetd
        Developer Name: Docker Inc
        Team Identifier: 9BNSXJN65R
        Type: daemon (0x10)
        Disposition: [enabled, allowed, visible, notified] (0xb)
        Identifier: com.docker.vmnetd
        URL: file:///Library/LaunchDaemons/com.docker.vmnetd.plist
        Executable Path: /Library/PrivilegedHelperTools/com.docker.vmnetd
        Generation: 1
        Assoc. Bundle IDs: [com.docker.docker]
        Parent Identifier: Docker Inc
    #58
        UUID: AAAA1111-0000-0000-0000-000000000000
        Name: com.example.legacyagent
        Type: agent (0x8)
        Disposition: [disabled] (0x1)
        Identifier: com.example.legacyagent
    """

    func testParsesTwoRecords() {
        let records = BTMDumpParser.parse(sample)
        XCTAssertEqual(records.count, 2)
    }

    func testTypeAndDispositionBits() {
        let records = BTMDumpParser.parse(sample)
        let docker = records[0]
        XCTAssertTrue(docker.isDaemon)
        XCTAssertEqual(docker.teamIdentifier, "9BNSXJN65R")
        XCTAssertEqual(docker.willRun, true)   // enabled AND allowed
        XCTAssertEqual(docker.mechanism, .smAppServiceDaemon)
        XCTAssertEqual(docker.associatedBundleIDs, ["com.docker.docker"])
    }

    func testEnabledButNotAllowedDoesNotRun() {
        // Disposition 0x1 = enabled only, NOT allowed → willRun false.
        let records = BTMDumpParser.parse(sample)
        let legacy = records[1]
        XCTAssertTrue(legacy.dispEnabled)
        XCTAssertFalse(legacy.dispAllowed)
        XCTAssertEqual(legacy.willRun, false)
    }

    func testMissingDispositionIsNil() {
        let records = BTMDumpParser.parse("#1\n    UUID: X\n    Name: y\n")
        XCTAssertNil(records[0].willRun)
    }
}

final class CrashReportParsingTests: XCTestCase {
    func testTwoJSONDocumentSplit() {
        let ips = """
        {"app_name":"FooHelper","timestamp":"2026-07-26 09:00:00","bug_type":"309"}
        {"procName":"FooHelper","procPath":"/Applications/Foo.app/Contents/MacOS/FooHelper","parentPid":1,"termination":{"namespace":"DYLD","indicator":"Library not loaded: /opt/missing.dylib"}}
        """
        let report = CrashReportParser.parse(ips)
        XCTAssertNotNil(report)
        XCTAssertTrue(report!.isCrash)
        XCTAssertEqual(report!.procName, "FooHelper")
        XCTAssertTrue(report!.parentIsLaunchd)
        XCTAssertEqual(report!.terminationNamespace, "DYLD")
        XCTAssertEqual(report!.terminationReason, "Library not loaded: /opt/missing.dylib")
    }

    func testHeaderOnlyStillUsable() {
        let ips = #"{"app_name":"Bar","bug_type":"309"}"# + "\nnot json body"
        let report = CrashReportParser.parse(ips)
        XCTAssertEqual(report?.procName, "Bar")
    }
}

final class UnifiedLogTests: XCTestCase {
    func testNDJSONParse() {
        let text = """
        {"timestamp":"2026-07-26 09:00:00","eventMessage":"Service could not initialize","subsystem":"com.apple.xpc.launchd","processID":1}
        {"timestamp":"2026-07-26 09:00:01","eventMessage":"hello","subsystem":"com.apple.other"}
        """
        let records = UnifiedLogMatchers.parseNDJSON(text)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].subsystem, "com.apple.xpc.launchd")
    }

    func testClassifyMatchers() {
        XCTAssertEqual(
            UnifiedLogMatchers.classify("com.foo: Service could not initialize: 18E226: xpc"),
            .serviceCouldNotInitialize)
        XCTAssertEqual(
            UnifiedLogMatchers.classify("Service only ran for 2 seconds. Pushing respawn out by 10 seconds."),
            .throttledRespawn)
        XCTAssertNil(UnifiedLogMatchers.classify("perfectly normal message"))
    }
}

final class CronParsingTests: XCTestCase {
    func testUserCrontabParse() {
        let text = """
        # a comment
        FOO=bar
        0 9 * * 1-5 /usr/local/bin/backup.sh
        @reboot /usr/local/bin/startup.sh
        """
        let entries = CronParser.parse(text, style: .userCrontab)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].command, "/usr/local/bin/backup.sh")
        XCTAssertTrue(entries[1].runsAtReboot)
    }

    func testSystemCrontabHasUserColumn() {
        let text = "0 9 * * * root /usr/local/bin/task.sh"
        let entries = CronParser.parse(text, style: .systemCrontab)
        XCTAssertEqual(entries.first?.user, "root")
        XCTAssertEqual(entries.first?.command, "/usr/local/bin/task.sh")
    }

    func testReversibleToggleRoundTrip() {
        let text = "0 9 * * 1-5 /usr/local/bin/backup.sh"
        let disabled = CronParser.toggle(text, lineNumber: 0, disable: true)
        XCTAssertTrue(disabled.hasPrefix("# BOOTCAPTAIN-DISABLED: "))
        // Re-parse: the disabled entry is still discoverable and marked.
        let reparsed = CronParser.parse(disabled, style: .userCrontab)
        XCTAssertEqual(reparsed.count, 1)
        XCTAssertTrue(reparsed[0].isDisabledByBootCaptain)
        // Round-trip back.
        let reenabled = CronParser.toggle(disabled, lineNumber: 0, disable: false)
        XCTAssertEqual(reenabled, text)
    }
}
