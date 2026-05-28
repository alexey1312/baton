/// Adapter for the Codex CLI (`codex exec`, non-interactive).
public struct CodexRunner: AgentRunner {
    public let kind: AgentKind = .codex
    public let defaultBinary = "codex"
    public let baseArguments = ["exec", "--skip-git-repo-check"]

    public init() {}
}
