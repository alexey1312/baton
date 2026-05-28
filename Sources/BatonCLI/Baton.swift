import ArgumentParser

/// The `baton` command-line interface.
///
/// Orchestrates AI code review across a monorepo: discover scopes, cascade
/// configuration, route the diff, run agents, and publish findings to GitHub.
@main
struct Baton: AsyncParsableCommand {
    /// Build-time version, overwritten by the release pipeline.
    static let version = "0.0.0-dev"

    static let configuration = CommandConfiguration(
        commandName: "baton",
        abstract: "Monorepo AI code-review orchestrator.",
        version: version,
        subcommands: [
            InitCommand.self,
            ReviewCommand.self,
            ConfigCommand.self,
            RenderCommand.self,
            PublishCommand.self,
            DoctorCommand.self,
            StatsCommand.self,
            HistoryCommand.self,
            ShowCommand.self,
        ]
    )

    @OptionGroup var global: GlobalOptions
}
