/// Adapter for an arbitrary user-specified CLI.
///
/// Carries no headless flags of its own — the user provides everything via
/// `[agent].binary` and `[agent].args`. The prompt is delivered over stdin and the
/// output is parsed with the standard findings parser. `[agent].binary` is required
/// (there is no sensible default executable); see ``AgentToolPreflight`` and the
/// custom-binary validation.
public struct CustomRunner: AgentRunner {
    public let kind: AgentKind = .custom
    /// Empty: a custom agent has no built-in default; `[agent].binary` is required.
    public let defaultBinary = ""
    public let baseArguments: [String] = []

    public init() {}
}
