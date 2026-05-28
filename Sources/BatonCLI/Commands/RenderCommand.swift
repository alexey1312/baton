import ArgumentParser
import BatonKit
import Foundation

/// `baton render --format <fmt>` — render a saved run without re-invoking the agent.
struct RenderCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "render",
        abstract: "Render a saved run in a chosen format."
    )

    @OptionGroup var global: GlobalOptions

    @Option(help: "Output format: \(RenderFormat.allCases.map(\.rawValue).joined(separator: ", ")).")
    var format: RenderFormat = .terminal

    @Option(help: "Run to render: an id, `latest`, or `latest` by default.")
    var run: String?

    @Option(name: .customLong("head-sha"), help: "Head commit SHA for github-anchored formats.")
    var headSHA: String?

    @Option(help: "Repository root to operate on.")
    var repo: String?

    func run() async throws {
        try await present(global.outputMode) {
            let root = try CLISupport.resolveRepoRoot(repo)
            let store = RunRecordStore(repoRoot: root)
            let loaded = try store.load(runId: run)
            let sha = headSHA ?? GitHubEnv.detect()?.headSHA
            let output = try Renderer.render(
                run: loaded,
                format: format,
                headSHA: sha,
                useColors: global.outputMode.useColors
            )
            TerminalOutput.shared.out(output)
        }
    }
}
