@testable import BatonKit
import Testing

struct AgentUsageTests {
    @Test("adding folds nil and numeric fields component-wise")
    func addingFolds() {
        let lhs = AgentUsage(inputTokens: 100, outputTokens: nil, totalCostUSD: 0.01, source: .agentEnvelope)
        let rhs = AgentUsage(inputTokens: 50, outputTokens: 20, totalCostUSD: nil, source: .priceTable)
        let combined = lhs.adding(rhs)
        #expect(combined.inputTokens == 150)
        #expect(combined.outputTokens == 20)
        #expect(combined.totalCostUSD.map { abs($0 - 0.01) < 0.0001 } == true)
        #expect(combined.source == .agentEnvelope)
    }

    @Test("zero plus zero stays nil")
    func zeroIsAllNil() {
        let result = AgentUsage.zero.adding(.zero)
        #expect(result.inputTokens == nil)
        #expect(result.outputTokens == nil)
        #expect(result.totalCostUSD == nil)
        #expect(!result.hasData)
    }

    @Test("source priority: envelope > priceTable > unknown")
    func sourcePriority() {
        #expect(AgentUsage(source: .unknown).adding(AgentUsage(source: .priceTable)).source == .priceTable)
        #expect(AgentUsage(source: .priceTable).adding(AgentUsage(source: .agentEnvelope)).source == .agentEnvelope)
        #expect(AgentUsage(source: .unknown).adding(AgentUsage(source: .unknown)).source == .unknown)
    }
}
