/// Adapter for the Codex CLI (`codex exec`, non-interactive).
public struct CodexRunner: AgentRunner {
    public let kind: AgentKind = .codex
    public let defaultBinary = "codex"
    public let baseArguments = ["exec", "--skip-git-repo-check"]

    public init() {}

    public func parse(_ output: AgentOutput) throws -> ParsedFindings {
        var parsed = try FindingsParser.parse(output.stdout)
        parsed.usage = UsageExtractor.extract(stdout: output.stdout, model: output.model)
        return parsed
    }
}
