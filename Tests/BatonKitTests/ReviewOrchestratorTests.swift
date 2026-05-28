@testable import BatonKit
import Foundation
import Testing

struct ReviewOrchestratorTests {
    // MARK: - Test doubles

    private actor Tracker {
        private var current = 0
        private(set) var maxObserved = 0
        private(set) var calls = 0
        func enter() {
            current += 1; calls += 1; maxObserved = max(maxObserved, current)
        }

        func leave() {
            current -= 1
        }
    }

    private struct MockSkills: SkillResolving {
        func resolve(
            _ skill: SkillConfig,
            declaringConfigDir _: URL,
            security _: SecurityConfig?
        ) throws -> ResolvedSkill {
            ResolvedSkill(name: skill.name, body: "BODY", sourceDescription: "mock")
        }
    }

    private struct MockAgent: ReviewAgentRunning {
        var findings: [Finding] = []
        var shouldFail = false
        var tracker: Tracker?

        func run(_: ReviewAgentRequest) async throws -> AgentRunOutcome {
            await tracker?.enter()
            try? await Task.sleep(nanoseconds: 15_000_000)
            await tracker?.leave()
            if shouldFail {
                throw AgentError.nonZeroExit(agent: "mock", status: 1, stderrTail: "boom")
            }
            return AgentRunOutcome(findings: findings, rawOutput: "{}", warnings: [], duration: 0.01)
        }
    }

    private func file(_ path: String, bytes: Int = 20) -> FileChange {
        FileChange(
            path: path,
            changeKind: .modified,
            hunks: [Hunk(header: "@@ -1 +1 @@", newStart: 1, lines: [String(repeating: "x", count: bytes)])],
            patch: "diff --git a/\(path) b/\(path)\n@@ -1 +1 @@\n+\(String(repeating: "x", count: bytes))"
        )
    }

    private func scope(
        _ path: String, reviews: [ReviewConfig], files: [FileChange],
        skills: [SkillConfig] = [], defaults: EffectiveDefaults = EffectiveDefaults()
    ) -> ScopePlan {
        let config = EffectiveConfig(
            scopePath: path,
            agent: AgentConfig(kind: .claude),
            defaults: defaults,
            skills: skills,
            reviews: reviews,
            security: nil,
            provenance: ConfigProvenance()
        )
        return ScopePlan(config: config, files: files, configDir: URL(fileURLWithPath: "/tmp"))
    }

    private let repoRoot = URL(fileURLWithPath: "/tmp")

    // MARK: - Tests

    @Test("one task is created per (scope, review)")
    func taskPerScopeReview() async throws {
        let scopes = [
            scope("ios", reviews: [ReviewConfig(name: "a"), ReviewConfig(name: "b")], files: [file("ios/x.swift")]),
            scope("web", reviews: [ReviewConfig(name: "a"), ReviewConfig(name: "b")], files: [file("web/y.ts")]),
        ]
        let orch = ReviewOrchestrator(repoRoot: repoRoot, agent: MockAgent(), skills: MockSkills())
        let tasks = try await orch.run(scopes: scopes)
        #expect(tasks.count == 4)
    }

    @Test("only the named review runs when onlyReview is set")
    func onlyReview() async throws {
        let scopes = [scope(
            "ios",
            reviews: [ReviewConfig(name: "a"), ReviewConfig(name: "security")],
            files: [file("ios/x.swift")]
        )]
        let orch = ReviewOrchestrator(repoRoot: repoRoot, agent: MockAgent(), skills: MockSkills())
        let tasks = try await orch.run(scopes: scopes, options: .init(onlyReview: "security"))
        #expect(tasks.map(\.result.review) == ["security"])
    }

    @Test("a review whose glob matches nothing produces no task")
    func globNoMatch() async throws {
        let scopes = [scope(
            "ios",
            reviews: [ReviewConfig(name: "kt", glob: ["**/*.kt"])],
            files: [file("ios/x.swift")]
        )]
        let orch = ReviewOrchestrator(repoRoot: repoRoot, agent: MockAgent(), skills: MockSkills())
        let tasks = try await orch.run(scopes: scopes)
        #expect(tasks.isEmpty)
    }

    @Test("a failing task is recorded and does not abort the run")
    func failingTaskRecorded() async throws {
        let scopes = [scope(
            "ios",
            reviews: [ReviewConfig(name: "a"), ReviewConfig(name: "b")],
            files: [file("ios/x.swift")]
        )]
        let orch = ReviewOrchestrator(repoRoot: repoRoot, agent: MockAgent(shouldFail: true), skills: MockSkills())
        let tasks = try await orch.run(scopes: scopes)
        let allTaskFailed = tasks.allSatisfy(\.result.taskFailed)
        let allFailed = tasks.allSatisfy(\.result.failed)
        #expect(tasks.count == 2)
        #expect(allTaskFailed)
        #expect(allFailed)
    }

    @Test("sliding window bounds concurrency")
    func concurrencyBound() async throws {
        let tracker = Tracker()
        let reviews = (0 ..< 6).map { ReviewConfig(name: "r\($0)") }
        let scopes = [scope("ios", reviews: reviews, files: [file("ios/x.swift")])]
        let orch = ReviewOrchestrator(repoRoot: repoRoot, agent: MockAgent(tracker: tracker), skills: MockSkills())
        _ = try await orch.run(scopes: scopes, options: .init(maxConcurrencyOverride: 2))
        let observed = await tracker.maxObserved
        #expect(observed <= 2)
        #expect(observed >= 1)
    }

    @Test("findings merged across chunks are deduplicated")
    func dedupeAcrossChunks() async throws {
        let tracker = Tracker()
        let finding = Finding(file: "ios/x.swift", line: 1, severity: .high, title: "dup", body: "b")
        // Tiny budget forces two by-file chunks, so the agent runs twice.
        let tightDefaults = EffectiveDefaults(diffBudget: 10)
        let scopes = [scope(
            "ios",
            reviews: [ReviewConfig(name: "a")],
            files: [file("ios/x.swift", bytes: 40), file("ios/y.swift", bytes: 40)],
            defaults: tightDefaults
        )]
        let orch = ReviewOrchestrator(
            repoRoot: repoRoot, agent: MockAgent(findings: [finding], tracker: tracker), skills: MockSkills()
        )
        let tasks = try await orch.run(scopes: scopes)
        let calls = await tracker.calls
        #expect(calls >= 2) // multiple chunks → multiple passes
        #expect(tasks.first?.result.findings.count == 1) // deduped
    }

    @Test("static dedupe keeps first by (file, line, severity, title)")
    func staticDedupe() {
        let a = Finding(file: "x", line: 1, severity: .high, title: "t", body: "first")
        let b = Finding(file: "x", line: 1, severity: .high, title: "t", body: "second")
        let c = Finding(file: "x", line: 2, severity: .high, title: "t", body: "third")
        let result = ReviewOrchestrator.dedupe([a, b, c])
        #expect(result.count == 2)
        #expect(result[0].body == "first")
    }
}
