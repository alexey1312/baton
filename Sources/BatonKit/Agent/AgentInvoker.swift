import Foundation

/// The outcome of one agent invocation: parsed findings plus diagnostics.
public struct AgentRunOutcome: Sendable {
    public var findings: [Finding]
    public var rawOutput: String
    public var warnings: [String]
    public var duration: TimeInterval
    public var usage: AgentUsage?

    public init(
        findings: [Finding],
        rawOutput: String,
        warnings: [String],
        duration: TimeInterval,
        usage: AgentUsage? = nil
    ) {
        self.findings = findings
        self.rawOutput = rawOutput
        self.warnings = warnings
        self.duration = duration
        self.usage = usage
    }
}

/// Runs an agent invocation through ``ProcessExecutor`` and turns its output into
/// findings, mapping failure modes to typed ``AgentError``s.
public struct AgentInvoker: Sendable {
    private let executor: ProcessExecutor

    public init(executor: ProcessExecutor = ProcessExecutor()) {
        self.executor = executor
    }

    public func run(runner: any AgentRunner, invocation: ProcessInvocation) async throws -> AgentRunOutcome {
        let agent = runner.kind.rawValue
        let result = try await executor.run(invocation, agentName: agent)

        guard result.status == 0 else {
            throw AgentError.nonZeroExit(agent: agent, status: result.status, stderrTail: result.stderrTail())
        }
        guard !result.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // A zero exit with empty stdout usually means an auth/billing error
            // printed to stderr — treat as failure, not zero findings.
            throw AgentError.emptyOutput(agent: agent, stderrTail: result.stderrTail())
        }

        let output = AgentOutput(stdout: result.stdoutText, stderr: result.stderr, exitStatus: result.status)
        do {
            let parsed = try runner.parse(output)
            return AgentRunOutcome(
                findings: parsed.findings,
                rawOutput: result.stdoutText,
                warnings: parsed.warnings,
                duration: result.duration,
                usage: parsed.usage
            )
        } catch {
            throw AgentError.parseFailure(
                agent: agent,
                detail: "\(error)",
                likelyArgConflict: looksLikeArgConflict(result.stdoutText)
            )
        }
    }

    private func looksLikeArgConflict(_ output: String) -> Bool {
        let lower = output.lowercased()
        return lower.contains("usage:")
            || lower.contains("unknown option")
            || lower.contains("unexpected argument")
            || lower.contains("error: invalid")
    }
}
