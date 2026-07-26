import Foundation

/// Result of running a subprocess.
public struct ProcessResult: Sendable {
    public var status: Int32
    public var stdout: String
    public var stderr: String
    public var timedOut: Bool

    public var succeeded: Bool { status == 0 && !timedOut }
}

/// Thin, testable wrapper over `Foundation.Process`. The collectors depend on
/// the `CommandRunner` protocol so they can be unit-tested with a fake, and so
/// the privileged helper can route allow-listed commands through the same shape.
public protocol CommandRunner: Sendable {
    func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval) -> ProcessResult
}

extension CommandRunner {
    public func run(_ launchPath: String, _ arguments: [String]) -> ProcessResult {
        run(launchPath, arguments, timeout: 30)
    }
}

/// Real subprocess runner. Bounds output implicitly via pipe draining and kills
/// the process on timeout (PLAN.md §6.4 "bound output").
public struct ProcessRunner: CommandRunner {
    public init() {}

    public func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        // Collect asynchronously (into a locked box) so a large stream cannot
        // deadlock the pipe and mutation stays concurrency-safe.
        let out = DataBox()
        let err = DataBox()
        let outHandle = outPipe.fileHandleForReading
        let errHandle = errPipe.fileHandleForReading
        let ioQueue = DispatchQueue(label: "bootcaptain.process.io", attributes: .concurrent)
        let group = DispatchGroup()

        do {
            try process.run()
        } catch {
            return ProcessResult(status: -1, stdout: "",
                                 stderr: "failed to launch: \(error)", timedOut: false)
        }

        group.enter()
        ioQueue.async { out.set(outHandle.readDataToEndOfFile()); group.leave() }
        group.enter()
        ioQueue.async { err.set(errHandle.readDataToEndOfFile()); group.leave() }

        let deadline = DispatchTime.now() + timeout
        let timedOut = process.waitUntil(deadline: deadline) == false
        if timedOut {
            process.terminate()
            _ = process.waitUntil(deadline: .now() + 2)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        group.wait()

        return ProcessResult(
            status: process.terminationStatus,
            stdout: String(data: out.get(), encoding: .utf8) ?? "",
            stderr: String(data: err.get(), encoding: .utf8) ?? "",
            timedOut: timedOut)
    }
}

/// A tiny lock-protected data holder, safe to mutate from the IO queue.
final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func set(_ value: Data) { lock.lock(); data = value; lock.unlock() }
    func get() -> Data { lock.lock(); defer { lock.unlock() }; return data }
}

extension Process {
    /// Polls for termination until `deadline`; returns false on timeout.
    func waitUntil(deadline: DispatchTime) -> Bool {
        while isRunning {
            if DispatchTime.now() >= deadline { return false }
            usleep(20_000)  // 20 ms
        }
        return true
    }
}
