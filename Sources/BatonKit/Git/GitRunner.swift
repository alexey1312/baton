import Foundation

/// Runs `git` subprocesses in a repository and captures their output.
public struct GitRunner: Sendable {
    public let repoRoot: URL
    private let executable: String

    public init(repoRoot: URL, executable: String = "git") {
        self.repoRoot = repoRoot
        self.executable = executable
    }

    /// The captured result of a git invocation.
    public struct Output: Sendable {
        public var status: Int32
        public var stdout: Data
        public var stderr: String

        /// `stdout` decoded as UTF-8.
        public var text: String {
            String(bytes: stdout, encoding: .utf8) ?? ""
        }
    }

    /// Run git with `arguments`, returning the captured output without throwing on
    /// a non-zero exit.
    public func capture(_ arguments: [String]) throws -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.currentDirectoryURL = repoRoot

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            throw GitError.gitUnavailable
        }

        // Drain both pipes before waiting so a large diff cannot deadlock on a full
        // pipe buffer.
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return Output(
            status: process.terminationStatus,
            stdout: outData,
            stderr: String(bytes: errData, encoding: .utf8) ?? ""
        )
    }

    /// Run git, returning stdout text and throwing `GitError.commandFailed` on a
    /// non-zero exit.
    @discardableResult
    public func run(_ arguments: [String]) throws -> String {
        let output = try capture(arguments)
        guard output.status == 0 else {
            throw GitError.commandFailed(
                command: arguments.joined(separator: " "),
                status: output.status,
                stderr: output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return output.text
    }

    /// Whether the current directory is inside a git work tree.
    public func isRepository() -> Bool {
        (try? capture(["rev-parse", "--is-inside-work-tree"]))?.status == 0
    }

    /// Whether a ref/commit exists locally.
    public func refExists(_ ref: String) -> Bool {
        (try? capture(["rev-parse", "--verify", "--quiet", "\(ref)^{commit}"]))?.status == 0
    }

    /// Resolve a ref to its commit SHA.
    public func revParse(_ ref: String) throws -> String {
        try run(["rev-parse", ref]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
