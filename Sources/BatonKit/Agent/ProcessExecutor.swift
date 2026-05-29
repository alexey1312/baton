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
    ///
    /// Completion is driven by the process's `terminationHandler` (Foundation's own
    /// `waitpid` monitor), not a blocking `waitUntilExit()` on a GCD worker — so a
    /// parallel fan-out of runs cannot starve the global pool. The timeout
    /// terminator likewise runs on a dedicated OS thread, never the pool.
    public func run(_ invocation: ProcessInvocation, agentName: String) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            Self.launch(invocation, agentName: agentName, continuation: continuation)
        }
    }

    private static func launch(
        _ invocation: ProcessInvocation,
        agentName: String,
        continuation: CheckedContinuation<ProcessResult, Error>
    ) {
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
        outPipe.fileHandleForReading.readabilityHandler = { buffers.appendOut($0.availableData) }
        errPipe.fileHandleForReading.readabilityHandler = { buffers.appendErr($0.availableData) }

        let timedOut = TimeoutFlag()
        let resume = ResumeOnce()
        let exited = DispatchSemaphore(value: 0)
        let start = Date()

        process.terminationHandler = { proc in
            exited.signal() // wake the terminator so it neither kills nor lingers
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            buffers.appendOut(outPipe.fileHandleForReading.readDataToEndOfFile())
            buffers.appendErr(errPipe.fileHandleForReading.readDataToEndOfFile())
            guard resume.tryResume() else { return }
            if timedOut.isSet {
                continuation.resume(throwing: AgentError.timedOut(agent: agentName, seconds: invocation.timeout))
            } else {
                continuation.resume(returning: ProcessResult(
                    status: proc.terminationStatus,
                    stdout: buffers.outData,
                    stderr: buffers.errString,
                    duration: Date().timeIntervalSince(start)
                ))
            }
        }

        do {
            try process.run()
        } catch {
            exited.signal()
            if resume.tryResume() {
                continuation.resume(throwing: AgentError.binaryNotFound(
                    agent: agentName,
                    binary: invocation.executable
                ))
            }
            return
        }

        if let stdin = invocation.stdin, let inPipe {
            inPipe.fileHandleForWriting.write(Data(stdin.utf8))
            try? inPipe.fileHandleForWriting.close()
        }

        armTimeout(process, seconds: invocation.timeout, flag: timedOut, exited: exited)
    }

    /// Arm a one-shot terminator on a dedicated OS thread: it waits on `exited` until
    /// the deadline, then flags the timeout and SIGTERMs the process, escalating to
    /// SIGKILL after a grace period (POSIX) so a child that ignores SIGTERM cannot
    /// linger. A real thread (not a GCD queue, which shares the starvable global
    /// pool) guarantees the terminator fires on time even under heavy fan-out.
    private static func armTimeout(_ process: Process, seconds: Int, flag: TimeoutFlag, exited: DispatchSemaphore) {
        guard seconds > 0 else { return }
        let thread = Thread {
            if exited.wait(timeout: .now() + .seconds(seconds)) == .success { return } // exited in time
            guard process.isRunning else { return }
            flag.set()
            process.terminate()
            #if !os(Windows)
            if exited.wait(timeout: .now() + .seconds(killGraceSeconds)) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            #endif
        }
        thread.stackSize = 256 << 10
        thread.start()
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

/// Guards a `CheckedContinuation` against a double resume: the termination handler
/// and the launch-failure path both try to resume, but exactly one must win.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func tryResume() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if resumed { return false }
        resumed = true
        return true
    }
}
