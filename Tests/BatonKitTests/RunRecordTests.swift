@testable import BatonKit
import Foundation
import Testing

struct RunRecordTests {
    private func withTempRepo(_ body: (URL) throws -> Void) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("baton-runrec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private func completed(
        scope: String,
        review: String,
        findings: [Finding],
        failOn: Severity = .high
    ) -> CompletedTask {
        CompletedTask(
            result: ReviewTaskResult(scope: scope, review: review, findings: findings, failOn: failOn),
            prompt: "PROMPT for \(scope)/\(review)",
            rawOutput: "RAW for \(scope)/\(review)"
        )
    }

    @Test("write then load round-trips the run with manifest base and head SHA")
    func roundTrip() throws {
        try withTempRepo { root in
            let store = RunRecordStore(repoRoot: root)
            let task = completed(
                scope: "ios", review: "security",
                findings: [Finding(file: "a.swift", line: 1, severity: .high, title: "t", body: "b")]
            )
            try store.write(runId: "run1", base: "origin/main", headSHA: "deadbeef", tasks: [task])

            let loaded = try store.load(runId: nil) // via latest pointer
            #expect(loaded.manifest.base == "origin/main")
            #expect(loaded.manifest.headSHA == "deadbeef")
            #expect(loaded.results.count == 1)
            #expect(loaded.results[0].findings[0].title == "t")
        }
    }

    @Test("scope/review names with path separators are sanitized into safe filenames")
    func sanitizeNames() throws {
        try withTempRepo { root in
            let store = RunRecordStore(repoRoot: root)
            let task = completed(scope: "web/api", review: "a/b", findings: [])
            let outcome = try store.write(runId: "run2", base: "HEAD", headSHA: "sha", tasks: [task])
            let files = try FileManager.default.contentsOfDirectory(atPath: outcome.runDirectory.path)
            #expect(files.contains("web__api--a__b.json"))
            #expect(!files.contains { $0.contains("/") })
        }
    }

    @Test("root scope artifacts are named 'root'")
    func rootScopeName() throws {
        try withTempRepo { root in
            let store = RunRecordStore(repoRoot: root)
            let outcome = try store.write(
                runId: "r",
                base: "HEAD",
                headSHA: "s",
                tasks: [completed(scope: "", review: "sec", findings: [])]
            )
            let files = try FileManager.default.contentsOfDirectory(atPath: outcome.runDirectory.path)
            #expect(files.contains("root--sec.json"))
        }
    }

    @Test("missing latest pointer surfaces a typed error")
    func missingLatest() throws {
        try withTempRepo { root in
            let store = RunRecordStore(repoRoot: root)
            #expect(throws: RunRecordError.self) {
                _ = try store.load(runId: nil)
            }
        }
    }

    @Test("a missing run id surfaces a typed error")
    func missingRun() throws {
        try withTempRepo { root in
            let store = RunRecordStore(repoRoot: root)
            #expect(throws: RunRecordError.self) {
                _ = try store.load(runId: "does-not-exist")
            }
        }
    }

    // MARK: - Severity / fail_on

    @Test("a finding at or above fail_on fails the review")
    func failOnThreshold() {
        let result = ReviewTaskResult(
            scope: "s", review: "r",
            findings: [Finding(file: "a", severity: .high, title: "t", body: "b")],
            failOn: .medium
        )
        #expect(result.failed)
    }

    @Test("findings below fail_on pass the review")
    func belowThreshold() {
        let result = ReviewTaskResult(
            scope: "s", review: "r",
            findings: [Finding(file: "a", severity: .low, title: "t", body: "b")],
            failOn: .high
        )
        #expect(!result.failed)
    }

    @Test("exit status reflects any failed review")
    func exitStatus() {
        let pass = ReviewTaskResult(scope: "s", review: "ok", findings: [], failOn: .high)
        let fail = ReviewTaskResult(
            scope: "s", review: "bad",
            findings: [Finding(file: "a", severity: .high, title: "t", body: "b")],
            failOn: .high
        )
        #expect(!ReviewOutcome(results: [pass]).shouldFailExit)
        #expect(ReviewOutcome(results: [pass, fail]).shouldFailExit)
    }
}
