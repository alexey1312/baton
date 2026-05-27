/// Output verbosity for CLI commands, derived from flags and the environment.
enum OutputMode: Sendable {
    /// Default mode with spinners and colors (interactive TTY).
    case normal
    /// Detailed output including timestamps and source locations.
    case verbose
    /// Minimal output — warnings and errors only.
    case quiet
    /// Plain text for non-TTY environments (CI, pipes).
    case plain

    /// Whether progress indicators should be shown.
    var showProgress: Bool {
        switch self {
        case .normal, .verbose: true
        case .quiet, .plain: false
        }
    }

    /// Whether animations should be used.
    var useAnimations: Bool { self == .normal }

    /// Whether colors should be used.
    var useColors: Bool {
        switch self {
        case .normal, .verbose: true
        case .quiet, .plain: false
        }
    }

    /// Whether debug-level messages should be shown.
    var showDebug: Bool { self == .verbose }
}
