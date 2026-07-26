import XCTest
@testable import BootCaptainKit
import BootCaptainCore

final class FileJournalTests: XCTestCase {
    private func tempDir() -> String {
        let dir = NSTemporaryDirectory() + "bootcaptain-journal-test-" + UUID().uuidString
        return dir
    }

    func testPrepareThenCompleteRoundTrips() {
        let journal = FileJournal(directory: tempDir())
        let request = ActionRequest(operation: .moveToVault, itemID: "launchDaemon:com.foo",
                                    sourcePath: "/Library/LaunchDaemons/com.foo.plist")
        let record = journal.prepare(request, at: 1000)
        XCTAssertEqual(record.status, .prepared)
        XCTAssertNotNil(record.inverse)
        XCTAssertEqual(record.inverse?.operation, .restoreFromVault)

        journal.complete(record, status: .committed, at: 1001)
        let all = journal.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.status, .committed)
        XCTAssertEqual(all.first?.completedAt, 1001)
    }

    func testUnfinishedFindsPreparedAndIndeterminate() {
        let journal = FileJournal(directory: tempDir())
        let a = journal.prepare(ActionRequest(operation: .moveToVault, itemID: "a"), at: 1)
        let b = journal.prepare(ActionRequest(operation: .moveToVault, itemID: "b"), at: 2)
        let c = journal.prepare(ActionRequest(operation: .moveToVault, itemID: "c"), at: 3)
        journal.complete(a, status: .committed, at: 10)   // settled
        journal.complete(b, status: .indeterminate, at: 11) // needs reconcile
        _ = c                                                // left prepared

        let unfinished = Set(journal.unfinished().map { $0.request.itemID })
        XCTAssertEqual(unfinished, ["b", "c"])
    }

    func testAllIgnoresNonJSON() {
        let dir = tempDir()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? "not json".data(using: .utf8)!.write(to: URL(fileURLWithPath: dir + "/stray.txt"))
        let journal = FileJournal(directory: dir)
        journal.prepare(ActionRequest(operation: .moveToVault, itemID: "x"), at: 1)
        XCTAssertEqual(journal.all().count, 1)
    }
}
