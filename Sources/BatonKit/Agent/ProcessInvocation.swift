import Foundation

/// How the assembled prompt is delivered to the agent process.
public enum PromptDelivery: Sendable, Equatable {
    /// Written to the process's standard input (default; avoids `ARG_MAX`).
    case stdin
    /// Appended as a trailing positional argument.
    case argument
    /// Written to a temp file whose path is passed as an argument.
    case tempFile
}

/// A fully-built, ready-to-run agent process invocation.
public struct ProcessInvocation: Sendable, Equatable {
    public var executable: String
    public var arguments: [String]
    /// Text to write to stdin, or `nil` when the prompt is delivered another way.
    public var stdin: String?
    public var workingDirectory: URL
    public var environment: [String: String]
    /// Seconds before the process is terminated (`<= 0` disables the timeout).
    public var timeout: Int

    public init(
        executable: String,
        arguments: [String],
        stdin: String?,
        workingDirectory: URL,
        environment: [String: String] = [:],
        timeout: Int
    ) {
        self.executable = executable
        self.arguments = arguments
        self.stdin = stdin
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.timeout = timeout
    }
}

/// The captured result of running a ``ProcessInvocation``.
public struct ProcessResult: Sendable {
    public var status: Int32
    public var stdout: Data
    public var stderr: String
    public var duration: TimeInterval

    public var stdoutText: String {
        String(bytes: stdout, encoding: .utf8) ?? ""
    }

    /// The last `maxLines` lines of stderr, for compact error messages.
    public func stderrTail(maxLines: Int = 10) -> String {
        let lines = stderr.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(maxLines).joined(separator: "\n")
    }
}
