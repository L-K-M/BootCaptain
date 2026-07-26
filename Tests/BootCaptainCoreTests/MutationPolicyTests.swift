import XCTest
@testable import BootCaptainCore

final class MutationPolicyTests: XCTestCase {
    func testOnlyReversibleVaultOpsAreEnabled() {
        XCTAssertTrue(ActionRequest.Operation.moveToVault.isEnabledInCurrentBuild)
        XCTAssertTrue(ActionRequest.Operation.restoreFromVault.isEnabledInCurrentBuild)
    }

    func testLaunchdAndCronMutationsStayDisabled() {
        XCTAssertFalse(ActionRequest.Operation.launchdDisable.isEnabledInCurrentBuild)
        XCTAssertFalse(ActionRequest.Operation.launchdEnable.isEnabledInCurrentBuild)
        XCTAssertFalse(ActionRequest.Operation.launchdBootout.isEnabledInCurrentBuild)
        XCTAssertFalse(ActionRequest.Operation.cronToggleEntry.isEnabledInCurrentBuild)
    }
}
