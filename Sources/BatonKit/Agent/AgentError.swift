/// Errors raised while building or running an agent invocation.
public enum AgentError: BatonError {
    /// The resolved agent binary is not present in `PATH`.
    case binaryNotFound(agent: String, binary: String)
    /// The agent is present but reports it is not authenticated.
    case unauthenticated(agent: String, detail: String)
    /// The agent exited with a non-zero status.
    case nonZeroExit(agent: String, status: Int32, stderrTail: String)
    /// The agent exited zero but produced empty stdout (often an auth/billing error
    /// printed to stderr).
    case emptyOutput(agent: String, stderrTail: String)
    /// The agent's output could not be parsed into findings.
    case parseFailure(agent: String, detail: String, likelyArgConflict: Bool)
    /// The agent ran longer than the configured timeout.
    case timedOut(agent: String, seconds: Int)
    /// A `custom` agent was configured without a `[agent].binary`.
    case customBinaryRequired

    public var errorDescription: String? {
        switch self {
        case let .binaryNotFound(agent, binary):
            "Agent '\(agent)' binary '\(binary)' was not found in PATH"
        case let .unauthenticated(agent, detail):
            "Agent '\(agent)' is not authenticated: \(detail)"
        case let .nonZeroExit(agent, status, tail):
            "Agent '\(agent)' exited \(status): \(tail)"
        case let .emptyOutput(agent, tail):
            "Agent '\(agent)' produced no output. stderr: \(tail)"
        case let .parseFailure(agent, detail, _):
            "Could not parse findings from agent '\(agent)': \(detail)"
        case let .timedOut(agent, seconds):
            "Agent '\(agent)' timed out after \(seconds)s"
        case .customBinaryRequired:
            "A custom agent requires an explicit binary"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case let .binaryNotFound(agent, _):
            "Install the \(agent) CLI and ensure it is on your PATH (run `baton doctor`)."
        case let .unauthenticated(agent, _):
            "Authenticate the \(agent) CLI (check its login/API-key setup), then retry."
        case .nonZeroExit:
            "Inspect the agent's stderr above; verify the CLI works standalone."
        case .emptyOutput:
            "The agent likely failed silently — check authentication, billing, and the model."
        case let .parseFailure(_, _, likelyArgConflict):
            likelyArgConflict
                ? "Your [agent].args may conflict with Baton's required headless/JSON flags; remove them."
                : "The agent did not return JSON findings; check the model and try --verbose."
        case .timedOut:
            "Increase [defaults].timeout or reduce the diff size."
        case .customBinaryRequired:
            "Set [agent].binary to the executable to run for `kind = \"custom\"`."
        }
    }
}
