import XCTest
@testable import BootCaptainKit
import BootCaptainCore

final class RequestValidatorTests: XCTestCase {
    let homes = ["/Users/alice"]

    func testAllowsCanonicalDaemonDisable() {
        let req = ActionRequest(operation: .launchdDisable, itemID: "1",
                                label: "com.foo.bar", domain: "system",
                                sourcePath: "/Library/LaunchDaemons/com.foo.bar.plist")
        if case .success = RequestValidator.validate(req, userHomes: homes) {} else {
            XCTFail("canonical daemon disable should be allowed")
        }
    }

    func testRejectsOutsideRoot() {
        let req = ActionRequest(operation: .launchdBootout, itemID: "1",
                                label: "com.foo", domain: "system",
                                sourcePath: "/tmp/evil.plist")
        if case .failure(.pathNotAllowed) = RequestValidator.validate(req, userHomes: homes) {} else {
            XCTFail("should reject /tmp path")
        }
    }

    func testRejectsPathTraversal() {
        let req = ActionRequest(operation: .moveToVault, itemID: "../../etc",
                                sourcePath: "/Library/LaunchDaemons/x.plist")
        // itemID traversal is caught after the path check.
        let result = RequestValidator.validate(req, userHomes: homes)
        if case .failure(.pathEscapesRoot) = result {} else {
            XCTFail("should reject itemID traversal, got \(result)")
        }
    }

    func testRejectsDoubleSlashAndDotDot() {
        XCTAssertFalse(RequestValidator.isAllowedSource("/Library/LaunchDaemons/../x", userHomes: homes))
        XCTAssertFalse(RequestValidator.isAllowedSource("/Library//LaunchDaemons/x", userHomes: homes))
    }

    func testUserAgentPathAllowed() {
        XCTAssertTrue(RequestValidator.isAllowedSource(
            "/Users/alice/Library/LaunchAgents/com.foo.plist", userHomes: homes))
        XCTAssertFalse(RequestValidator.isAllowedSource(
            "/Users/bob/Library/LaunchAgents/com.foo.plist", userHomes: homes))
    }

    func testBadLabelRejected() {
        let req = ActionRequest(operation: .launchdDisable, itemID: "1",
                                label: "com.foo; rm -rf /", domain: "system")
        if case .failure(.badLabel) = RequestValidator.validate(req, userHomes: homes) {} else {
            XCTFail("should reject label with shell metacharacters")
        }
    }

    func testDomainValidation() {
        XCTAssertTrue(RequestValidator.isValidDomain("system"))
        XCTAssertTrue(RequestValidator.isValidDomain("gui/501"))
        XCTAssertTrue(RequestValidator.isValidDomain("user/0"))
        XCTAssertFalse(RequestValidator.isValidDomain("gui/notanumber"))
        XCTAssertFalse(RequestValidator.isValidDomain("root"))
    }

    func testCronRequiresLine() {
        let req = ActionRequest(operation: .cronToggleEntry, itemID: "1",
                                sourcePath: "/usr/lib/cron/tabs/alice")
        if case .failure(.missingField) = RequestValidator.validate(req, userHomes: homes) {} else {
            XCTFail("cron toggle needs a line number")
        }
    }
}
