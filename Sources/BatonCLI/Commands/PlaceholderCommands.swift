import ArgumentParser

// Phase-1 command skeletons. Each is fleshed out in its capability phase
// (cli / review-orchestration / rendering / github-publish). They exist now so the
// command tree and `--help` are wired and testable.

struct InitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Write a starter baton.toml."
    )

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        throw CleanExit.message("`baton init` is not implemented yet.")
    }
}

struct ReviewCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "review",
        abstract: "Run configured reviews over the resolved diff."
    )

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        throw CleanExit.message("`baton review` is not implemented yet.")
    }
}

struct ConfigCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Print the effective per-scope configuration with provenance."
    )

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        throw CleanExit.message("`baton config` is not implemented yet.")
    }
}

struct RenderCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "render",
        abstract: "Render a saved run in a chosen format."
    )

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        throw CleanExit.message("`baton render` is not implemented yet.")
    }
}

struct PublishCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "publish",
        abstract: "Publish a saved run to a GitHub pull request."
    )

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        throw CleanExit.message("`baton publish` is not implemented yet.")
    }
}

struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check required external tools and report their status."
    )

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        throw CleanExit.message("`baton doctor` is not implemented yet.")
    }
}
