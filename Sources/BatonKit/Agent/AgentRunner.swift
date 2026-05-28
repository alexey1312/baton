import Foundation

/// The raw output captured from an agent process plus the model that was
/// invoked. `model` carries the resolved model id so adapters can pass it to
/// ``UsageExtractor`` for price-table fallback when the envelope omits cost.
public struct AgentOutput: Sendable {
    public var stdout: String
    public var stderr: String
    public var exitStatus: Int32
    public var model: String?

    public init(stdout: String, stderr: String, exitStatus: Int32, model: String? = nil) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitStatus = exitStatus
        self.model = model
    }
}

/// A thin adapter that declares how to invoke one coding CLI and parse its output.
///
/// The single ``InvocationBuilder`` applies `binary`/`args` overrides uniformly, so
/// adding an agent is ~10 lines and overrides are honored for every agent (the
/// blick PR #20 fix).
public protocol AgentRunner: Sendable {
    var kind: AgentKind { get }
    /// Default executable when `[agent].binary` is not set.
    var defaultBinary: String { get }
    /// Headless/non-interactive flags for this CLI.
    var baseArguments: [String] { get }
    /// Extra flags that make this CLI run hermetically — ignoring the user's
    /// global MCP servers, extensions, and plugins (so no ambient tools load and
    /// no interactive auth prompts fire). Appended only when sandbox is enabled.
    /// Empty by default; each adapter supplies its CLI's flags.
    var sandboxArguments: [String] { get }
    /// How the prompt is delivered (stdin by default).
    var promptDelivery: PromptDelivery { get }
    /// Map the resolved model to this CLI's model flag (empty when unset).
    func modelArguments(_ model: String?) -> [String]
    /// Convert captured output into findings (plus clamping warnings).
    func parse(_ output: AgentOutput) throws -> ParsedFindings
}

public extension AgentRunner {
    var promptDelivery: PromptDelivery {
        .stdin
    }

    var sandboxArguments: [String] {
        []
    }

    func modelArguments(_ model: String?) -> [String] {
        guard let model = Self.bareModel(model) else { return [] }
        return ["--model", model]
    }

    /// Default parse: run the robust findings parser over stdout.
    func parse(_ output: AgentOutput) throws -> ParsedFindings {
        try FindingsParser.parse(output.stdout)
    }

    /// Strip a `provider/` prefix (e.g. `anthropic/claude-…` → `claude-…`) where a
    /// CLI expects a bare model id. Returns `nil` for an unset model.
    static func bareModel(_ model: String?) -> String? {
        guard let model, !model.isEmpty else { return nil }
        if let slash = model.firstIndex(of: "/") {
            return String(model[model.index(after: slash)...])
        }
        return model
    }
}
