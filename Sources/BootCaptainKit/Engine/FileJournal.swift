import Foundation
import BootCaptainCore

/// A durable on-disk journal of privileged mutations (AGENTS.md: "durable
/// prepared/committed journaling ... idempotent recovery"). Each record is one
/// JSON file named by its immutable id, written atomically. Both the app
/// (user-scope) and the helper (root-scope) use this so a mutation is always
/// preceded by a `prepared` record and followed by a terminal one.
///
/// This is intentionally minimal and Foundation-only so it is testable off a
/// Mac. `Data.write(.atomic)` gives an atomic rename; on macOS a fuller
/// implementation would add `F_FULLFSYNC` — noted as a hardening follow-up.
public struct FileJournal: Sendable {
    public let directory: String
    private let fileManager: FileManager

    public init(directory: String, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    /// Write (or overwrite) a record durably. Returns false on failure.
    @discardableResult
    public func write(_ record: JournalRecord) -> Bool {
        do {
            try fileManager.createDirectory(atPath: directory,
                                            withIntermediateDirectories: true)
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(record.id).json")
            let data = try JSONEncoder().encode(record)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Load every journal record currently on disk.
    public func all() -> [JournalRecord] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory) else { return [] }
        let decoder = JSONDecoder()
        return names.filter { $0.hasSuffix(".json") }.compactMap { name in
            let path = directory + "/" + name
            guard let data = fileManager.contents(atPath: path) else { return nil }
            return try? decoder.decode(JournalRecord.self, from: data)
        }
    }

    /// Records that were never resolved (prepared/indeterminate) and need
    /// reconciliation on startup (PLAN.md §6.3).
    public func unfinished() -> [JournalRecord] {
        ActionJournalLogic.unfinished(all())
    }

    /// Convenience: journal a prepared record for a request with its precomputed
    /// inverse, timestamped by the caller (Core forbids Date()).
    ///
    /// Returns `nil` if the prepared record could not be written durably. Callers
    /// MUST NOT perform the mutation in that case: a privileged action must never
    /// run without a persisted prepared record on disk (AGENTS.md: "a mutation is
    /// always preceded by a `prepared` record ... durable prepared/committed
    /// journaling").
    public func prepare(_ request: ActionRequest, at time: Double) -> JournalRecord? {
        let record = JournalRecord(
            id: UUID().uuidString,
            request: request,
            status: .prepared,
            inverse: ActionJournalLogic.inverse(of: request),
            preparedAt: time)
        guard write(record) else { return nil }
        return record
    }

    /// Convenience: mark a prepared record terminal.
    public func complete(_ record: JournalRecord, status: JournalStatus, at time: Double) {
        var updated = record
        updated.status = status
        updated.completedAt = time
        write(updated)
    }
}
