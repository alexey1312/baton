/// Adapter for the Gemini CLI (non-interactive, auto-approve).
public struct GeminiRunner: AgentRunner {
    public let kind: AgentKind = .gemini
    public let defaultBinary = "gemini"
    public let baseArguments = ["--approval-mode=yolo", "--skip-trust"]

    public init() {}
}
