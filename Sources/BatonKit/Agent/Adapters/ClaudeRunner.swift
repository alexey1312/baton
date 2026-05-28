import Foundation

/// Adapter for the Claude Code CLI.
///
/// Headless flags pinned from how blick drives `claude`. `--output-format json`
/// wraps the model's text in a result envelope, so `parse` unwraps it before
/// extracting findings.
///
/// Security note — `--dangerously-skip-permissions`: required for non-interactive
/// operation (without it the CLI blocks on interactive permission prompts and the
/// headless run hangs). The risk is bounded by Baton's isolation model (see
/// ``Isolation`` and design Decision/Improvement #1): the agent runs in a fresh
/// temporary working directory — never the real repository tree — so it cannot
/// modify the working tree; `context = "repo"` provides a *copy*, not the live
/// tree; `--max-turns 1` caps it to a single turn; and the untrusted-skill defense
/// is the delimited prompt block, not tool permissions. A true OS sandbox and
/// egress allowlist are deferred (documented in design Risks).
public struct ClaudeRunner: AgentRunner {
    public let kind: AgentKind = .claude
    public let defaultBinary = "claude"
    public let baseArguments = [
        "--print",
        "--output-format", "json",
        "--max-turns", "1",
        "--dangerously-skip-permissions",
    ]

    public init() {}

    public func parse(_ output: AgentOutput) throws -> ParsedFindings {
        struct Envelope: Decodable { var result: String? }
        if let data = output.stdout.data(using: .utf8),
           let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
           let inner = envelope.result
        {
            return try FindingsParser.parse(inner)
        }
        return try FindingsParser.parse(output.stdout)
    }
}
