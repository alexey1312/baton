import Foundation

/// Adapter for the Claude Code CLI.
///
/// Headless flags pinned from how blick drives `claude`. `--output-format json`
/// wraps the model's text in a result envelope, so `parse` unwraps it before
/// extracting findings.
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
