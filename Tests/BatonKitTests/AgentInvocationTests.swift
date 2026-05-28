@testable import BatonKit
import Foundation
import Testing

struct AgentInvocationTests {
    private let workdir = URL(fileURLWithPath: "/tmp")
    private let defaults = EffectiveDefaults(timeout: 600)

    @Test("binary override is honored for every agent kind")
    func binaryOverrideAllAgents() {
        for kind in AgentKind.allCases {
            let runner = AgentRegistry.runner(for: kind)
            let agent = AgentConfig(kind: kind, binary: "/custom/bin/\(kind.rawValue)")
            let inv = InvocationBuilder.make(
                runner: runner, agent: agent, defaults: defaults,
                model: nil, prompt: "P", workdir: workdir
            )
            #expect(inv.executable == "/custom/bin/\(kind.rawValue)")
        }
    }

    @Test("custom args are appended after base args for every agent")
    func customArgsAppended() {
        for kind in AgentKind.allCases {
            let runner = AgentRegistry.runner(for: kind)
            let agent = AgentConfig(kind: kind, args: ["--verbose"])
            let inv = InvocationBuilder.make(
                runner: runner, agent: agent, defaults: defaults,
                model: nil, prompt: "P", workdir: workdir
            )
            #expect(inv.arguments.last == "--verbose")
            #expect(inv.arguments.starts(with: runner.baseArguments))
        }
    }

    @Test("model flag maps and strips a provider/ prefix")
    func modelMapping() {
        let inv = InvocationBuilder.make(
            runner: ClaudeRunner(),
            agent: AgentConfig(kind: .claude),
            defaults: defaults,
            model: "anthropic/claude-opus-4-7",
            prompt: "P",
            workdir: workdir
        )
        #expect(inv.arguments.contains("--model"))
        #expect(inv.arguments.contains("claude-opus-4-7"))
        #expect(!inv.arguments.contains("anthropic/claude-opus-4-7"))
    }

    @Test("unset model omits the model flag")
    func unsetModel() {
        let inv = InvocationBuilder.make(
            runner: GeminiRunner(), agent: AgentConfig(kind: .gemini),
            defaults: defaults, model: nil, prompt: "P", workdir: workdir
        )
        #expect(!inv.arguments.contains("--model"))
    }

    @Test("prompt is delivered via stdin, never as an argument")
    func promptViaStdin() {
        let inv = InvocationBuilder.make(
            runner: ClaudeRunner(), agent: AgentConfig(kind: .claude),
            defaults: defaults, model: nil, prompt: "BIG PROMPT", workdir: workdir
        )
        #expect(inv.stdin == "BIG PROMPT")
        #expect(!inv.arguments.contains("BIG PROMPT"))
    }

    @Test("every built-in agent has an adapter with a non-empty binary and base args")
    func registryComplete() {
        for kind in AgentKind.builtIn {
            let runner = AgentRegistry.runner(for: kind)
            #expect(runner.kind == kind)
            #expect(!runner.defaultBinary.isEmpty)
            #expect(!runner.baseArguments.isEmpty)
        }
    }

    @Test("custom agent requires an explicit binary")
    func customRequiresBinary() throws {
        #expect(throws: AgentError.self) {
            _ = try AgentToolPreflight.resolveBinary(kind: .custom, configBinary: nil)
        }
        #expect(try AgentToolPreflight
            .resolveBinary(kind: .custom, configBinary: "/usr/bin/my-agent") == "/usr/bin/my-agent")
        #expect(try AgentToolPreflight.resolveBinary(kind: .claude, configBinary: nil) == "claude")
    }

    // POSIX paths/PATH semantics; Windows resolution is covered by ProcessLauncher.
    #if !os(Windows)
    @Test("tool preflight detects binaries on PATH and explicit paths")
    func preflight() {
        #expect(AgentToolPreflight.isAvailable("/bin/sh"))
        #expect(AgentToolPreflight.isAvailable("sh", environment: ["PATH": "/bin:/usr/bin"]))
        #expect(!AgentToolPreflight.isAvailable("baton-no-such-binary-xyz", environment: ["PATH": "/bin"]))
    }
    #endif
}
