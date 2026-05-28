import Foundation

/// Per-million-token prices for known models, in USD.
public struct ModelPrice: Sendable, Equatable {
    public let inputPerMTok: Double
    public let outputPerMTok: Double

    public init(inputPerMTok: Double, outputPerMTok: Double) {
        self.inputPerMTok = inputPerMTok
        self.outputPerMTok = outputPerMTok
    }

    /// Cost in USD for the given token counts.
    public func cost(inputTokens: Int, outputTokens: Int) -> Double {
        let inputCost = Double(inputTokens) / 1_000_000.0 * inputPerMTok
        let outputCost = Double(outputTokens) / 1_000_000.0 * outputPerMTok
        return inputCost + outputCost
    }
}

/// Static price table for the most common coding-CLI models. The keys match
/// the *bare* model id that agents accept (no provider prefix).
///
/// This is a Swift literal rather than a file on disk because:
///   * the table is small and rarely changes (PRs are the right channel);
///   * the table is read on every run and we want zero IO overhead;
///   * pricing changes belong in version control so cost history stays
///     reproducible.
public enum Pricing {
    public static let table: [String: ModelPrice] = [
        // Anthropic. Indicative as of early 2026; update via PR.
        "claude-opus-4-7": ModelPrice(inputPerMTok: 15.00, outputPerMTok: 75.00),
        "claude-sonnet-4-6": ModelPrice(inputPerMTok: 3.00, outputPerMTok: 15.00),
        "claude-haiku-4-5": ModelPrice(inputPerMTok: 0.80, outputPerMTok: 4.00),
        // OpenAI / Codex variants.
        "gpt-5-codex": ModelPrice(inputPerMTok: 2.50, outputPerMTok: 10.00),
        "gpt-5": ModelPrice(inputPerMTok: 5.00, outputPerMTok: 15.00),
        // Google Gemini.
        "gemini-2.5-pro": ModelPrice(inputPerMTok: 1.25, outputPerMTok: 5.00),
        "gemini-2.5-flash": ModelPrice(inputPerMTok: 0.075, outputPerMTok: 0.30),
    ]

    /// Look up a model and return its price record, stripping `provider/` prefixes.
    public static func price(for model: String?) -> ModelPrice? {
        guard let model, !model.isEmpty else { return nil }
        let bare = model.split(separator: "/").last.map(String.init) ?? model
        return table[bare]
    }

    /// Compute cost from tokens + model. Returns nil when the model isn't known
    /// (the caller should keep `cost` honest about that, not fabricate a 0).
    public static func estimateCost(model: String?, inputTokens: Int?, outputTokens: Int?) -> Double? {
        guard let inputTokens, let outputTokens, let price = price(for: model) else { return nil }
        return price.cost(inputTokens: inputTokens, outputTokens: outputTokens)
    }
}

/// Best-effort extraction of an ``AgentUsage`` from agent stdout we don't
/// control. Non-Claude CLIs (codex, gemini, opencode, …) print results in
/// shifting formats. We scan known-shape JSON envelopes for the most common
/// accounting keys; when nothing matches we fall back to ``Pricing`` if the
/// model is known. When even that fails we return `nil` so the UI shows `—`.
public enum UsageExtractor {
    /// Search `stdout` for usage-shaped keys. Tokens are extracted if found;
    /// cost is taken from the envelope when present, otherwise priced from
    /// `model` via ``Pricing``. Returns `nil` when no signal can be recovered.
    public static func extract(stdout: String, model: String?) -> AgentUsage? {
        let envelopeUsage = parseEnvelope(stdout)
        if let envelopeUsage, envelopeUsage.hasData {
            // If the envelope gave us tokens but no cost and we know the
            // model, fill cost in from the price table.
            if envelopeUsage.totalCostUSD == nil,
               let cost = Pricing.estimateCost(
                   model: model,
                   inputTokens: envelopeUsage.inputTokens,
                   outputTokens: envelopeUsage.outputTokens
               )
            {
                var enriched = envelopeUsage
                enriched.totalCostUSD = cost
                enriched.source = .priceTable
                return enriched
            }
            return envelopeUsage
        }
        return nil
    }

    /// Decode any of the common usage shapes. Returns nil when nothing matches.
    private static func parseEnvelope(_ stdout: String) -> AgentUsage? {
        guard let data = stdout.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(LooseEnvelope.self, from: data),
           let usage = envelope.toUsage()
        {
            return usage
        }
        return nil
    }

    /// Catches several known top-level shapes:
    ///   * `{"usage": {...}}` (codex / opencode style)
    ///   * `{"tokens": {...}}` (gemini-style)
    ///   * `{"cost": 0.01}` / `{"total_cost_usd": 0.01}` flat fields
    private struct LooseEnvelope: Decodable {
        var usage: TokenBlock?
        var tokens: TokenBlock?
        var cost: Double?
        var total_cost_usd: Double?

        func toUsage() -> AgentUsage? {
            let block = usage ?? tokens
            let costValue = total_cost_usd ?? cost
            let input = block?.input_tokens ?? block?.prompt_tokens ?? block?.input
            let output = block?.output_tokens ?? block?.completion_tokens ?? block?.output
            if input == nil, output == nil, costValue == nil { return nil }
            return AgentUsage(
                inputTokens: input,
                outputTokens: output,
                totalCostUSD: costValue,
                source: .agentEnvelope
            )
        }
    }

    private struct TokenBlock: Decodable {
        var input_tokens: Int?
        var output_tokens: Int?
        var prompt_tokens: Int?
        var completion_tokens: Int?
        var input: Int?
        var output: Int?
    }
}
