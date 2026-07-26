import XCTest
@testable import BootCaptainCore

final class MutationPolicyTests: XCTestCase {
    func testNoPrivilegedOperationsAreEnabled() {
        for operation in [
            ActionRequest.Operation.moveToVault,
            .restoreFromVault,
            .launchdDisable,
            .launchdEnable,
            .launchdBootout,
            .cronToggleEntry,
        ] {
            XCTAssertFalse(operation.isEnabledInCurrentBuild)
        }
    }
}
