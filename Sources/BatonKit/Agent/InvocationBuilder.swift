import Foundation

/// Builds every agent's `ProcessInvocation` uniformly so `binary`/`args`/`model`
/// overrides are honored identically for all agents (the blick PR #20 fix).
public enum InvocationBuilder {
    // swiftlint:disable:next function_parameter_count
    public static func make(
        runner: any AgentRunner,
        agent: AgentConfig,
        defaults: EffectiveDefaults,
        model: String?,
        prompt: String,
        workdir: URL,
        environment: [String: String] = [:]
    ) -> ProcessInvocation {
        var arguments = runner.baseArguments
        if agent.sandbox ?? ConfigDefaults.sandbox {
            arguments += runner.sandboxArguments
        }
        arguments += runner.modelArguments(model)
        arguments += agent.args ?? []
        if runner.promptDelivery == .argument {
            arguments.append(prompt)
        }

        return ProcessInvocation(
            executable: agent.binary ?? runner.defaultBinary,
            arguments: arguments,
            stdin: runner.promptDelivery == .stdin ? prompt : nil,
            workingDirectory: workdir,
            environment: environment,
            timeout: defaults.timeout
        )
    }
}
