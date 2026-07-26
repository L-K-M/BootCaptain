import XCTest
@testable import BootCaptainCore

final class LaunchdParsingTests: XCTestCase {
    func makePlist(_ dict: [String: Any]) -> Data {
        try! PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    func testParsesLabelAndProgramArguments() throws {
        let data = makePlist([
            "Label": "com.example.agent",
            "ProgramArguments": ["/usr/local/bin/foo", "--serve"],
            "RunAtLoad": true,
        ])
        let job = try LaunchdJobParser.parse(data: data)
        XCTAssertEqual(job.label, "com.example.agent")
        XCTAssertEqual(job.programArguments, ["/usr/local/bin/foo", "--serve"])
        XCTAssertTrue(job.runAtLoad)
    }

    func testKeepAliveBooleanVsDictionary() throws {
        let boolJob = try LaunchdJobParser.parse(data: makePlist([
            "Label": "a", "KeepAlive": true,
        ]))
        XCTAssertEqual(boolJob.keepAlive, .always)

        let dictJob = try LaunchdJobParser.parse(data: makePlist([
            "Label": "b", "KeepAlive": ["SuccessfulExit": false],
        ]))
        XCTAssertEqual(dictJob.keepAlive, .conditional)
    }

    func testUnknownKeysPreserved() throws {
        let job = try LaunchdJobParser.parse(data: makePlist([
            "Label": "c", "SomeFutureKey": "x", "AnotherOne": 3,
        ]))
        XCTAssertEqual(job.unknownKeys, ["AnotherOne", "SomeFutureKey"])
    }

    func testMachServicesDetected() throws {
        let job = try LaunchdJobParser.parse(data: makePlist([
            "Label": "d", "MachServices": ["com.example.xpc": true],
        ]))
        XCTAssertTrue(job.machServices)
    }

    func testNonDictionaryThrows() {
        let data = try! PropertyListSerialization.data(
            fromPropertyList: ["a", "b"], format: .xml, options: 0)
        XCTAssertThrowsError(try LaunchdJobParser.parse(data: data)) { error in
            XCTAssertEqual(error as? LaunchdParseError, .notADictionary)
        }
    }

    func testBinaryPlistParses() throws {
        let data = try! PropertyListSerialization.data(
            fromPropertyList: ["Label": "bin", "RunAtLoad": true],
            format: .binary, options: 0)
        let job = try LaunchdJobParser.parse(data: data)
        XCTAssertEqual(job.label, "bin")
        XCTAssertTrue(job.runAtLoad)
    }
}

final class TriggerClassifierTests: XCTestCase {
    func testRunAtLoadIsSpeculative() {
        var job = LaunchdJob(); job.runAtLoad = true
        let (set, _) = TriggerClassifier.classify(job)
        XCTAssertTrue(set.contains(.speculative))
        XCTAssertTrue(set.runsAtStartup)
    }

    func testAnyKeepAliveImpliesSpeculative() {
        // EVIDENCE L-04: even the dictionary form implies RunAtLoad.
        var job = LaunchdJob(); job.keepAlive = .conditional
        let (set, ka) = TriggerClassifier.classify(job)
        XCTAssertTrue(set.contains(.speculative))
        XCTAssertEqual(ka, .conditional)
    }

    func testLegacyOnDemandFalseIsSpeculative() {
        var job = LaunchdJob(); job.onDemand = false
        let (set, _) = TriggerClassifier.classify(job)
        XCTAssertTrue(set.contains(.speculative))
    }

    func testMachServicesOnlyIsOnDemand() {
        var job = LaunchdJob(); job.machServices = true
        let (set, _) = TriggerClassifier.classify(job)
        XCTAssertTrue(set.contains(.onDemand))
        XCTAssertFalse(set.contains(.speculative))
        XCTAssertFalse(set.runsAtStartup)
    }

    func testScheduledAndEventAreIndependent() {
        var job = LaunchdJob()
        job.startCalendarInterval = true
        job.watchPaths = true
        let (set, _) = TriggerClassifier.classify(job)
        XCTAssertTrue(set.contains(.scheduled))
        XCTAssertTrue(set.contains(.event))
        XCTAssertFalse(set.contains(.onDemand))  // has real triggers
    }

    func testChipsForOnDemand() {
        var job = LaunchdJob(); job.machServices = true
        let (set, ka) = TriggerClassifier.classify(job)
        XCTAssertEqual(set.chips(keepAlive: ka), ["On demand — only when a client asks"])
    }
}

final class RecipeResolverTests: XCTestCase {
    func testProgramTakesPrecedence() {
        var job = LaunchdJob()
        job.program = "/opt/foo/bin/foo"
        job.programArguments = ["foo", "--x"]
        let recipe = RecipeResolver.resolve(job)
        XCTAssertEqual(recipe.executablePath, "/opt/foo/bin/foo")
        XCTAssertFalse(recipe.isInterpreter)
    }

    func testInterpreterTrapDetectsScript() {
        var job = LaunchdJob()
        job.programArguments = ["/bin/bash", "/Users/me/Library/hidden.sh"]
        let recipe = RecipeResolver.resolve(job)
        XCTAssertTrue(recipe.isInterpreter)
        XCTAssertEqual(recipe.scriptPath, "/Users/me/Library/hidden.sh")
        XCTAssertEqual(recipe.trustPath, "/Users/me/Library/hidden.sh")
    }

    func testInlineCodeIsUnresolved() {
        var job = LaunchdJob()
        job.programArguments = ["/usr/bin/osascript", "-e", "do something evil"]
        let recipe = RecipeResolver.resolve(job)
        XCTAssertTrue(recipe.isInterpreter)
        XCTAssertNil(recipe.scriptPath)
        XCTAssertTrue(recipe.isUnresolved)
    }

    func testBareCommandIsUnresolved() {
        var job = LaunchdJob()
        job.programArguments = ["foo", "--x"]  // no slash
        let recipe = RecipeResolver.resolve(job)
        XCTAssertNil(recipe.executablePath)
        XCTAssertTrue(recipe.isUnresolved)
    }

    func testBundleProgramNeedsRoot() {
        var job = LaunchdJob()
        job.bundleProgram = "Contents/MacOS/Helper"
        let withoutRoot = RecipeResolver.resolve(job)
        XCTAssertTrue(withoutRoot.isUnresolved)
        let withRoot = RecipeResolver.resolve(job, bundleRoot: "/Applications/Foo.app")
        XCTAssertEqual(withRoot.executablePath, "/Applications/Foo.app/Contents/MacOS/Helper")
        XCTAssertFalse(withRoot.isUnresolved)
    }
}
