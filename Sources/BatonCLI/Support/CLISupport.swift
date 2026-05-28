import ArgumentParser
import BatonKit
import Foundation

/// Errors raised by the CLI layer itself (not a capability).
enum CLIError: BatonError {
    case repoNotFound(path: String)
    case notAGitRepository(path: String)
    case namedReviewMissing(name: String, available: [String])
    case noRunsRecorded
    case invalidDate(value: String)

    var errorDescription: String? {
        switch self {
        case let .repoNotFound(path):
            "Repository path does not exist: \(path)"
        case let .notAGitRepository(path):
            "Not a git repository: \(path)"
        case let .namedReviewMissing(name, _):
            "No review named '\(name)' is defined in any scope"
        case .noRunsRecorded:
            "No runs are recorded for this repository yet"
        case let .invalidDate(value):
            "Invalid date: '\(value)'"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .repoNotFound:
            "Pass --repo pointing at an existing directory."
        case .notAGitRepository:
            "Run inside a git repository, or pass --repo pointing at one."
        case let .namedReviewMissing(_, available):
            available.isEmpty
                ? "Define a [[reviews]] entry in a baton.toml."
                : "Available reviews: \(available.joined(separator: ", "))."
        case .noRunsRecorded:
            "Run `baton review` first, or pass --all-repos to look across every repo."
        case .invalidDate:
            "Use ISO-8601 yyyy-MM-dd format, e.g. 2026-05-28."
        }
    }
}

enum CLISupport {
    /// Resolve and validate the repository root from `--repo` or the current directory.
    static func resolveRepoRoot(_ repoOption: String?) throws -> URL {
        let path = repoOption ?? FileManager.default.currentDirectoryPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            throw CLIError.repoNotFound(path: path)
        }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard GitRunner(repoRoot: url).isRepository() else {
            throw CLIError.notAGitRepository(path: path)
        }
        return url
    }
}

extension AsyncParsableCommand {
    /// Run `body`, presenting any thrown error as `✗/→` on stderr and exiting
    /// non-zero. `ExitCode` is rethrown unchanged so success/failure codes propagate.
    func present(_ outputMode: OutputMode, _ body: () async throws -> Void) async throws {
        do {
            try await body()
        } catch let exit as ExitCode {
            throw exit
        } catch {
            TerminalOutput.shared.err(ErrorPresenter.present(error, useColors: outputMode.useColors))
            throw ExitCode.failure
        }
    }
}
