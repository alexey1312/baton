import Foundation

/// Detects terminal capabilities and the surrounding environment.
enum TTYDetector {
    /// Whether stdout is connected to a TTY.
    static var isTTY: Bool {
        isatty(STDOUT_FILENO) == 1
    }

    /// Current terminal width in columns, defaulting to 80.
    static var terminalWidth: Int {
        #if os(macOS) || os(Linux)
        var size = winsize()
        if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &size) == 0, size.ws_col > 0 {
            return Int(size.ws_col)
        }
        #endif
        return 80
    }

    /// Whether `FORCE_COLOR` is set.
    static var forceColor: Bool {
        ProcessInfo.processInfo.environment["FORCE_COLOR"] != nil
    }

    /// Whether `NO_COLOR` is set.
    static var noColor: Bool {
        ProcessInfo.processInfo.environment["NO_COLOR"] != nil
    }

    /// Whether a known CI environment variable is set.
    static var isCI: Bool {
        let vars = ["CI", "CONTINUOUS_INTEGRATION", "GITHUB_ACTIONS", "GITLAB_CI", "JENKINS_URL"]
        return vars.contains { ProcessInfo.processInfo.environment[$0] != nil }
    }

    /// Resolves the effective output mode from the global flags and environment.
    ///
    /// `FORCE_COLOR` keeps the colored interactive mode even when piped or in CI;
    /// `NO_COLOR` (no-color.org) joins the existing no-color triggers. Explicit
    /// `--quiet`/`--verbose` still take precedence for verbosity.
    static func effectiveMode(verbose: Bool, quiet: Bool) -> OutputMode {
        if quiet { return .quiet }
        if verbose { return .verbose }
        if forceColor { return .normal }
        if noColor || !isTTY || isCI { return .plain }
        return .normal
    }
}
