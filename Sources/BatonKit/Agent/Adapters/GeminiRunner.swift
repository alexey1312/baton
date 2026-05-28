/// Adapter for the Gemini CLI (non-interactive, auto-approve).
public struct GeminiRunner: AgentRunner {
    public let kind: AgentKind = .gemini
    public let defaultBinary = "gemini"
    public let baseArguments = ["--approval-mode=yolo", "--skip-trust"]
    /// Gemini has no flag to disable MCP outright (servers come from
    /// `~/.gemini/settings.json`, not extensions) and an empty allowlist is
    /// rejected. Restricting the allowlist to a sentinel name no real server
    /// matches disables them all — which also avoids the MCP-discovery hangs.
    public let sandboxArguments = ["--allowed-mcp-server-names", "baton-sandbox-no-mcp"]

    public init() {}

    public func parse(_ output: AgentOutput) throws -> ParsedFindings {
        var parsed = try FindingsParser.parse(output.stdout)
        parsed.usage = UsageExtractor.extract(stdout: output.stdout, model: output.model)
        return parsed
    }
}
