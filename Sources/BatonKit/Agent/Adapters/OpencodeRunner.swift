/// Adapter for the opencode CLI (`opencode run`, non-interactive).
public struct OpencodeRunner: AgentRunner {
    public let kind: AgentKind = .opencode
    public let defaultBinary = "opencode"
    public let baseArguments = ["run"]
    /// `--pure` runs opencode without external plugins.
    public let sandboxArguments = ["--pure"]

    public init() {}

    public func parse(_ output: AgentOutput) throws -> ParsedFindings {
        var parsed = try FindingsParser.parse(output.stdout)
        parsed.usage = UsageExtractor.extract(stdout: output.stdout, model: output.model)
        return parsed
    }
}
