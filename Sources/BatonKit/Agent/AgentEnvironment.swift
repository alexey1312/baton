import Foundation

/// Builds the environment handed to a spawned agent CLI.
///
/// The agent inherits the parent environment so it can reach its model provider
/// (e.g. `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`) and find tools on `PATH` — but
/// Baton's GitHub credentials are scrubbed first. The agent never needs them, and
/// because egress is not blocked and the agent processes untrusted skill/diff/
/// signal content, leaving a GitHub write token in the child's environment is an
/// unnecessary exfiltration surface. `gh` itself still inherits the token: it is
/// launched directly (``LiveGHRunner``), not as an agent.
public enum AgentEnvironment {
    /// GitHub credentials Baton uses for `gh`; an agent CLI has no use for them.
    static let scrubbedKeys: Set<String> = [
        "GITHUB_TOKEN", "GH_TOKEN", "GH_ENTERPRISE_TOKEN",
    ]

    /// The parent environment with GitHub credentials removed.
    public static func scrubbed(
        from environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        environment.filter { !scrubbedKeys.contains($0.key) }
    }
}
