/// A supported external coding-CLI agent.
public enum AgentKind: String, Codable, CaseIterable, Sendable {
    case claude
    case codex
    case gemini
    case opencode

    /// Comma-separated list of valid kinds, for use in recovery suggestions.
    public static var listForHelp: String {
        allCases.map(\.rawValue).joined(separator: ", ")
    }
}
