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
