import ArgumentParser
import BatonKit
import Foundation

/// `baton learn` — a periodic reflection pass that reads 👍/👎 + thread-resolution
/// signal from merged PRs and proposes edits to the review setup as a single
/// rolling draft PR. Safe-by-default: preview unless delivery is configured or
/// `--apply` is passed.
struct LearnCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "learn",
        abstract: "Propose review-setup edits from recent review signal (preview by default)."
    )

    @OptionGroup var global: GlobalOptions

    @Flag(help: "Open or update the rolling draft pull request instead of only previewing.")
    var apply = false

    @Flag(help: "Emit the proposal as markdown (the rolling PR body) instead of terminal text.")
    var markdown = false

    @Option(help: "Override the agent kind for the learning pass (\(AgentKind.listForHelp)).")
    var agent: AgentKind?

    @Option(help: "Override the agent model for the learning pass.")
    var model: String?

    @Option(name: .customLong("gh-repo"), help: "Target repository slug (owner/repo).")
    var ghRepo: String?

    @Option(help: "Repository root to operate on.")
    var repo: String?

    func run() async throws {
        try await present(global.outputMode) {
            let root = try CLISupport.resolveRepoRoot(repo)
            try await LearnCoordinator.run(LearnCoordinator.Options(
                repoRoot: root,
                ghRepo: ghRepo,
                apply: apply,
                markdown: markdown,
                agent: agent,
                model: model,
                outputMode: global.outputMode
            ))
        }
    }
}
