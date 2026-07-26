import XCTest
@testable import BootCaptainCore

final class TrustClassifierTests: XCTestCase {
    func testApplePlatformRequiresAnchorAndSSV() {
        let sig = SigningIdentity(isPlatformBinary: true, isValid: .yes, anchorApple: .yes)
        let input = TrustInputs(signing: [sig], onSSV: true, label: "com.apple.foo")
        XCTAssertEqual(TrustClassifier.classify(input), .applePlatform)
        XCTAssertTrue(TrustClassifier.classify(input).isMutationForbidden)
    }

    func testAppleSignedOffSSVIsDistributed() {
        let sig = SigningIdentity(isValid: .yes, anchorApple: .yes)
        let input = TrustInputs(signing: [sig], onSSV: false, appleControlledLocation: true)
        XCTAssertEqual(TrustClassifier.classify(input), .appleDistributed)
    }

    func testSpoofedAppleLabelIsRedFlag() {
        // com.apple.* label but NOT Apple-signed → conflicting.
        let sig = SigningIdentity(teamIdentifier: "ABCDE12345", isValid: .yes, anchorApple: .no)
        let input = TrustInputs(signing: [sig], label: "com.apple.appstore")
        XCTAssertEqual(TrustClassifier.classify(input), .brokenOrConflicting)
    }

    func testManagedWins() {
        let sig = SigningIdentity(teamIdentifier: "ABCDE12345", isValid: .yes)
        let input = TrustInputs(signing: [sig], isManaged: true)
        XCTAssertEqual(TrustClassifier.classify(input), .managed)
        XCTAssertTrue(TrustClass.managed.isMutationForbidden)
    }

    func testCrossSliceTeamMismatchIsConflict() {
        let a = SigningIdentity(architecture: "arm64", teamIdentifier: "AAAAA11111", isValid: .yes)
        let b = SigningIdentity(architecture: "x86_64", teamIdentifier: "BBBBB22222", isValid: .yes)
        XCTAssertEqual(TrustClassifier.classify(TrustInputs(signing: [a, b])), .brokenOrConflicting)
    }

    func testInvalidSignatureIsBroken() {
        let sig = SigningIdentity(teamIdentifier: "ABCDE12345", isValid: .no)
        XCTAssertEqual(TrustClassifier.classify(TrustInputs(signing: [sig])), .brokenOrConflicting)
    }

    func testDeveloperIDThirdParty() {
        let sig = SigningIdentity(teamIdentifier: "G7HH3F8CAK",
                                  authority: "Developer ID Application: Dropbox, Inc.",
                                  isValid: .yes, anchorApple: .no, anchorAppleGeneric: .yes)
        let input = TrustInputs(signing: [sig], label: "com.dropbox.agent")
        XCTAssertEqual(TrustClassifier.classify(input), .developerIDUnnotarized)
        XCTAssertFalse(TrustClass.developerIDUnnotarized.isMutationForbidden)
    }

    func testNoSigningIsUnknown() {
        XCTAssertEqual(TrustClassifier.classify(TrustInputs()), .unknown)
    }
}

final class SafetyPolicyTests: XCTestCase {
    func testAppleItemsNeverMutated() {
        let d = SafetyPolicy.decide(mechanism: .launchDaemon, trust: .applePlatform,
            recipe: LaunchRecipe(executablePath: "/x"), overrideState: .absentDefault,
            label: "com.apple.foo", isInert: false)
        XCTAssertEqual(d.actionClass, .readOnly)
    }

    func testCriticalLabelBlocked() {
        let d = SafetyPolicy.decide(mechanism: .launchDaemon, trust: .developerIDNotarized,
            recipe: LaunchRecipe(executablePath: "/x"), overrideState: .absentDefault,
            label: "com.apple.tccd", isInert: false)
        XCTAssertEqual(d.actionClass, .readOnly)
    }

    func testUnresolvedRecipeFailsClosed() {
        let d = SafetyPolicy.decide(mechanism: .launchAgent, trust: .developerIDNotarized,
            recipe: LaunchRecipe(isUnresolved: true), overrideState: .absentDefault,
            label: "com.foo", isInert: false)
        XCTAssertEqual(d.actionClass, .readOnly)
    }

    func testUnknownOverrideBecomesGuided() {
        let d = SafetyPolicy.decide(mechanism: .launchAgent, trust: .developerIDNotarized,
            recipe: LaunchRecipe(executablePath: "/x"), overrideState: .unknown,
            label: "com.foo", isInert: false)
        XCTAssertEqual(d.actionClass, .guidedAction)
    }

    func testUnqualifiedThirdPartyLaunchdIsGuided() {
        let d = SafetyPolicy.decide(mechanism: .launchAgent, trust: .developerIDNotarized,
            recipe: LaunchRecipe(executablePath: "/x"), overrideState: .absentDefault,
            label: "com.dropbox.agent", isInert: false)
        XCTAssertEqual(d.actionClass, .guidedAction)
    }

    func testSMAppServiceItemIsGuided() {
        let d = SafetyPolicy.decide(mechanism: .smAppServiceDaemon, trust: .developerIDNotarized,
            recipe: LaunchRecipe(executablePath: "/x"), overrideState: .absentDefault,
            label: "com.foo", isInert: false)
        XCTAssertEqual(d.actionClass, .guidedAction)
    }

    func testInertIsReadOnly() {
        let d = SafetyPolicy.decide(mechanism: .startupItem, trust: .unsigned,
            recipe: nil, overrideState: .unknown, label: nil, isInert: true)
        XCTAssertEqual(d.actionClass, .readOnly)
    }
}

final class SafeStateDeriverTests: XCTestCase {
    func testRunningIsActiveNow() {
        let d = SafeStateDeriver.derive(.init(state: StateAxes(running: .yes)))
        XCTAssertEqual(d.state, .activeNow)
        XCTAssertEqual(d.confidence, .high)
    }

    func testCrashEvidenceIsFailure() {
        let ev = EvidenceItem(origin: .crashReport, summary: "Crashed with SIGSEGV")
        let d = SafeStateDeriver.derive(.init(state: StateAxes(), evidence: [ev]))
        XCTAssertEqual(d.state, .failureEvidence)
    }

    func testNoCoverageNeverBecomesNeverAttempted() {
        let d = SafeStateDeriver.derive(.init(
            state: StateAxes(configured: .yes), hasUsableCoverage: false))
        XCTAssertEqual(d.state, .coverageIncomplete)
        XCTAssertNotEqual(d.state, .configuredNotObserved)
    }

    func testConfiguredButUnobservedWithCoverage() {
        let d = SafeStateDeriver.derive(.init(
            state: StateAxes(configured: .yes), evidence: [], hasUsableCoverage: true))
        XCTAssertEqual(d.state, .configuredNotObserved)
    }

    func testDisabledIsNotEligible() {
        let d = SafeStateDeriver.derive(.init(state: StateAxes(override: .disabled)))
        XCTAssertEqual(d.state, .notEligibleAtSnapshot)
    }

    func testNeverClaimsSucceeded() {
        // No path in the deriver should ever produce `.succeeded`.
        let cases: [SafeStateDeriver.Inputs] = [
            .init(state: StateAxes(running: .yes)),
            .init(state: StateAxes(configured: .yes)),
            .init(state: StateAxes(), evidence: [EvidenceItem(origin: .unifiedLog, summary: "launched")]),
        ]
        for c in cases { XCTAssertNotEqual(SafeStateDeriver.derive(c).state, .succeeded) }
    }
}

final class AttributionScorerTests: XCTestCase {
    func testHighestWeightWins() {
        let signals = [
            AttributionSignal(kind: .labelHeuristic, vendorName: "Maybe Corp", weight: 0.2),
            AttributionSignal(kind: .bundleContainment, vendorName: "Dropbox",
                              productName: "Dropbox", weight: 1.0),
        ]
        let r = AttributionScorer.resolve(signals)
        XCTAssertEqual(r.vendorName, "Dropbox")
        XCTAssertEqual(r.productName, "Dropbox")
        XCTAssertEqual(r.confidence, .high)
    }

    func testConflictDowngradesConfidence() {
        let signals = [
            AttributionSignal(kind: .btmRecord, vendorName: "Vendor A", weight: 0.9),
            AttributionSignal(kind: .codeSignatureTeamID, vendorName: "Vendor B",
                              teamIdentifier: "ZZZZZ99999", weight: 0.8),
            AttributionSignal(kind: .associatedBundleID, vendorName: "Vendor A",
                              teamIdentifier: "AAAAA11111", weight: 0.85),
        ]
        let r = AttributionScorer.resolve(signals)
        XCTAssertTrue(r.hasConflict)
        XCTAssertNotEqual(r.confidence, .high)
    }

    func testEmptyIsUnknownTitle() {
        XCTAssertEqual(AttributionScorer.resolve([]).displayTitle, "Unknown item")
    }
}

final class CatalogTests: XCTestCase {
    func testTeamIDMatch() {
        let e = Catalog.seed.match(teamID: "9BNSXJN65R", label: nil)
        XCTAssertEqual(e?.vendor, "Docker")
    }

    func testLongestPrefixWins() {
        let e = Catalog.seed.match(teamID: nil, label: "com.google.keystone.agent")
        XCTAssertEqual(e?.vendor, "Google")
    }

    func testNoMatchReturnsNil() {
        XCTAssertNil(Catalog.seed.match(teamID: "NONE", label: "org.unknown.thing"))
    }
}

final class ActionJournalTests: XCTestCase {
    func testDisableInverseIsEnable() {
        let req = ActionRequest(operation: .launchdDisable, itemID: "1",
                                label: "com.foo", domain: "gui/501")
        let inv = ActionJournalLogic.inverse(of: req)
        XCTAssertEqual(inv?.operation, .launchdEnable)
        XCTAssertEqual(inv?.label, "com.foo")
    }

    func testBootoutInverseNeedsSourcePath() {
        let noPath = ActionRequest(operation: .launchdBootout, itemID: "1", label: "com.foo")
        XCTAssertNil(ActionJournalLogic.inverse(of: noPath))
        let withPath = ActionRequest(operation: .launchdBootout, itemID: "1",
                                     label: "com.foo", domain: "system",
                                     sourcePath: "/Library/LaunchDaemons/com.foo.plist")
        XCTAssertNotNil(ActionJournalLogic.inverse(of: withPath))
    }

    func testUnfinishedRecordsNeedReconcile() {
        let records = [
            JournalRecord(id: "a", request: .init(operation: .launchdDisable, itemID: "1"),
                          status: .committed, preparedAt: 0),
            JournalRecord(id: "b", request: .init(operation: .launchdDisable, itemID: "2"),
                          status: .indeterminate, preparedAt: 0),
            JournalRecord(id: "c", request: .init(operation: .launchdDisable, itemID: "3"),
                          status: .prepared, preparedAt: 0),
        ]
        let unfinished = ActionJournalLogic.unfinished(records)
        XCTAssertEqual(Set(unfinished.map(\.id)), ["b", "c"])
    }
}

final class HealthDeriverTests: XCTestCase {
    func testMissingExecutableIsBroken() {
        let h = HealthDeriver.derive(.init(executableExists: .no))
        XCTAssertEqual(h, .broken)
    }

    func testMissingVolumeIsOrphaned() {
        let h = HealthDeriver.derive(.init(
            executableExists: .yes, pointsToMissingVolume: true))
        XCTAssertEqual(h, .possiblyOrphaned)
    }

    func testRuntimeFailureIsFailing() {
        let h = HealthDeriver.derive(.init(
            executableExists: .yes, diagnosis: .failureEvidence))
        XCTAssertEqual(h, .failing)
    }

    func testHealthyItem() {
        let h = HealthDeriver.derive(.init(executableExists: .yes, executableIsRunnable: .yes))
        XCTAssertEqual(h, .ok)
    }
}

final class StateAxesTests: XCTestCase {
    func testDisabledOverrideIsOff() {
        XCTAssertEqual(StateAxes(override: .disabled).effectivelyEnabled, .no)
    }

    func testAmbiguousIsUnknown() {
        XCTAssertEqual(StateAxes().effectivelyEnabled, .unknown)
    }

    func testRunningIsOn() {
        XCTAssertEqual(StateAxes(running: .yes).effectivelyEnabled, .yes)
    }
}
