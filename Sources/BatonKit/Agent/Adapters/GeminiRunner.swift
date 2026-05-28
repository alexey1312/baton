import Foundation

/// Adapter for the Gemini CLI (non-interactive, auto-approve).
///
/// `--output-format json` makes the CLI emit a stable `{session_id, response,
/// stats}` envelope where `response` carries the model text (often itself a
/// ```` ```json ```` block). `parse` unwraps that envelope before extracting
/// findings, the same way ``ClaudeRunner`` unwraps Claude's `result` field.
public struct GeminiRunner: AgentRunner {
    public let kind: AgentKind = .gemini
    public let defaultBinary = "gemini"
    public let baseArguments = ["--approval-mode=yolo", "--skip-trust", "--output-format", "json"]
    /// Gemini has no flag to disable MCP outright (servers come from
    /// `~/.gemini/settings.json`, not extensions) and an empty allowlist is
    /// rejected. Restricting the allowlist to a sentinel name no real server
    /// matches disables them all — which also avoids the MCP-discovery hangs.
    public let sandboxArguments = ["--allowed-mcp-server-names", "baton-sandbox-no-mcp"]

    public init() {}

    /// Gemini's `--output-format json` envelope. `response` holds the model text.
    private struct Envelope: Decodable {
        var response: String?
    }

    public func parse(_ output: AgentOutput) throws -> ParsedFindings {
        let inner = Self.unwrap(output.stdout)
        var parsed = try FindingsParser.parse(inner)
        parsed.usage = UsageExtractor.extract(stdout: output.stdout, model: output.model)
        return parsed
    }

    /// Return the envelope's `response` text, or the raw stdout when the output
    /// is not a recognizable envelope (so plain JSON output still parses).
    private static func unwrap(_ stdout: String) -> String {
        guard let data = stdout.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              let response = envelope.response
        else {
            return stdout
        }
        return response
    }
}
