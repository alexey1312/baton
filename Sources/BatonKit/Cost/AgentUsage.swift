import Foundation

/// Token and cost accounting for a single agent invocation (or a sum over
/// several chunks). All fields are optional because some agents do not emit
/// usage at all — in that case the UI surfaces `—` rather than fabricating
/// zeros.
public struct AgentUsage: Sendable, Codable, Equatable {
    /// Where the numbers in this struct came from.
    public enum Source: String, Sendable, Codable, Equatable {
        /// The agent's own output envelope carried the numbers (most trustworthy).
        case agentEnvelope = "agent_envelope"
        /// The agent only emitted tokens; cost was derived from a price table.
        case priceTable = "price_table"
        /// Nothing was parseable — both tokens and cost remain `nil`.
        case unknown
    }

    public var inputTokens: Int?
    public var outputTokens: Int?
    public var totalCostUSD: Double?
    public var source: Source

    public init(
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        totalCostUSD: Double? = nil,
        source: Source = .unknown
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalCostUSD = totalCostUSD
        self.source = source
    }

    public static let zero = AgentUsage()

    /// Whether any of the three numeric fields carries a value.
    public var hasData: Bool {
        inputTokens != nil || outputTokens != nil || totalCostUSD != nil
    }

    /// Add another usage record (component-wise; nil + value = value).
    /// Source resolves to the most authoritative of the two (envelope beats
    /// priceTable beats unknown).
    public func adding(_ other: AgentUsage) -> AgentUsage {
        AgentUsage(
            inputTokens: Self.add(inputTokens, other.inputTokens),
            outputTokens: Self.add(outputTokens, other.outputTokens),
            totalCostUSD: Self.add(totalCostUSD, other.totalCostUSD),
            source: Self.combine(source, other.source)
        )
    }

    private static func add<T: AdditiveArithmetic>(_ lhs: T?, _ rhs: T?) -> T? {
        switch (lhs, rhs) {
        case (nil, nil): nil
        case let (lhs?, nil): lhs
        case let (nil, rhs?): rhs
        case let (lhs?, rhs?): lhs + rhs
        }
    }

    private static func combine(_ lhs: Source, _ rhs: Source) -> Source {
        // envelope > priceTable > unknown
        if lhs == .agentEnvelope || rhs == .agentEnvelope { return .agentEnvelope }
        if lhs == .priceTable || rhs == .priceTable { return .priceTable }
        return .unknown
    }
}
