import ArgumentParser
import BatonForge
import BatonKit
import Foundation

/// `baton publish` — publish a saved run to a GitHub PR via the `gh` CLI, using
/// `BatonForge.GitHubForge` (PR review + Check Runs, no LLM re-invocation).
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

    @Flag(
        inversion: .prefixedNo,
        help: "Auto-resolve Baton's own outdated review threads (overrides [publish].resolve_outdated_threads)."
    )
    var resolveOutdatedThreads: Bool?

    func run() async throws {
        try await present(global.outputMode) {
            let root = try CLISupport.resolveRepoRoot(repo)
            let store = RunRecordStore(repoRoot: root)
            let loaded = try store.load(runId: run)
            try await Publisher.publish(
                run: loaded,
                overrides: .init(ghRepo: ghRepo, headSHA: headSHA, pr: pr),
                resolveOutdatedThreads: resolveOutdatedThreadsSetting(root: root),
                outputMode: global.outputMode
            )
        }
    }

    /// The effective auto-resolve setting: an explicit `--[no-]resolve-outdated-threads`
    /// flag wins; otherwise the root `[publish].resolve_outdated_threads`. A config-read
    /// failure falls back to the safe default (off) rather than failing a publish that
    /// operates on an already-saved run.
    private func resolveOutdatedThreadsSetting(root: URL) -> Bool {
        if let resolveOutdatedThreads { return resolveOutdatedThreads }
        guard let discovery = try? ScopeDiscovery.discover(repoRoot: root),
              let rootScope = discovery.scopes.first(where: { $0.path.isEmpty }),
              let effective = try? Cascade.effective(for: rootScope, in: discovery.scopes)
        else { return ConfigDefaults.resolveOutdatedThreads }
        return effective.publish.resolveOutdatedThreads
    }
}
