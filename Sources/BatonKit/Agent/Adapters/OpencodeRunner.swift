/// Adapter for the opencode CLI (`opencode run`, non-interactive).
public struct OpencodeRunner: AgentRunner {
    public let kind: AgentKind = .opencode
    public let defaultBinary = "opencode"
    public let baseArguments = ["run"]

    public init() {}
}
