@testable import BatonForge
import BatonKit
import Foundation
import Testing

struct GitHubForgeTests {
    /// A recording `gh` runner that returns canned responses keyed on the API path.
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

    private func ok(_ stdout: String = "") -> GHResult {
        GHResult(status: 0, stdout: stdout, stderr: "")
    }

    private func fail(_ stderr: String) -> GHResult {
        GHResult(status: 1, stdout: "", stderr: stderr)
    }

    private func run(headSHA: String = "sha123", findings: [Finding]) -> LoadedRun {
        let result = ReviewTaskResult(scope: "ios", review: "security", findings: findings, failOn: .high)
        let manifest = RunManifest(
            runId: "r", base: "origin/main", headSHA: headSHA, createdAt: Date(),
            tasks: [.init(
                scope: "ios",
                review: "security",
                findingsCount: findings.count,
                failed: false,
                recordFile: "ios--security.json"
            )]
        )
        return LoadedRun(directory: URL(fileURLWithPath: "/tmp"), manifest: manifest, results: [result])
    }

    private let highFinding = Finding(file: "ios/A.swift", line: 10, severity: .high, title: "bug", body: "b")
    private let prContext = PublishContext(repo: "o/r", headSHA: "sha123", prNumber: 7)

    // MARK: - Preflight

    @Test("preflight succeeds when gh is present and authenticated")
    func preflightOk() async throws {
        let gh = MockGH { _, _ in ok() }
        try await GitHubForge(gh: gh).preflight()
    }

    @Test("preflight fails when gh is missing or unauthenticated")
    func preflightFailures() async {
        let missing = MockGH { args, _ in args.first == "--version" ? fail("not found") : ok() }
        await #expect(throws: ForgeError.self) { try await GitHubForge(gh: missing).preflight() }

        let unauth = MockGH { args, _ in args.contains("status") ? fail("not logged in") : ok() }
        await #expect(throws: ForgeError.self) { try await GitHubForge(gh: unauth).preflight() }
    }

    // MARK: - Context

    @Test("context resolution: overrides win; repo+sha without PR is valid; missing fails")
    func contextResolution() throws {
        let env = GitHubActionsContext(repository: "env/repo", prNumber: 1, headSHA: "envsha")
        let overridden = try PublishContext.resolve(
            overrides: .init(ghRepo: "o/r", headSHA: "sha", pr: 9), env: env
        )
        #expect(overridden.repo == "o/r" && overridden.headSHA == "sha" && overridden.prNumber == 9)

        let noPR = try PublishContext.resolve(overrides: .init(ghRepo: "o/r", headSHA: "s"), env: nil)
        #expect(!noPR.hasPR)

        #expect(throws: ForgeError.self) {
            _ = try PublishContext.resolve(overrides: .init(), env: nil)
        }
    }

    // MARK: - Publish

    @Test("findings with lines become inline comments in a COMMENT review")
    func postsReview() async throws {
        let gh = MockGH { _, _ in ok("[]") }
        let report = try await GitHubForge(gh: gh).publish(run: run(findings: [highFinding]), context: prContext)
        #expect(report.reviewPosted)
        #expect(report.inlineCommentsPosted == 1)

        let calls = await gh.calls
        let reviewCall = try #require(calls.first(where: { $0.args.contains(where: { $0.contains("/reviews") }) }))
        let body = try #require(reviewCall.stdin)
        #expect(body.contains("COMMENT"))
        #expect(body.contains(BatonMarker.lastReviewed("sha123")))
    }

    @Test("a check run is created per scope-review with the high-gated conclusion")
    func createsCheckRun() async throws {
        let gh = MockGH { _, _ in ok("[]") }
        let report = try await GitHubForge(gh: gh).publish(run: run(findings: [highFinding]), context: prContext)
        #expect(report.checkRunsCreated == 1)
        let calls = await gh.calls
        let checkCall = try #require(calls.first(where: { $0.args.contains(where: { $0.contains("/check-runs") }) }))
        #expect(try #require(checkCall.stdin).contains("\"conclusion\":\"failure\""))
    }

    @Test("an already-posted comment is deduped, not reposted")
    func dedupe() async throws {
        let existing = #"[{"path":"ios/A.swift","line":10,"body":"old \#(BatonMarker.finding)"}]"#
        let gh = MockGH { args, _ in
            args.contains(where: { $0.contains("/comments") }) ? ok(existing) : ok("[]")
        }
        let report = try await GitHubForge(gh: gh).publish(run: run(findings: [highFinding]), context: prContext)
        #expect(report.inlineCommentsDeduped == 1)
        #expect(report.inlineCommentsPosted == 0)
    }

    @Test("a forbidden check run degrades to review-only with a warning")
    func checkRunDegrades() async throws {
        let gh = MockGH { args, _ in
            if args.contains(where: { $0.contains("/check-runs") }) {
                return GHResult(status: 1, stdout: "", stderr: "HTTP 403: Resource not accessible by integration")
            }
            return ok("[]")
        }
        let report = try await GitHubForge(gh: gh).publish(run: run(findings: [highFinding]), context: prContext)
        #expect(report.checkRunsSkipped == 1)
        #expect(report.reviewPosted) // review still posted
        #expect(report.warnings.contains(where: { $0.contains("Check Runs were skipped") }))
    }

    @Test("a stale head folds findings into the summary instead of inline comments")
    func staleHead() async throws {
        let gh = MockGH { _, _ in ok("[]") }
        // Saved run head differs from the publish context head.
        let stale = run(headSHA: "oldsha", findings: [highFinding])
        let report = try await GitHubForge(gh: gh).publish(run: stale, context: prContext)
        #expect(report.inlineCommentsPosted == 0)
        #expect(report.findingsFoldedIntoSummary == 1)
        #expect(report.warnings.contains(where: { $0.contains("differs from current head") }))
    }

    // MARK: - Auto-resolve outdated threads

    /// One review thread as the GraphQL `reviewThreads` read returns it. Defaults
    /// describe an obsolete Baton thread (outdated, unresolved, carries the finding
    /// marker, not yet auto-resolved) — the only shape that should be resolved.
    private func threadsJSON(
        isResolved: Bool = false,
        isOutdated: Bool = true,
        findingMarker: Bool = true,
        extraComment: String? = nil
    ) -> String {
        let body = "**🔴 high — bug**\\n\\n" + (findingMarker ? BatonMarker.finding : "no marker")
        var comments = [#"{"databaseId":555,"body":"\#(body)","path":"ios/A.swift","line":10}"#]
        if let extra = extraComment {
            comments.append(#"{"databaseId":556,"body":"\#(extra)","path":"ios/A.swift","line":10}"#)
        }
        return """
        {"data":{"repository":{"pullRequest":{
          "author":{"login":"alice"},
          "reviewThreads":{"nodes":[
            {"id":"T1","isResolved":\(isResolved),"isOutdated":\(isOutdated),"resolvedBy":null,
             "comments":{"nodes":[\(comments.joined(separator: ","))]}}
          ]}
        }}}}
        """
    }

    /// Route `gh` calls during an auto-resolving publish: the thread read vs the
    /// resolve mutation are both `api graphql`, told apart by the request body.
    private func resolvingGH(threads: String, reply: GHResult? = nil) -> MockGH {
        MockGH { args, stdin in
            if args.contains("graphql") {
                return (stdin ?? "").contains("resolveReviewThread") ? ok("{}") : ok(threads)
            }
            if let reply, (stdin ?? "").contains("in_reply_to") { return reply }
            return ok("[]")
        }
    }

    @Test("an outdated Baton thread is replied-to with the marker, then resolved")
    func resolvesOutdatedThread() async throws {
        let gh = resolvingGH(threads: threadsJSON())
        let report = try await GitHubForge(gh: gh, options: .init(resolveOutdatedThreads: true))
            .publish(run: run(findings: [highFinding]), context: prContext)
        #expect(report.threadsResolved == 1)
        #expect(report.threadsResolveSkipped == 0)

        let calls = await gh.calls
        let reply = try #require(calls.first { ($0.stdin ?? "").contains("in_reply_to") })
        #expect((reply.stdin ?? "").contains(BatonMarker.autoResolved))
        #expect(!(reply.stdin ?? "").contains(BatonMarker.finding)) // reply is not a finding comment
        #expect(calls.contains { ($0.stdin ?? "").contains("resolveReviewThread") })
    }

    @Test("auto-resolve skips non-outdated, resolved, non-Baton, and already-resolved threads")
    func autoResolveSkips() async throws {
        let alreadyMarked = "Auto-resolved\\n\(BatonMarker.autoResolved)"
        let cases = [
            threadsJSON(isOutdated: false), // not outdated
            threadsJSON(isResolved: true), // already resolved
            threadsJSON(findingMarker: false), // not Baton-authored
            threadsJSON(extraComment: alreadyMarked), // idempotency: already auto-resolved
        ]
        for threads in cases {
            let gh = resolvingGH(threads: threads)
            let report = try await GitHubForge(gh: gh, options: .init(resolveOutdatedThreads: true))
                .publish(run: run(findings: [highFinding]), context: prContext)
            #expect(report.threadsResolved == 0)
            let calls = await gh.calls
            #expect(!calls.contains { ($0.stdin ?? "").contains("in_reply_to") })
            #expect(!calls.contains { ($0.stdin ?? "").contains("resolveReviewThread") })
        }
    }

    @Test("auto-resolve reads no threads when the flag is off")
    func autoResolveDisabledByDefault() async throws {
        let gh = MockGH { _, _ in ok("[]") }
        _ = try await GitHubForge(gh: gh).publish(run: run(findings: [highFinding]), context: prContext)
        #expect(await !(gh.calls).contains { $0.args.contains("graphql") })
    }

    @Test("a forbidden auto-resolve degrades to a warning without failing the publish")
    func autoResolveDegrades() async throws {
        let forbidden = GHResult(status: 1, stdout: "", stderr: "HTTP 403: Resource not accessible by integration")
        let gh = resolvingGH(threads: threadsJSON(), reply: forbidden)
        let report = try await GitHubForge(gh: gh, options: .init(resolveOutdatedThreads: true))
            .publish(run: run(findings: [highFinding]), context: prContext)
        #expect(report.threadsResolved == 0)
        #expect(report.threadsResolveSkipped == 1)
        #expect(report.reviewPosted) // the review still posted
        #expect(report.warnings.contains { $0.contains("auto-resolution skipped") })
    }
}
