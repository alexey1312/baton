/// Maps each ``AgentKind`` to its adapter.
public enum AgentRegistry {
    public static func runner(for kind: AgentKind) -> any AgentRunner {
        switch kind {
        case .claude: ClaudeRunner()
        case .codex: CodexRunner()
        case .gemini: GeminiRunner()
        case .opencode: OpencodeRunner()
        case .custom: CustomRunner()
        }
    }
}
