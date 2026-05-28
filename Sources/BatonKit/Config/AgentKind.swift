/// A supported external coding-CLI agent.
///
/// `custom` is an escape hatch for any other CLI: the user supplies `[agent].binary`
/// and `[agent].args`, and Baton drives it generically (prompt via stdin, findings
/// parsed with the standard parser). Because `binary`/`args` are honored uniformly,
/// no per-CLI adapter is needed for a custom agent.
public enum AgentKind: String, Codable, CaseIterable, Sendable {
    case claude
    case codex
    case gemini
    case opencode
    case custom

    /// The built-in agents that ship a tuned adapter (excludes `custom`).
    public static var builtIn: [AgentKind] {
        [.claude, .codex, .gemini, .opencode]
    }

    /// Comma-separated list of valid kinds, for use in recovery suggestions.
    public static var listForHelp: String {
        allCases.map(\.rawValue).joined(separator: ", ")
    }
}
