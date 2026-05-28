@testable import BatonCLI
import BatonKit
import Foundation
import Testing

struct RenderTests {
    /// Write a fixture run to a temp repo and load it back.
    private func fixtureRun(findings: [Finding]) throws -> (LoadedRun, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("baton-render-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = RunRecordStore(repoRoot: root)
        let task = CompletedTask(
            result: ReviewTaskResult(scope: "ios", review: "security", findings: findings, failOn: .high),
            prompt: "P",
            rawOutput: "R"
        )
        try store.write(runId: "run1", base: "origin/main", headSHA: "sha123", tasks: [task])
        return try (store.load(runId: nil), root)
    }

    private let sample = Finding(
        file: "ios/App.swift", line: 42, severity: .high,
        title: "SQL injection", body: "Unsanitized input.", aiInstructions: "Use parameterized queries."
    )

    @Test("terminal, markdown, and json render from the saved record")
    func localFormats() throws {
        let (run, root) = try fixtureRun(findings: [sample])
        defer { try? FileManager.default.removeItem(at: root) }

        let terminal = try Renderer.render(run: run, format: .terminal, headSHA: nil)
        #expect(terminal.contains("SQL injection"))
        #expect(terminal.contains("ios/App.swift:42"))

        let markdown = try Renderer.render(run: run, format: .markdown, headSHA: nil)
        #expect(markdown.contains("**SQL injection**"))

        let json = try Renderer.render(run: run, format: .json, headSHA: nil)
        #expect(json.contains("\"head_sha\""))
        #expect(json.contains("SQL injection"))
    }

    @Test("github-review and check-run require a head SHA")
    func headSHARequired() throws {
        let (run, root) = try fixtureRun(findings: [sample])
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(throws: RenderError.self) {
            _ = try Renderer.render(run: run, format: .githubReview, headSHA: nil)
        }
        #expect(throws: RenderError.self) {
            _ = try Renderer.render(run: run, format: .checkRun, headSHA: "")
        }
    }

    @Test("github formats include the finding marker and AI-agent block")
    func githubFormats() throws {
        let (run, root) = try fixtureRun(findings: [sample])
        defer { try? FileManager.default.removeItem(at: root) }

        let review = try Renderer.render(run: run, format: .githubReview, headSHA: "sha123")
        #expect(review.contains(BatonMarker.finding))
        #expect(review.contains("Instructions for AI agents"))
        #expect(review.contains("\"event\""))

        let checkRun = try Renderer.render(run: run, format: .checkRun, headSHA: "sha123")
        #expect(checkRun.contains("\"conclusion\""))
        #expect(checkRun.contains("failure")) // high finding → failure

        let summary = try Renderer.render(run: run, format: .githubSummary, headSHA: nil)
        #expect(summary.contains("SQL injection"))
        #expect(summary.contains(BatonMarker.finding))
    }

    @Test("a run with zero findings still renders valid output")
    func zeroFindings() throws {
        let (run, root) = try fixtureRun(findings: [])
        defer { try? FileManager.default.removeItem(at: root) }

        for format in RenderFormat.allCases {
            let output = try Renderer.render(run: run, format: format, headSHA: "sha123")
            #expect(!output.isEmpty)
        }
    }

    /// Write a fixture run carrying a single failed (e.g. timed-out) task.
    private func fixtureFailedRun() throws -> (LoadedRun, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("baton-render-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = RunRecordStore(repoRoot: root)
        let task = CompletedTask(
            result: ReviewTaskResult(
                scope: "ios", review: "security", findings: [], failOn: .high,
                taskFailed: true, errorMessage: "Agent 'gemini' timed out after 600s"
            ),
            prompt: "P",
            rawOutput: ""
        )
        try store.write(runId: "run1", base: "origin/main", headSHA: "sha123", tasks: [task])
        return try (store.load(runId: nil), root)
    }

    @Test("a failed task surfaces its error instead of rendering as 'No findings'")
    func failedTaskSurfacesError() throws {
        let (run, root) = try fixtureFailedRun()
        defer { try? FileManager.default.removeItem(at: root) }

        let terminal = try Renderer.render(run: run, format: .terminal, headSHA: nil)
        #expect(terminal.contains("ios / security"))
        #expect(terminal.contains("timed out after 600s"))
        #expect(!terminal.contains("No findings"))

        let markdown = try Renderer.render(run: run, format: .markdown, headSHA: nil)
        #expect(markdown.contains("timed out after 600s"))
        #expect(!markdown.contains("No findings"))
    }
}
