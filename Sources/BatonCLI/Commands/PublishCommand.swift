import ArgumentParser
import BatonKit
import Foundation

/// `baton publish` — publish a saved run to a GitHub PR via the `gh` CLI.
///
/// Wired to `BatonForge.GitHubForge` once that capability lands; the command shell
/// here resolves the run and publish context and performs the `gh` preflight.
struct PublishCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "publish",
        abstract: "Publish a saved run to a GitHub pull request."
    )

    @OptionGroup var global: GlobalOptions

    @Option(help: "Run to publish: an id or `latest` (default).")
    var run: String?

    @Option(name: .customLong("head-sha"), help: "Head commit SHA to publish against.")
    var headSHA: String?

    @Option(name: .customLong("gh-repo"), help: "Target repository slug (owner/repo).")
    var ghRepo: String?

    @Option(help: "Pull-request number to publish to.")
    var pr: Int?

    @Option(help: "Repository root to operate on.")
    var repo: String?

    func run() async throws {
        try await present(global.outputMode) {
            let root = try CLISupport.resolveRepoRoot(repo)
            let store = RunRecordStore(repoRoot: root)
            let loaded = try store.load(runId: run)
            try await Publisher.publish(
                run: loaded,
                overrides: .init(ghRepo: ghRepo, headSHA: headSHA, pr: pr),
                outputMode: global.outputMode
            )
        }
    }
}
