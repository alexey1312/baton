import ArgumentParser

/// Options shared by every `baton` subcommand.
///
/// Declared as an `@OptionGroup` on both the root command and each subcommand so
/// that `baton --verbose review` and `baton review --verbose` are both accepted.
struct GlobalOptions: ParsableArguments {
    @Flag(name: [.long, .short], help: "Raise logging and output verbosity.")
    var verbose = false

    @Flag(name: .long, help: "Suppress non-essential progress and informational output.")
    var quiet = false

    /// The output mode resolved from these flags and the environment.
    var outputMode: OutputMode {
        TTYDetector.effectiveMode(verbose: verbose, quiet: quiet)
    }
}
