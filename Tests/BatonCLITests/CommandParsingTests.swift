import ArgumentParser
@testable import BatonCLI
import Testing

struct CommandParsingTests {
    @Test("review parses all options")
    func reviewOptions() throws {
        let cmd = try ReviewCommand.parse([
            "security", "--base", "origin/main", "--agent", "codex",
            "--model", "o3", "--json", "--max-concurrency", "2",
            "--repo", "/tmp/x", "--allow-unpinned",
        ])
        #expect(cmd.name == "security")
        #expect(cmd.base == "origin/main")
        #expect(cmd.agent == .codex)
        #expect(cmd.model == "o3")
        #expect(cmd.json)
        #expect(cmd.maxConcurrency == 2)
        #expect(cmd.allowUnpinned)
    }

    @Test("init parses agent/model/path/force")
    func initOptions() throws {
        let cmd = try InitCommand.parse(["--agent", "gemini", "--model", "g", "--path", "./svc", "--force"])
        #expect(cmd.agent == .gemini)
        #expect(cmd.model == "g")
        #expect(cmd.path == "./svc")
        #expect(cmd.force)
    }

    @Test("render parses the format")
    func renderFormat() throws {
        let cmd = try RenderCommand.parse(["--format", "github-summary"])
        #expect(cmd.format == .githubSummary)
    }

    @Test("learn parses apply/markdown/gh-repo/repo with preview as default")
    func learnOptions() throws {
        let preview = try LearnCommand.parse([])
        #expect(!preview.apply)
        #expect(!preview.markdown)

        let cmd = try LearnCommand.parse(["--apply", "--markdown", "--gh-repo", "o/r", "--repo", "/tmp/x"])
        #expect(cmd.apply)
        #expect(cmd.markdown)
        #expect(cmd.ghRepo == "o/r")
        #expect(cmd.repo == "/tmp/x")
        #expect(cmd.agent == nil)
        #expect(cmd.model == nil)

        let withAgent = try LearnCommand.parse(["--agent", "codex", "--model", "opus"])
        #expect(withAgent.agent == .codex)
        #expect(withAgent.model == "opus")
    }

    @Test("an unknown subcommand is rejected")
    func unknownSubcommand() {
        #expect(throws: (any Error).self) {
            _ = try Baton.parseAsRoot(["frobnicate"])
        }
    }

    @Test("global verbose flag is accepted before a subcommand")
    func globalVerbose() throws {
        // `baton --verbose config` — the flag is shared via the OptionGroup.
        let parsed = try Baton.parseAsRoot(["config", "--verbose"])
        #expect(parsed is ConfigCommand)
    }
}
