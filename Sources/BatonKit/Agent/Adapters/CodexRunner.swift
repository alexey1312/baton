/// Adapter for the Codex CLI (`codex exec`, non-interactive).
public struct CodexRunner: AgentRunner {
    public let kind: AgentKind = .codex
    public let defaultBinary = "codex"
    public let baseArguments = ["exec", "--skip-git-repo-check"]
    /// `--ignore-user-config` skips `$CODEX_HOME/config.toml` (MCP servers, custom
    /// config) while auth still resolves via `CODEX_HOME`.
    public let sandboxArguments = ["--ignore-user-config"]

    public init() {}

    public func parse(_ output: AgentOutput) throws -> ParsedFindings {
        var parsed = try FindingsParser.parse(output.stdout)
        parsed.usage = UsageExtractor.extract(stdout: output.stdout, model: output.model)
        return parsed
    }
}
