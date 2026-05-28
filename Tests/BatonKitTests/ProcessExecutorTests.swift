@testable import BatonKit
import Foundation
import Testing

struct ProcessExecutorTests {
    private let workdir = FileManager.default.temporaryDirectory

    private func invocation(
        _ executable: String,
        _ args: [String],
        stdin: String? = nil,
        timeout: Int = 30
    ) -> ProcessInvocation {
        ProcessInvocation(
            executable: executable,
            arguments: args,
            stdin: stdin,
            workingDirectory: workdir,
            timeout: timeout
        )
    }

    @Test("captures stdout from a command")
    func capturesStdout() async throws {
        let result = try await ProcessExecutor().run(invocation("echo", ["hello"]), agentName: "test")
        #expect(result.status == 0)
        #expect(result.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines) == "hello")
    }

    @Test("delivers stdin to the process")
    func deliversStdin() async throws {
        let result = try await ProcessExecutor().run(invocation("cat", [], stdin: "piped-input"), agentName: "test")
        #expect(result.stdoutText == "piped-input")
    }

    @Test("terminates a process that exceeds the timeout")
    func timeout() async {
        await #expect(throws: AgentError.self) {
            _ = try await ProcessExecutor().run(invocation("sleep", ["5"], timeout: 1), agentName: "test")
        }
    }

    @Test("AgentInvoker parses findings from a successful run")
    func invokerSuccess() async throws {
        let json = #"[{"file":"a.swift","severity":"high","title":"t","body":"b"}]"#
        let outcome = try await AgentInvoker().run(
            runner: OpencodeRunner(),
            invocation: invocation("echo", [json])
        )
        #expect(outcome.findings.count == 1)
        #expect(outcome.findings[0].severity == .high)
    }

    @Test("AgentInvoker treats a non-zero exit as a typed failure")
    func invokerNonZero() async {
        await #expect(throws: AgentError.self) {
            _ = try await AgentInvoker().run(runner: OpencodeRunner(), invocation: invocation("false", []))
        }
    }

    @Test("AgentInvoker treats zero-exit-with-empty-output as a failure")
    func invokerEmpty() async {
        await #expect(throws: AgentError.self) {
            _ = try await AgentInvoker().run(runner: OpencodeRunner(), invocation: invocation("true", []))
        }
    }
}
