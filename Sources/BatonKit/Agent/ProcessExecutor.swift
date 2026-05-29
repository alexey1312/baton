import Foundation

/// Runs a single ``ProcessInvocation``, draining stdout/stderr concurrently so a
/// chatty agent cannot deadlock on a full pipe buffer, installing the termination
/// handler before starting the process, and enforcing a per-invocation timeout.
///
/// Ported from ExFig's subprocess runner pattern.
public struct ProcessExecutor: Sendable {
    /// Grace period after SIGTERM before escalating to SIGKILL on a child that
    /// traps or ignores SIGTERM (POSIX only — `terminate()` is already forceful on
    /// Windows).
    private static let killGraceSeconds = 5

    public init() {}

    /// Run `invocation`, returning the captured result. Throws `AgentError.timedOut`
    /// when the timeout elapses before the process exits.
    public func run(_ invocation: ProcessInvocation, agentName: String) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    try continuation.resume(returning: Self.runBlocking(invocation, agentName: agentName))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runBlocking(_ invocation: ProcessInvocation, agentName: String) throws -> ProcessResult {
        let process = Process()
        ProcessLauncher.configure(process, executable: invocation.executable, arguments: invocation.arguments)
        process.currentDirectoryURL = invocation.workingDirectory
        if !invocation.environment.isEmpty {
            process.environment = invocation.environment
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        let inPipe = invocation.stdin != nil ? Pipe() : nil
        process.standardOutput = outPipe
        process.standardError = errPipe
        if let inPipe { process.standardInput = inPipe }

        // Concurrently drain both pipes so the child cannot block on a full buffer.
        let buffers = StreamBuffers()
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            buffers.appendOut(handle.availableData)
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            buffers.appendErr(handle.availableData)
        }

        // Termination handler is installed before run() (ExFig pattern).
        process.terminationHandler = { _ in }

        // Arm the timeout terminator before waiting.
        let timedOut = TimeoutFlag()
        var timer: DispatchSourceTimer?
        if invocation.timeout > 0 {
            let source = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
            source.schedule(deadline: .now() + .seconds(invocation.timeout))
            source.setEventHandler {
                guard process.isRunning else { return }
                timedOut.set()
                process.terminate()
                #if !os(Windows)
                // A child that traps/ignores SIGTERM would hang waitUntilExit
                // forever (defeating the very timeout meant to bound it); escalate
                // to SIGKILL after a short grace period.
                DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(Self.killGraceSeconds)) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
                #endif
            }
            source.resume()
            timer = source
        }

        let start = Date()
        do {
            try process.run()
        } catch {
            throw AgentError.binaryNotFound(agent: agentName, binary: invocation.executable)
        }

        if let stdin = invocation.stdin, let inPipe {
            inPipe.fileHandleForWriting.write(Data(stdin.utf8))
            try? inPipe.fileHandleForWriting.close()
        }

        process.waitUntilExit()
        timer?.cancel()

        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        buffers.appendOut(outPipe.fileHandleForReading.readDataToEndOfFile())
        buffers.appendErr(errPipe.fileHandleForReading.readDataToEndOfFile())

        if timedOut.isSet {
            throw AgentError.timedOut(agent: agentName, seconds: invocation.timeout)
        }

        return ProcessResult(
            status: process.terminationStatus,
            stdout: buffers.outData,
            stderr: buffers.errString,
            duration: Date().timeIntervalSince(start)
        )
    }
}

/// Thread-safe accumulator for the child's stdout/stderr. Reads take the lock too
/// (mirroring `BatonForge`'s `GHRunner.StreamBuffers`) so the final snapshot cannot
/// race a readability handler still draining the pipe.
private final class StreamBuffers: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data()
    private var err = Data()

    func appendOut(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock(); out.append(data); lock.unlock()
    }

    func appendErr(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock(); err.append(data); lock.unlock()
    }

    var outData: Data {
        lock.lock(); defer { lock.unlock() }
        return out
    }

    var errString: String {
        lock.lock(); defer { lock.unlock() }
        return String(bytes: err, encoding: .utf8) ?? ""
    }
}

/// Thread-safe one-shot flag for timeout signalling.
private final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock(); value = true; lock.unlock()
    }

    var isSet: Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}
