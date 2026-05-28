import ArgumentParser
@testable import BatonCLI
import BatonKit
import Foundation
import Testing

struct ReviewE2ETests {
    /// Build a one-scope git repo whose agent is a `custom` mock script that emits a
    /// fixed JSON finding, with one modified file so there is a diff to review.
    private func makeFixture(findingSeverity: String) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("baton-e2e-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let git = GitRunner(repoRoot: root)
        _ = try git.run(["init", "-q", "-b", "main"])
        _ = try git.run(["config", "user.email", "t@e.com"])
        _ = try git.run(["config", "user.name", "T"])
        _ = try git.run(["config", "commit.gpgsign", "false"])

        // Mock agent: ignore stdin, print one finding.
        let script = root.appendingPathComponent("mock-agent.sh")
        let finding = #"{"file":"a.txt","line":1,"severity":"\#(findingSeverity)","title":"mock finding","body":"x"}"#
        let json = #"{"findings":[\#(finding)]}"#
        try "#!/bin/sh\ncat > /dev/null\ncat <<'EOF'\n\(json)\nEOF\n".write(
            to: script,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let config = """
        [agent]
        kind = "custom"
        binary = "\(script.path)"

        [[reviews]]
        name = "general"
        prompt = "Review it."
        """
        try config.write(to: root.appendingPathComponent("baton.toml"), atomically: true, encoding: .utf8)

        try "hello\n".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        _ = try git.run(["add", "."])
        _ = try git.run(["commit", "-q", "-m", "init"])
        // Modify so HEAD..worktree has a diff.
        try "hello\nworld\n".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        return root
    }

    @Test("review runs the mock agent, records findings, and fails on a high finding")
    func highFindingFailsExit() async throws {
        let root = try makeFixture(findingSeverity: "high")
        defer { try? FileManager.default.removeItem(at: root) }

        let cmd = try ReviewCommand.parse(["--repo", root.path, "--quiet"])
        await #expect(throws: ExitCode.self) {
            try await cmd.run() // exits non-zero because fail_on defaults to high
        }

        // The run record persisted the mock agent's finding.
        let loaded = try RunRecordStore(repoRoot: root).load(runId: nil)
        let findings = loaded.results.flatMap(\.findings)
        #expect(findings.count == 1)
        #expect(findings.first?.title == "mock finding")
        #expect(findings.first?.severity == .high)
    }

    @Test("a low finding passes (exit zero) under the default high threshold")
    func lowFindingPasses() async throws {
        let root = try makeFixture(findingSeverity: "low")
        defer { try? FileManager.default.removeItem(at: root) }

        let cmd = try ReviewCommand.parse(["--repo", root.path, "--quiet"])
        try await cmd.run() // does not throw ExitCode

        let loaded = try RunRecordStore(repoRoot: root).load(runId: nil)
        #expect(loaded.results.flatMap(\.findings).first?.severity == .low)
    }

    @Test("a named review that does not exist is rejected")
    func unknownNamedReview() async throws {
        let root = try makeFixture(findingSeverity: "low")
        defer { try? FileManager.default.removeItem(at: root) }

        let cmd = try ReviewCommand.parse(["does-not-exist", "--repo", root.path, "--quiet"])
        await #expect(throws: ExitCode.self) {
            try await cmd.run()
        }
    }
}
