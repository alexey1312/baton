@testable import BatonKit
import Testing

struct PricingTests {
    @Test("price strips provider/ prefix before lookup")
    func bareModel() {
        #expect(Pricing.price(for: "anthropic/claude-sonnet-4-6") != nil)
        #expect(Pricing.price(for: "claude-sonnet-4-6") != nil)
    }

    @Test("estimateCost returns nil for unknown models and computes for known ones")
    func estimate() {
        #expect(Pricing.estimateCost(model: nil, inputTokens: 1000, outputTokens: 100) == nil)
        #expect(Pricing.estimateCost(model: "unknown-model", inputTokens: 1000, outputTokens: 100) == nil)

        let cost = Pricing.estimateCost(
            model: "claude-sonnet-4-6", inputTokens: 1_000_000, outputTokens: 1_000_000
        )
        // 1M input at $3 + 1M output at $15 = $18.
        #expect(cost.map { abs($0 - 18.0) < 0.0001 } == true)
    }
}
