import Foundation

/// Runs a single ``ProcessInvocation``, draining stdout/stderr concurrently so a
/// chatty agent cannot deadlock on a full pipe buffer, installing the termination
/// handler before starting the process, and enforcing a per-invocation timeout.
///
/// Ported from ExFig's subprocess runner pattern.
public struct ProcessExecutor: Sendable {
    /// Grace period after SIGTERM before escalating to SIGKILL on a child that traps,
    /// ignores, or never receives SIGTERM (POSIX only — `terminate()` is already
    /// forceful on Windows). Kept short: on swift-corelibs-foundation/Linux SIGTERM
    /// via `terminate()` does not reliably reach a `/usr/bin/env`-wrapped child, so the
    /// uncatchable `kill(pid, SIGKILL)` is what actually enforces the deadline — it
    /// must fire well before any long-running child would exit on its own.
    private static let killGraceSeconds = 1

    public init() {}

    /// Run `invocation`, returning the captured result. Throws `AgentError.timedOut`
    /// when the timeout elapses before the process exits.
    ///
    /// The blocking work runs on a dedicated OS thread, not `DispatchQueue.global()`:
    /// `waitUntilExit()` blocks its thread, and a parallel fan-out on the shared GCD
    /// pool would starve both that wait and the timeout terminator. A real thread is
    /// independent of the pool. (`terminationHandler` would avoid blocking entirely
    /// but is unreliable on swift-corelibs-foundation/Linux, so we keep the portable
    /// `waitUntilExit()`.)
    public func run(_ invocation: ProcessInvocation, agentName: String) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let thread = Thread {
                do {
                    try continuation.resume(returning: Self.runBlocking(invocation, agentName: agentName))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            thread.stackSize = 1 << 20
            thread.start()
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
        outPipe.fileHandleForReading.readabilityHandler = { buffers.appendOut($0.availableData) }
        errPipe.fileHandleForReading.readabilityHandler = { buffers.appendErr($0.availableData) }

        // Termination handler is installed before run() (ExFig pattern).
        process.terminationHandler = { _ in }

        let timedOut = TimeoutFlag()
        let exited = DispatchSemaphore(value: 0)
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

        // Arm the terminator before blocking, then release it once the child exits.
        armTimeout(process, seconds: invocation.timeout, flag: timedOut, exited: exited)
        process.waitUntilExit()
        exited.signal()

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
