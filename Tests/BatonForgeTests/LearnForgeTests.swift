@testable import BatonForge
import BatonKit
import Foundation
import Testing

struct LearnForgeTests {
    /// A recording `gh` runner that returns canned responses keyed on the args.
    actor MockGH: GHRunning {
        struct Call { let args: [String]; let stdin: String? }
        private(set) var calls: [Call] = []
        private let responder: @Sendable (_ args: [String], _ stdin: String?) -> GHResult

        init(responder: @escaping @Sendable (_ args: [String], _ stdin: String?) -> GHResult) {
            self.responder = responder
        }

        func run(_ args: [String], stdin: String?) async throws -> GHResult {
            calls.append(Call(args: args, stdin: stdin))
            return responder(args, stdin)
        }
    }

    /// Thread-safe call counter so a `@Sendable` responder can vary its reply by
    /// attempt (the MockGH responder is synchronous and cannot await the actor).
    final class CallCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func next() -> Int {
            lock.lock(); defer { lock.unlock() }; n += 1; return n
        }
    }

    private func ok(_ stdout: String) -> GHResult {
        GHResult(status: 0, stdout: stdout, stderr: "")
    }

    private func http(_ status: Int, _ message: String) -> GHResult {
        GHResult(status: 1, stdout: "", stderr: "HTTP \(status): \(message)")
    }

    private func contains(_ args: [String], _ needle: String) -> Bool {
        args.contains { $0.contains(needle) }
    }

    private let fixedNow: @Sendable () -> Date = { Date(timeIntervalSince1970: 1_800_000_000) } // ~2027

    // MARK: - Merged PRs

    @Test("merged PRs are filtered to the lookback window")
    func mergedWindow() async throws {
        let recent = Date(timeIntervalSince1970: 1_800_000_000 - 2 * 86400)
        let old = Date(timeIntervalSince1970: 1_800_000_000 - 60 * 86400)
        let iso = ISO8601DateFormatter()
        let json = """
        [
          {"number": 5, "merged_at": "\(iso.string(from: recent))", "user": {"login": "alice"}},
          {"number": 6, "merged_at": "\(iso.string(from: old))", "user": {"login": "bob"}},
          {"number": 7, "merged_at": null, "user": {"login": "carol"}}
        ]
        """
        let gh = MockGH { _, _ in ok(json) }
        let forge = GitHubLearnForge(gh: gh, repo: "o/r", now: fixedNow)
        let prs = try await forge.mergedPullRequests(lookbackDays: 14)
        #expect(prs.map(\.number) == [5])
        #expect(prs.first?.author == "alice")
    }

    // MARK: - Thread signal

    private func graphQLThreads() -> String {
        let body = "**🔴 high — SQL injection**\\n\\nDetail\\n\\n\(BatonMarker.finding)"
        return """
        {"data":{"repository":{"pullRequest":{
          "author":{"login":"author"},
          "reviewThreads":{"nodes":[
            {"id":"T1","isResolved":true,"isOutdated":false,"resolvedBy":{"login":"reviewer"},
             "comments":{"nodes":[{"databaseId":123,"body":"\(body)","path":"ios/A.swift","line":10}]}},
            {"id":"T2","isResolved":true,"isOutdated":false,"resolvedBy":{"login":"ci[bot]"},
             "comments":{"nodes":[{"databaseId":124,"body":"\(body)","path":"ios/C.swift","line":3}]}},
            {"id":"T3","isResolved":false,"isOutdated":false,"resolvedBy":null,
             "comments":{"nodes":[{"databaseId":456,"body":"please fix this","path":"ios/B.swift","line":5}]}}
          ]}
        }}}}
        """
    }

    @Test("thread signals parse Baton vs human threads, resolution, actor, and reactions")
    func threadSignals() async throws {
        let reactions = #"[{"content":"+1","user":{"login":"bob"}},{"content":"-1","user":{"login":"author"}}]"#
        let gh = MockGH { args, _ in
            if contains(args, "graphql") { return ok(graphQLThreads()) }
            if contains(args, "/reactions") { return ok(reactions) }
            return ok("[]")
        }
        let forge = GitHubLearnForge(gh: gh, repo: "o/r")
        let pr = MergedPullRequest(number: 9, author: "author", mergedAt: Date())
        let signals = try await forge.threadSignals(for: pr)
        #expect(signals.count == 3)

        let baton = try #require(signals.first { $0.threadId == "T1" })
        #expect(baton.isBatonAuthored)
        #expect(baton.resolution == .resolved)
        #expect(baton.resolutionActor == "reviewer")
        #expect(!baton.resolvedByAutomation)
        #expect(baton.finding?.title == "SQL injection")
        #expect(baton.finding?.severity == .high)
        // bob's 👍 counts, author's own 👎 is excluded from the net.
        #expect(baton.netReactionWeight == 1)

        let automation = try #require(signals.first { $0.threadId == "T2" })
        #expect(automation.resolvedByAutomation) // ci[bot]

        let human = try #require(signals.first { $0.threadId == "T3" })
        #expect(!human.isBatonAuthored)
        #expect(human.finding == nil)
    }

    @Test("a configured automation actor's resolution is excluded as non-human signal")
    func automationActorExcluded() async throws {
        let body = "**🔴 high — X**\\n\\n\(BatonMarker.finding)"
        let json = """
        {"data":{"repository":{"pullRequest":{
          "author":{"login":"author"},
          "reviewThreads":{"nodes":[
            {"id":"T1","isResolved":true,"isOutdated":false,"resolvedBy":{"login":"svc-account"},
             "comments":{"nodes":[{"databaseId":1,"body":"\(body)","path":"ios/A.swift","line":1}]}}
          ]}
        }}}}
        """
        let gh = MockGH { args, _ in
            contains(args, "graphql") ? ok(json) : ok("[]")
        }
        let forge = GitHubLearnForge(gh: gh, repo: "o/r", options: .init(automationActors: ["svc-account"]))
        let pr = MergedPullRequest(number: 1, author: "author", mergedAt: Date())
        let signal = try #require(try await forge.threadSignals(for: pr).first)
        #expect(signal.resolvedByAutomation) // svc-account, though not a `[bot]`
    }

    @Test("the auto-resolve marker flags automation regardless of the resolving actor")
    func autoResolveMarkerIsTokenIndependent() async throws {
        let finding = "**🔴 high — X**\\n\\n\(BatonMarker.finding)"
        let reply = "Auto-resolved by Baton\\n\(BatonMarker.autoResolved)"
        // A human login resolved the thread, but a later comment carries the
        // auto-resolve marker — provenance must come from the marker, not the actor.
        let json = """
        {"data":{"repository":{"pullRequest":{
          "author":{"login":"author"},
          "reviewThreads":{"nodes":[
            {"id":"T1","isResolved":true,"isOutdated":true,"resolvedBy":{"login":"human-dev"},
             "comments":{"nodes":[
               {"databaseId":1,"body":"\(finding)","path":"ios/A.swift","line":1},
               {"databaseId":2,"body":"\(reply)","path":"ios/A.swift","line":1}
             ]}}
          ]}
        }}}}
        """
        let gh = MockGH { args, _ in contains(args, "graphql") ? ok(json) : ok("[]") }
        let forge = GitHubLearnForge(gh: gh, repo: "o/r")
        let pr = MergedPullRequest(number: 1, author: "author", mergedAt: Date())
        let signal = try #require(try await forge.threadSignals(for: pr).first)
        #expect(signal.resolvedByAutomation) // marker present, though "human-dev" is a human actor
        #expect(signal.resolutionActor == "human-dev")
    }

    @Test("a GraphQL query-level error fails hard instead of yielding empty signal")
    func graphQLErrorFailsHard() async throws {
        let errorBody = #"{"data":null,"errors":[{"message":"Could not resolve to a Repository"}]}"#
        let gh = MockGH { _, _ in ok(errorBody) } // HTTP 200 with errors
        let forge = GitHubLearnForge(gh: gh, repo: "o/r")
        let pr = MergedPullRequest(number: 1, author: "a", mergedAt: Date())
        await #expect(throws: ForgeError.self) {
            try await forge.threadSignals(for: pr)
        }
    }

    // MARK: - Delivery

    @Test("delivery opens a draft PR when none exists")
    func deliveryCreates() async throws {
        let gh = MockGH { args, _ in
            contains(args, "state=open") ? ok("[]") : ok(#"{"number": 42}"#)
        }
        let report = try await GitHubLearnDelivery(gh: gh).deliver(request())
        #expect(report.created)
        #expect(report.pullRequestNumber == 42)
    }

    @Test("delivery updates the existing rolling PR")
    func deliveryUpdates() async throws {
        let gh = MockGH { args, _ in
            contains(args, "state=open") ? ok(#"[{"number": 7}]"#) : ok(#"{"number": 7}"#)
        }
        let report = try await GitHubLearnDelivery(gh: gh).deliver(request())
        #expect(report.updated)
        #expect(report.pullRequestNumber == 7)
        let calls = await gh.calls
        #expect(calls.contains { $0.args.contains("PATCH") })
    }

    @Test("a write-denied token degrades delivery to preview with a warning")
    func deliveryDegrades() async throws {
        let gh = MockGH { args, _ in
            if contains(args, "state=open") { return ok("[]") }
            return GHResult(status: 1, stdout: "", stderr: "HTTP 403: Resource not accessible by integration")
        }
        let report = try await GitHubLearnDelivery(gh: gh).deliver(request())
        #expect(report.degradedToPreview)
        #expect(!report.created)
        #expect(report.warnings.contains { $0.contains("cannot open or update") })
    }

    @Test("a 422 validation error fails hard rather than degrading to preview")
    func validationErrorFailsHard() async throws {
        let gh = MockGH { args, _ in
            if contains(args, "state=open") { return ok("[]") }
            return GHResult(
                status: 1,
                stdout: "",
                stderr: "HTTP 422: Validation Failed: No commits between main and learn"
            )
        }
        await #expect(throws: ForgeError.self) {
            try await GitHubLearnDelivery(gh: gh).deliver(request())
        }
    }

    @Test("delivery retries a transient 5xx then succeeds")
    func deliveryRetriesTransient() async throws {
        let counter = CallCounter()
        let gh = MockGH { args, _ in
            if contains(args, "state=open") { return ok("[]") } // no existing PR
            // First create attempt 503s, the retry succeeds.
            return counter.next() == 1 ? http(503, "Service Unavailable") : ok(#"{"number": 42}"#)
        }
        let report = try await GitHubLearnDelivery(gh: gh, maxAttempts: 3).deliver(request())
        #expect(report.created)
        #expect(report.pullRequestNumber == 42)
    }

    @Test("delivery gives up after exactly maxAttempts on a persistent 5xx")
    func deliveryPersistent5xx() async throws {
        let gh = MockGH { args, _ in
            contains(args, "state=open") ? ok("[]") : http(503, "Service Unavailable")
        }
        await #expect(throws: ForgeError.self) {
            try await GitHubLearnDelivery(gh: gh, maxAttempts: 2).deliver(request())
        }
        let posts = await gh.calls.filter { $0.args.contains("POST") }
        #expect(posts.count == 2) // tried exactly maxAttempts, no more
    }

    @Test("signal read retries a transient 5xx then succeeds")
    func signalReadRetriesTransient() async throws {
        let counter = CallCounter()
        let gh = MockGH { _, _ in
            counter.next() == 1 ? http(503, "Service Unavailable") : ok("[]")
        }
        let forge = GitHubLearnForge(gh: gh, repo: "o/r", now: fixedNow)
        let prs = try await forge.mergedPullRequests(lookbackDays: 14)
        #expect(prs.isEmpty)
        #expect(await gh.calls.count == 2) // one failed, one retried-and-succeeded
    }

    private func request() -> LearnDeliveryRequest {
        LearnDeliveryRequest(repo: "o/r", branch: "learn", base: "main", title: "Baton learn", body: "body")
    }
}
