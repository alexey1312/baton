@testable import BatonKit
import Testing

struct UsageExtractorTests {
    @Test("extract reads codex-style {usage:{input_tokens, output_tokens}}")
    func codexShape() {
        let stdout = #"""
        {"findings":[],"usage":{"input_tokens":500,"output_tokens":120}}
        """#
        let usage = UsageExtractor.extract(stdout: stdout, model: nil)
        #expect(usage?.inputTokens == 500)
        #expect(usage?.outputTokens == 120)
        #expect(usage?.totalCostUSD == nil)
        #expect(usage?.source == .agentEnvelope)
    }

    @Test("extract reads gemini-style {tokens:{prompt_tokens, completion_tokens}}")
    func geminiShape() {
        let stdout = #"""
        {"tokens":{"prompt_tokens":200,"completion_tokens":50}}
        """#
        let usage = UsageExtractor.extract(stdout: stdout, model: nil)
        #expect(usage?.inputTokens == 200)
        #expect(usage?.outputTokens == 50)
    }

    @Test("extract enriches cost from Pricing when only tokens were emitted")
    func pricingFallback() {
        let stdout = #"""
        {"usage":{"input_tokens":1000000,"output_tokens":1000000}}
        """#
        let usage = UsageExtractor.extract(stdout: stdout, model: "claude-sonnet-4-6")
        #expect(usage?.totalCostUSD.map { abs($0 - 18.0) < 0.0001 } == true)
        #expect(usage?.source == .priceTable)
    }

    @Test("extract returns nil when stdout is plain prose with no usage fields")
    func noSignal() {
        #expect(UsageExtractor.extract(stdout: "no JSON at all", model: nil) == nil)
        #expect(UsageExtractor.extract(stdout: #"{"findings":[]}"#, model: "anything") == nil)
    }

    @Test("extract trusts envelope total_cost_usd over Pricing")
    func envelopeCostWins() {
        let stdout = #"""
        {"usage":{"input_tokens":1000,"output_tokens":100},"total_cost_usd":0.5}
        """#
        let usage = UsageExtractor.extract(stdout: stdout, model: "claude-sonnet-4-6")
        #expect(usage?.totalCostUSD == 0.5)
        #expect(usage?.source == .agentEnvelope)
    }
}
