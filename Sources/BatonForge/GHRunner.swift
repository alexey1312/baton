import BatonKit
import Foundation

/// The captured result of a single `gh` invocation.
public struct GHResult: Sendable, Equatable {
    public var status: Int32
    public var stdout: String
    public var stderr: String

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }

    /// Whether the invocation exited successfully (status 0).
    public var isSuccess: Bool {
        status == 0
    }
}

/// An abstraction over the `gh` CLI so publishing can be unit-tested without the
/// network. Production uses ``LiveGHRunner``; tests use a recording mock.
public protocol GHRunning: Sendable {
    /// Run `gh` with `args`, optionally writing `stdin` to the child's standard input.
    func run(_ args: [String], stdin: String?) async throws -> GHResult
}

public extension GHRunning {
    /// Run `gh` with no stdin.
    func run(_ args: [String]) async throws -> GHResult {
        try await run(args, stdin: nil)
    }
}

/// A ``GHRunning`` backed by the real `gh` executable, invoked via `/usr/bin/env gh`.
///
/// stdout/stderr are drained concurrently so a chatty child cannot deadlock on a
/// full pipe buffer (mirrors `BatonKit`'s `ProcessExecutor`).
public struct LiveGHRunner: GHRunning {
    public init() {}

    /// Whether a `gh` executable is resolvable on `PATH`.
    public static func isInstalled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "gh"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    public func run(_ args: [String], stdin: String?) async throws -> GHResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: Self.runBlocking(args, stdin: stdin))
            }
        }
    }

    private static func runBlocking(_ args: [String], stdin: String?) -> GHResult {
        let process = Process()
        ProcessLauncher.configure(process, executable: "gh", arguments: args)

        let outPipe = Pipe()
        let errPipe = Pipe()
        let inPipe = stdin != nil ? Pipe() : nil
        process.standardOutput = outPipe
        process.standardError = errPipe
        if let inPipe { process.standardInput = inPipe }

        let buffers = StreamBuffers()
        outPipe.fileHandleForReading.readabilityHandler = { buffers.appendOut($0.availableData) }
        errPipe.fileHandleForReading.readabilityHandler = { buffers.appendErr($0.availableData) }

        do {
            try process.run()
        } catch {
            // `gh` could not be launched — surface as a non-zero result so the
            // caller maps it to `ghNotFound` during preflight.
            return GHResult(status: 127, stdout: "", stderr: "failed to launch gh: \(error)")
        }

        if let stdin, let inPipe {
            inPipe.fileHandleForWriting.write(Data(stdin.utf8))
            try? inPipe.fileHandleForWriting.close()
        }

        process.waitUntilExit()
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        buffers.appendOut(outPipe.fileHandleForReading.readDataToEndOfFile())
        buffers.appendErr(errPipe.fileHandleForReading.readDataToEndOfFile())

        return GHResult(
            status: process.terminationStatus,
            stdout: buffers.outString,
            stderr: buffers.errString
        )
    }
}

/// Thread-safe accumulator for the child's stdout/stderr.
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

    var outString: String {
        lock.lock(); defer { lock.unlock() }
        return String(bytes: out, encoding: .utf8) ?? ""
    }

    var errString: String {
        lock.lock(); defer { lock.unlock() }
        return String(bytes: err, encoding: .utf8) ?? ""
    }
}
