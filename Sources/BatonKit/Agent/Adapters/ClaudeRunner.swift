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
    /// `--strict-mcp-config` ignores every MCP source except an explicit
    /// `--mcp-config` (which Baton never passes), so no global MCP server loads
    /// or prompts for auth.
    public let sandboxArguments = ["--strict-mcp-config"]

    public init() {}

    /// Claude's JSON envelope: `result` carries the model text, `usage` and
    /// `total_cost_usd` carry token/cost accounting we surface in stats.
    private struct Usage: Decodable {
        var input_tokens: Int?
        var output_tokens: Int?
        var cache_creation_input_tokens: Int?
        var cache_read_input_tokens: Int?
    }

    private struct Envelope: Decodable {
        var result: String?
        var total_cost_usd: Double?
        var usage: Usage?
    }

    public func parse(_ output: AgentOutput) throws -> ParsedFindings {
        guard let data = output.stdout.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
        else {
            return try FindingsParser.parse(output.stdout)
        }

        let inner = envelope.result ?? output.stdout
        var parsed = try FindingsParser.parse(inner)
        parsed.usage = Self.makeUsage(from: envelope, model: output.model)
        return parsed
    }

    /// Convert Claude's envelope into an ``AgentUsage``. Cache token counts
    /// are folded into `inputTokens` because they bill at input rates. If the
    /// envelope omits cost but we have tokens and a known model, fall back to
    /// the price table.
    private static func makeUsage(from envelope: Envelope, model: String?) -> AgentUsage? {
        let usage = envelope.usage
        var cost = envelope.total_cost_usd
        let input = sum(usage?.input_tokens, usage?.cache_creation_input_tokens, usage?.cache_read_input_tokens)
        let output = usage?.output_tokens
        if input == nil, output == nil, cost == nil {
            return nil
        }
        var source: AgentUsage.Source = .agentEnvelope
        if cost == nil {
            if let estimated = Pricing.estimateCost(model: model, inputTokens: input, outputTokens: output) {
                cost = estimated
                source = .priceTable
            }
        }
        return AgentUsage(
            inputTokens: input,
            outputTokens: output,
            totalCostUSD: cost,
            source: source
        )
    }

    private static func sum(_ values: Int?...) -> Int? {
        let present = values.compactMap(\.self)
        return present.isEmpty ? nil : present.reduce(0, +)
    }
}
