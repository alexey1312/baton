import Foundation

/// Errors raised while running `git` or interpreting its output.
public enum GitError: BatonError {
    /// `git` is not available on `PATH`.
    case gitUnavailable
    /// The working directory is not a git repository.
    case notARepository(path: String)
    /// The resolved base ref is not present locally.
    case invalidBaseRef(ref: String)
    /// A `git` invocation exited non-zero.
    case commandFailed(command: String, status: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .gitUnavailable:
            "git was not found on PATH"
        case let .notARepository(path):
            "\(path) is not a git repository"
        case let .invalidBaseRef(ref):
            "base ref '\(ref)' is not present in the local repository"
        case let .commandFailed(command, status, stderr):
            "git \(command) exited \(status): \(stderr)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .gitUnavailable:
            "Install git and ensure it is on your PATH."
        case .notARepository:
            "Run inside a git repository, or pass --repo pointing at one."
        case let .invalidBaseRef(ref):
            "Fetch the base ref first, e.g. `git fetch origin \(ref.replacingOccurrences(of: "origin/", with: ""))`."
        case .commandFailed:
            "Check the git output above and your repository state."
        }
    }
}
