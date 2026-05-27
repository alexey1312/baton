import ArgumentParser
@testable import BatonCLI
import Testing

struct OutputModeTests {
    @Test("quiet takes precedence over verbose")
    func quietWins() {
        #expect(TTYDetector.effectiveMode(verbose: true, quiet: true) == .quiet)
    }

    @Test("verbose mode enables debug output")
    func verboseShowsDebug() {
        #expect(OutputMode.verbose.showDebug)
        #expect(!OutputMode.plain.showDebug)
    }

    @Test("root command lists every subcommand")
    func subcommands() {
        let names = Baton.configuration.subcommands.map { $0.configuration.commandName ?? "" }
        #expect(Set(names) == ["init", "review", "config", "render", "publish", "doctor"])
    }
}
