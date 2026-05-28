/// Adapter for the Gemini CLI (non-interactive, auto-approve).
public struct GeminiRunner: AgentRunner {
    public let kind: AgentKind = .gemini
    public let defaultBinary = "gemini"
    public let baseArguments = ["--approval-mode=yolo", "--skip-trust"]

    public init() {}

    public func parse(_ output: AgentOutput) throws -> ParsedFindings {
        var parsed = try FindingsParser.parse(output.stdout)
        parsed.usage = UsageExtractor.extract(stdout: output.stdout, model: output.model)
        return parsed
    }
}
