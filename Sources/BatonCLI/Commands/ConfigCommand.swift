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
            lines.append("  sandbox = \(agent.sandbox ?? ConfigDefaults.sandbox)")
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
                var line = "  \(review.name)\(provenance("reviews.\(review.name)", config))"
                if let agent = review.agent {
                    let model = agent.model.map { "/\($0)" } ?? ""
                    line += "  [agent: \(agent.kind.rawValue)\(model)]"
                }
                lines.append(line)
            }
        }
        lines.append(contentsOf: formatLearn(config))
        lines.append(contentsOf: formatPublish(config))
        lines.append(contentsOf: formatRender(config))
        return lines.joined(separator: "\n")
    }

    private func formatPublish(_ config: EffectiveConfig) -> [String] {
        // Publish settings are repository-global; show them on the root scope only.
        guard config.scopePath.isEmpty else { return [] }
        let value = config.publish.resolveOutdatedThreads
        return [
            "[publish]",
            "  resolve_outdated_threads = \(value)\(provenance("publish.resolve_outdated_threads", config))",
        ]
    }

    private func formatRender(_ config: EffectiveConfig) -> [String] {
        // Render templates are repository-global and optional; show only when set.
        guard config.scopePath.isEmpty else { return [] }
        var lines: [String] = []
        if let md = config.render.markdownTemplate {
            lines.append("  markdown_template = \(md)\(provenance("render.markdown_template", config))")
        }
        if let learn = config.render.learnPrBodyTemplate {
            lines.append("  learn_pr_body_template = \(learn)\(provenance("render.learn_pr_body_template", config))")
        }
        return lines.isEmpty ? [] : ["[render]"] + lines
    }

    private func formatLearn(_ config: EffectiveConfig) -> [String] {
        let learn = config.learn
        var lines = ["[learn]"]
        lines.append("  enabled = \(learn.enabled)\(provenance("learn.enabled", config))")
        lines.append("  lookback_days = \(learn.lookbackDays)\(provenance("learn.lookback_days", config))")
        lines.append("  min_signal = \(learn.minSignal)\(provenance("learn.min_signal", config))")
        let car = learn.countAuthorReactions
        lines.append("  count_author_reactions = \(car)\(provenance("learn.count_author_reactions", config))")
        // Agent/model overrides are optional; show them only when set.
        if let agent = learn.agent {
            lines.append("  agent = \(agent.rawValue)\(provenance("learn.agent", config))")
        }
        if let model = learn.model {
            lines.append("  model = \(model)\(provenance("learn.model", config))")
        }
        // Delivery fields are repository-global; show them on the root scope only.
        guard config.scopePath.isEmpty else { return lines }
        lines.append("  branch = \(learn.branch)\(provenance("learn.branch", config))")
        if let base = learn.base { lines.append("  base = \(base)\(provenance("learn.base", config))") }
        lines.append("  draft = \(learn.draft)\(provenance("learn.draft", config))")
        if !learn.reviewers.isEmpty {
            let value = learn.reviewers.joined(separator: ", ")
            lines.append("  reviewers = \(value)\(provenance("learn.reviewers", config))")
        }
        if !learn.teamReviewers.isEmpty {
            let value = learn.teamReviewers.joined(separator: ", ")
            lines.append("  team_reviewers = \(value)\(provenance("learn.team_reviewers", config))")
        }
        if !learn.labels.isEmpty {
            let value = learn.labels.joined(separator: ", ")
            lines.append("  labels = \(value)\(provenance("learn.labels", config))")
        }
        return lines
    }

    private func provenance(_ key: String, _ config: EffectiveConfig) -> String {
        guard explain else { return "" }
        return "  (from \(config.provenance.source(for: key)))"
    }
}
