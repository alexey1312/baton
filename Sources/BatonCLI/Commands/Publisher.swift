import BatonKit
import Foundation

/// Bridges the `publish` command to GitHub. Performs the `gh` preflight and resolves
/// the publish context; the actual posting is delegated to `BatonForge.GitHubForge`
/// once wired (tracked for the github-publish integration step).
enum Publisher {
    struct Overrides {
        var ghRepo: String?
        var headSHA: String?
        var pr: Int?
    }

    enum PublishError: BatonError {
        case ghNotFound
        case ghUnauthenticated
        case contextUnresolved

        var errorDescription: String? {
            switch self {
            case .ghNotFound: "The gh CLI was not found in PATH"
            case .ghUnauthenticated: "The gh CLI is not authenticated"
            case .contextUnresolved: "Could not resolve the repository and head SHA to publish against"
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .ghNotFound: "Install the GitHub CLI: https://cli.github.com"
            case .ghUnauthenticated: "Run `gh auth login` or set GH_TOKEN."
            case .contextUnresolved: "Pass --gh-repo owner/repo and --head-sha <sha>."
            }
        }
    }

    static func publish(run: LoadedRun, overrides: Overrides, outputMode: OutputMode) async throws {
        try preflight()

        let env = GitHubEnv.detect()
        let repo = overrides.ghRepo ?? env?.repository
        let headSHA = overrides.headSHA ?? env?.headSHA ?? run.manifest.headSHA
        guard let repo, !headSHA.isEmpty else {
            throw PublishError.contextUnresolved
        }
        let prNumber = overrides.pr ?? env?.prNumber

        // Render the GitHub-shaped output the forge will post. Full posting via
        // GitHubForge (PR review + Check Runs + dedupe) is wired in the
        // github-publish integration step.
        let findings = run.results.flatMap(\.findings)
        let target = prNumber.map { "PR #\($0)" } ?? "Check Runs on \(headSHA.prefix(8))"
        TerminalOutput.shared.out(NooraUI.info(
            "Prepared \(findings.count) finding(s) for \(repo) (\(target)).",
            useColors: outputMode.useColors
        ))
        let summary = (try? Renderer.render(run: run, format: .githubSummary, headSHA: nil)) ?? ""
        TerminalOutput.shared.out(summary)
    }

    /// Verify the `gh` CLI is present and authenticated.
    static func preflight() throws {
        guard AgentToolPreflight.isAvailable("gh") else { throw PublishError.ghNotFound }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh", "auth", "status"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 { throw PublishError.ghUnauthenticated }
        } catch let error as PublishError {
            throw error
        } catch {
            throw PublishError.ghUnauthenticated
        }
    }
}
