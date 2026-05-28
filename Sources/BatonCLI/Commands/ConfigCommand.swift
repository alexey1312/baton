import ArgumentParser
import BatonKit
import Foundation

/// `baton config` — print the effective per-scope configuration, optionally with
/// provenance.
struct ConfigCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Print the effective per-scope configuration with provenance."
    )

    @OptionGroup var global: GlobalOptions

    @Option(help: "Repository root to operate on.")
    var repo: String?

    @Flag(help: "Annotate each effective value with the file it came from.")
    var explain = false

    func run() async throws {
        try await present(global.outputMode) {
            let root = try CLISupport.resolveRepoRoot(repo)
            let discovery = try ScopeDiscovery.discover(repoRoot: root)
            for warning in discovery.warnings {
                TerminalOutput.shared.err(NooraUI.warning(warning, useColors: global.outputMode.useColors))
            }

            let scopes = discovery.scopes.sorted { $0.depth < $1.depth }
            var blocks: [String] = []
            for scope in scopes {
                let effective = try Cascade.effective(for: scope, in: discovery.scopes)
                blocks.append(format(effective))
            }
            TerminalOutput.shared.out(blocks.joined(separator: "\n\n"))
        }
    }

    private func format(_ config: EffectiveConfig) -> String {
        let name = config.scopePath.isEmpty ? "(root)" : config.scopePath
        var lines = ["# scope: \(name)"]

        if let agent = config.agent {
            lines.append("[agent]\(provenance("agent", config))")
            lines.append("  kind = \(agent.kind.rawValue)")
            if let model = agent.model { lines.append("  model = \(model)") }
            lines.append("  context = \((agent.context ?? .diff).rawValue)")
        }

        lines.append("[defaults]")
        lines.append("  base = \(config.defaults.base)\(provenance("defaults.base", config))")
        lines.append("  fail_on = \(config.defaults.failOn.rawValue)\(provenance("defaults.fail_on", config))")
        lines
            .append(
                "  max_concurrency = \(config.defaults.maxConcurrency)\(provenance("defaults.max_concurrency", config))"
            )
        lines.append("  diff_budget = \(config.defaults.diffBudget)\(provenance("defaults.diff_budget", config))")
        let chunk = config.defaults.chunkStrategy.rawValue
        lines.append("  chunk_strategy = \(chunk)\(provenance("defaults.chunk_strategy", config))")
        lines.append("  timeout = \(config.defaults.timeout)\(provenance("defaults.timeout", config))")

        if !config.skills.isEmpty {
            lines.append("[[skills]]")
            for skill in config.skills {
                lines.append("  \(skill.name) <- \(skill.source)\(provenance("skills.\(skill.name)", config))")
            }
        }
        if !config.reviews.isEmpty {
            lines.append("[[reviews]]")
            for review in config.reviews {
                lines.append("  \(review.name)\(provenance("reviews.\(review.name)", config))")
            }
        }
        lines.append(contentsOf: formatLearn(config))
        return lines.joined(separator: "\n")
    }

    private func formatLearn(_ config: EffectiveConfig) -> [String] {
        let learn = config.learn
        var lines = ["[learn]"]
        lines.append("  enabled = \(learn.enabled)\(provenance("learn.enabled", config))")
        lines.append("  lookback_days = \(learn.lookbackDays)\(provenance("learn.lookback_days", config))")
        lines.append("  min_signal = \(learn.minSignal)\(provenance("learn.min_signal", config))")
        // Delivery fields are repository-global; show them on the root scope only.
        guard config.scopePath.isEmpty else { return lines }
        lines.append("  branch = \(learn.branch)\(provenance("learn.branch", config))")
        if let base = learn.base { lines.append("  base = \(base)\(provenance("learn.base", config))") }
        lines.append("  draft = \(learn.draft)\(provenance("learn.draft", config))")
        return lines
    }

    private func provenance(_ key: String, _ config: EffectiveConfig) -> String {
        guard explain else { return "" }
        return "  (from \(config.provenance.source(for: key)))"
    }
}
