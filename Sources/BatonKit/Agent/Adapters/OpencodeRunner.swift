/// Adapter for the opencode CLI (`opencode run`, non-interactive).
public struct OpencodeRunner: AgentRunner {
    public let kind: AgentKind = .opencode
    public let defaultBinary = "opencode"
    public let baseArguments = ["run"]

    public init() {}

    public func parse(_ output: AgentOutput) throws -> ParsedFindings {
        var parsed = try FindingsParser.parse(output.stdout)
        parsed.usage = UsageExtractor.extract(stdout: output.stdout, model: output.model)
        return parsed
    }
}
