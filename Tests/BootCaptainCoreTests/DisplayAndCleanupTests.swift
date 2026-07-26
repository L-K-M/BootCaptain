import XCTest
@testable import BootCaptainCore

final class DisplayPolishTests: XCTestCase {
    func testTransientApplicationLabels() {
        XCTAssertTrue(DisplayPolish.isTransientLaunchdLabel(
            "application.ai.perplexity.macv3.1088234562.1088244873"))
        XCTAssertTrue(DisplayPolish.isTransientLaunchdLabel(
            "application.com.apple.ActivityMonitor.1152921500311908412.1152921500311908417"))
        XCTAssertTrue(DisplayPolish.isTransientLaunchdLabel(
            "application.app.zen-browser.zen.388608337.1091134354.4495DDE5-8CB0-41B9-A102-06A4142758D5"))
    }

    func testUUIDSuffixedLabelsAreTransient() {
        XCTAssertTrue(DisplayPolish.isTransientLaunchdLabel(
            "com.foo.session.4495DDE5-8CB0-41B9-A102-06A4142758D5"))
    }

    func testRealStartupLabelsAreNotTransient() {
        XCTAssertFalse(DisplayPolish.isTransientLaunchdLabel("com.docker.vmnetd"))
        XCTAssertFalse(DisplayPolish.isTransientLaunchdLabel("org.apache.httpd"))
        XCTAssertFalse(DisplayPolish.isTransientLaunchdLabel(
            "2BUA8C4S2C.com.1password.browser-helper"))
        XCTAssertFalse(DisplayPolish.isTransientLaunchdLabel("com.google.keystone.agent"))
    }

    func testPrettifyStripsTeamIDAndTLD() {
        XCTAssertEqual(DisplayPolish.prettifyLabel("2BUA8C4S2C.com.1password.browser-helper"),
                       "1password browser-helper")
        XCTAssertEqual(DisplayPolish.prettifyLabel("com.foo.helperd"), "foo helperd")
    }

    func testPrettifyDropsTrailingNumbers() {
        XCTAssertEqual(DisplayPolish.prettifyLabel("ch.lkmc.Gans.1060765833.1067779824"),
                       "lkmc Gans")
    }

    func testPrettifyNeverEmpty() {
        XCTAssertEqual(DisplayPolish.prettifyLabel("com"), "com")
        XCTAssertFalse(DisplayPolish.prettifyLabel("a.b").isEmpty)
    }
}

final class CleanupPlannerTests: XCTestCase {
    let homes = ["/Users/alice"]

    func makeItem(
        id: String = "launchAgent:com.foo",
        mechanism: Mechanism = .launchAgent,
        path: String? = "/Users/alice/Library/LaunchAgents/com.foo.plist",
        health: HealthState = .broken,
        trust: TrustClass = .unsigned,
        exec: String? = "/Applications/Gone.app/Contents/MacOS/gone",
        actionClass: ActionClass = .reversibleMutation,
        attribution: ResolvedAttribution = ResolvedAttribution()
    ) -> StartupItem {
        StartupItem(
            id: id, mechanism: mechanism, label: "com.foo", displayName: "Foo",
            sourcePath: path,
            recipe: LaunchRecipe(executablePath: exec),
            trust: trust, health: health, attribution: attribution,
            actionClass: actionClass)
    }

    func testBrokenUserAgentIsVaultMovable() {
        let plan = CleanupPlanner.plan(items: [makeItem()], userHomes: homes)
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].eligibility, .userVaultMove)
    }

    func testHealthyItemsExcluded() {
        let plan = CleanupPlanner.plan(items: [makeItem(health: .ok)], userHomes: homes)
        XCTAssertTrue(plan.isEmpty)
    }

    func testUnknownHealthExcluded() {
        // Never offer cleanup on "unknown" — only concrete brokenness.
        let plan = CleanupPlanner.plan(items: [makeItem(health: .unknown)], userHomes: homes)
        XCTAssertTrue(plan.isEmpty)
    }

    func testMutationForbiddenTrustNeverCandidate() {
        let apple = makeItem(id: "a", trust: .applePlatform)
        let managed = makeItem(id: "b", trust: .managed)
        let unknown = makeItem(id: "c", trust: .unknown)
        let conflicting = makeItem(id: "d", trust: .brokenOrConflicting)
        XCTAssertTrue(CleanupPlanner.plan(
            items: [apple, managed, unknown, conflicting], userHomes: homes).isEmpty)
    }

    func testRootOwnedDaemonExcludedWhileHelperOperationDisabled() {
        let item = makeItem(
            id: "launchDaemon:com.foo", mechanism: .launchDaemon,
            path: "/Library/LaunchDaemons/com.foo.plist")
        let plan = CleanupPlanner.plan(items: [item], userHomes: homes)
        XCTAssertTrue(plan.isEmpty)
    }

    func testPossiblyOrphanedItemNeedsMoreEvidence() {
        let item = makeItem(
            id: "classicLoginItem:/Applications/Gone.app",
            mechanism: .classicLoginItem,
            path: "/Applications/Gone.app",
            health: .possiblyOrphaned)
        let plan = CleanupPlanner.plan(items: [item], userHomes: homes)
        XCTAssertTrue(plan.isEmpty)
    }

    func testOtherUsersAgentNotVaultMovable() {
        // A broken agent in ANOTHER user's home is not ours to move unprivileged
        // — and it's not a /Library path either, so it drops out entirely.
        let item = makeItem(path: "/Users/bob/Library/LaunchAgents/com.foo.plist")
        let plan = CleanupPlanner.plan(items: [item], userHomes: homes)
        XCTAssertTrue(plan.isEmpty)
    }

    func testReadOnlyUnresolvedAndConflictingAttributionAreExcluded() {
        let readOnly = makeItem(id: "a", actionClass: .readOnly)
        var unresolved = makeItem(id: "b")
        unresolved.recipe?.isUnresolved = true
        let conflict = makeItem(
            id: "c", attribution: ResolvedAttribution(hasConflict: true))
        let plan = CleanupPlanner.plan(
            items: [readOnly, unresolved, conflict], userHomes: homes)
        XCTAssertTrue(plan.isEmpty)
    }
}
