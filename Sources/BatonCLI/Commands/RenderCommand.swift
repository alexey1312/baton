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

    @Option(name: .customLong("template"), help: "Jinja template for the markdown format (overrides [render]).")
    var template: String?

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
                useColors: global.outputMode.useColors,
                markdownTemplate: markdownTemplateOverride(root: root)
            )
            TerminalOutput.shared.out(output)
        }
    }

    /// The markdown template override: an explicit `--template` (rejected for any
    /// non-markdown format) wins over the root `[render].markdown_template`. Returns
    /// `nil` to use the bundled default.
    private func markdownTemplateOverride(root: URL) throws -> Renderer.Template? {
        if let template {
            guard format.supportsTemplate else { throw RenderError.templateNotSupported(format: format.rawValue) }
            return try ReportTemplating.userTemplate(path: template, configDir: root)
        }
        guard format.supportsTemplate, let configured = effectiveRender(root: root)?.markdownTemplate else {
            return nil
        }
        return try ReportTemplating.userTemplate(path: configured, configDir: root)
    }

    /// The root scope's effective `[render]` block, or nil if config can't be read.
    private func effectiveRender(root: URL) -> EffectiveRender? {
        guard let discovery = try? ScopeDiscovery.discover(repoRoot: root),
              let rootScope = discovery.scopes.first(where: { $0.path.isEmpty }),
              let effective = try? Cascade.effective(for: rootScope, in: discovery.scopes)
        else { return nil }
        return effective.render
    }
}
