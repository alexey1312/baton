import BatonKit
import Foundation

/// Publishes a saved Baton run to a GitHub pull request via the `gh` CLI: one PR
/// review with resolvable inline comments, plus one Check Run per `(scope, review)`.
///
/// All GitHub access goes through an injected ``GHRunning`` so the publisher is fully
/// unit-testable without the network. See `design.md` Decisions 2, 11, 12.
public struct GitHubForge: Forge {
    /// Tuning knobs for a publish (bundled to keep call sites small).
    public struct Options: Sendable, Equatable {
        /// Max inline comments per review before the overflow folds into summaries.
        public var inlineCommentCap: Int
        /// Max attempts for a single API call when rate-limited or hit by a 5xx.
        public var maxAttempts: Int
        /// Whether publish auto-resolves Baton's own outdated review threads.
        public var resolveOutdatedThreads: Bool

        public init(inlineCommentCap: Int = 50, maxAttempts: Int = 3, resolveOutdatedThreads: Bool = false) {
            self.inlineCommentCap = inlineCommentCap
            self.maxAttempts = maxAttempts
            self.resolveOutdatedThreads = resolveOutdatedThreads
        }
    }

    private let gh: GHRunning
    private let options: Options

    public init(gh: GHRunning = LiveGHRunner(), options: Options = Options()) {
        self.gh = gh
        self.options = options
    }

    // MARK: - Preflight

    /// Verify `gh` is present and authenticated before any publish.
    public func preflight() async throws {
        let version = try await gh.run(["--version"])
        guard version.isSuccess else { throw ForgeError.ghNotFound }

        let auth = try await gh.run(["auth", "status"])
        guard auth.isSuccess else { throw ForgeError.ghUnauthenticated }
    }

    // MARK: - Publish

    /// Publish `run` against `context`, returning what was posted.
    public func publish(run: LoadedRun, context: PublishContext) async throws -> PublishReport {
        var report = PublishReport()
        let staleHead = run.manifest.headSHA != context.headSHA && !run.manifest.headSHA.isEmpty
        if staleHead {
            report.warnings.append(
                "Saved run head \(run.manifest.headSHA) differs from current head " +
                    "\(context.headSHA); inline comments are folded into summaries."
            )
        }

        // Existing Baton inline comments, used to dedupe re-runs.
        let existing = context.hasPR ? try await fetchExistingComments(context: context) : []

        let plan = buildPlan(
            results: run.results,
            staleHead: staleHead,
            canAnchor: context.hasPR,
            existing: existing
        )
        report.inlineCommentsDeduped = plan.dedupedCount
        report.findingsFoldedIntoSummary = plan.foldedCount

        if context.hasPR, !plan.inlineComments.isEmpty {
            try await postReview(comments: plan.inlineComments, context: context)
            report.inlineCommentsPosted = plan.inlineComments.count
            report.reviewPosted = true
        }

        try await postCheckRuns(plan: plan, context: context, report: &report)

        if options.resolveOutdatedThreads, context.hasPR {
            await resolveObsoleteThreads(context: context, report: &report)
        }
        return report
    }

    // MARK: - Planning

    /// The posting plan derived from a run's results: the inline comments to post and
    /// the per-`(scope, review)` summary findings (folded + already-handled).
    struct PostingPlan {
        var inlineComments: [GitHubAPIBodies.ReviewComment] = []
        var checkRuns: [CheckRunPlan] = []
        var dedupedCount = 0
        var foldedCount = 0
    }

    /// One Check Run to create: identity + the findings that belong in its summary.
    struct CheckRunPlan {
        var scope: String
        var review: String
        var allFindings: [Finding]
        var summaryFindings: [Finding]
    }

    private func buildPlan(
        results: [ReviewTaskResult],
        staleHead: Bool,
        canAnchor: Bool,
        existing: Set<ExistingKey>
    ) -> PostingPlan {
        var plan = PostingPlan()
        for result in results {
            var summaryFindings: [Finding] = []
            for finding in result.findings {
                let anchorable = canAnchor && !staleHead && finding.line != nil
                    && plan.inlineComments.count < options.inlineCommentCap
                guard anchorable, let line = finding.line else {
                    summaryFindings.append(finding)
                    if finding.line != nil { plan.foldedCount += 1 }
                    continue
                }
                if existing.contains(ExistingKey(path: finding.file, line: line)) {
                    plan.dedupedCount += 1
                    continue
                }
                plan.inlineComments.append(GitHubAPIBodies.ReviewComment(
                    path: finding.file,
                    line: line,
                    side: "RIGHT",
                    body: GitHubPresentation.inlineCommentBody(finding)
                ))
            }
            plan.checkRuns.append(CheckRunPlan(
                scope: result.scope,
                review: result.review,
                allFindings: result.findings,
                summaryFindings: summaryFindings
            ))
        }
        return plan
    }

    // MARK: - Review posting

    private func postReview(
        comments: [GitHubAPIBodies.ReviewComment],
        context: PublishContext
    ) async throws {
        let body = GitHubAPIBodies.ReviewRequest(
            event: "COMMENT",
            body: BatonMarker.lastReviewed(context.headSHA),
            commit_id: context.headSHA,
            comments: comments
        )
        let path = "/repos/\(context.repo)/pulls/\(context.prNumber ?? 0)/reviews"
        let json = try GitHubAPIBodies.json(body)
        _ = try await call(APIRequest(method: "POST", path: path, stdin: json))
    }

    // MARK: - Check Runs

    private func postCheckRuns(
        plan: PostingPlan,
        context: PublishContext,
        report: inout PublishReport
    ) async throws {
        for checkRun in plan.checkRuns {
            let body = GitHubAPIBodies.CheckRunRequest(
                name: "baton: \(checkRun.scope.isEmpty ? "root" : checkRun.scope)/\(checkRun.review)",
                head_sha: context.headSHA,
                status: "completed",
                conclusion: GitHubPresentation.conclusion(for: checkRun.allFindings).rawValue,
                output: GitHubAPIBodies.CheckRunOutput(
                    title: "baton: \(checkRun.scope.isEmpty ? "root" : checkRun.scope)/\(checkRun.review)",
                    summary: GitHubPresentation.summaryBody(
                        scope: checkRun.scope,
                        review: checkRun.review,
                        findings: checkRun.summaryFindings
                    )
                )
            )
            let json = try GitHubAPIBodies.json(body)
            do {
                _ = try await call(APIRequest(
                    method: "POST",
                    path: "/repos/\(context.repo)/check-runs",
                    stdin: json,
                    isCheckRun: true
                ))
                report.checkRunsCreated += 1
            } catch let error as ForgeError {
                guard case .checkRunForbidden = error else { throw error }
                report.checkRunsSkipped += 1
                if report.checkRunsSkipped == 1 {
                    report.warnings.append(
                        "Check Runs were skipped: the token cannot create them (a GitHub App token " +
                            "is required, e.g. the Actions GITHUB_TOKEN). The PR review was still posted."
                    )
                }
            }
        }
    }

    // MARK: - Thread resolution

    /// Resolve a PR review thread via the GraphQL `resolveReviewThread` mutation.
    public func resolveReviewThread(threadId: String) async throws {
        let body = GitHubAPIBodies.GraphQLResolveThread(
            query: """
            mutation($threadId: ID!) {
              resolveReviewThread(input: {threadId: $threadId}) {
                thread { id isResolved }
              }
            }
            """,
            variables: .init(threadId: threadId)
        )
        let json = try GitHubAPIBodies.json(body)
        let result = try await gh.run(["api", "graphql", "--input", "-"], stdin: json)
        if !result.isSuccess {
            throw ForgeError.publishFailed(detail: GHApiClient.errorText(result))
        }
    }

    // MARK: - Existing comment lookup (dedupe)

    private struct ExistingKey: Hashable {
        let path: String
        let line: Int
    }

    private func fetchExistingComments(context: PublishContext) async throws -> Set<ExistingKey> {
        let path = "/repos/\(context.repo)/pulls/\(context.prNumber ?? 0)/comments"
        let result = try await call(APIRequest(method: "GET", path: path, stdin: nil, paginate: true))
        var keys: Set<ExistingKey> = []
        for comment in GitHubAPIBodies.decodeExistingComments(result.stdout) {
            guard let body = comment.body, body.contains(BatonMarker.finding),
                  let path = comment.path, let line = comment.line
            else { continue }
            keys.insert(ExistingKey(path: path, line: line))
        }
        return keys
    }

    // MARK: - gh api invocation + retry/error mapping

    /// One `gh api` request (bundled so call sites stay under the param-count limit).
    private struct APIRequest {
        var method: String
        var path: String
        var stdin: String?
        /// True for the check-runs endpoint, so a 403/422 maps to a degradable
        /// ``ForgeError/checkRunForbidden`` rather than a hard write failure.
        var isCheckRun = false
        /// Follow `Link` pagination (used for the existing-comments dedupe lookup).
        var paginate = false
    }

    private var api: GHApiClient {
        GHApiClient(gh: gh, maxAttempts: options.maxAttempts)
    }

    private func call(_ request: APIRequest) async throws -> GHResult {
        var args = ["api", "--method", request.method, request.path]
        if request.paginate { args += ["--paginate"] }
        if request.stdin != nil { args += ["--input", "-"] }
        return try await api.run(args, stdin: request.stdin) { result in
            Self.mapError(result, isCheckRun: request.isCheckRun)
        }
    }

    /// Map a terminal (non-retryable) `gh api` failure to a typed ``ForgeError``.
    /// A Check Run 403/422 degrades; a write 403/422 denies; anything else fails.
    static func mapError(_ result: GHResult, isCheckRun: Bool) -> ForgeError {
        if let transient = GHApiClient.transientError(result) { return transient }
        let detail = GHApiClient.errorText(result)
        let text = detail.lowercased()
        let isForbidden = text.contains("403") || text.contains("422")
            || text.contains("forbidden") || text.contains("not accessible by integration")
        if isCheckRun, isForbidden {
            return .checkRunForbidden(detail: detail)
        }
        if isForbidden || text.contains("must have write access") {
            return .writePermissionDenied(detail: detail)
        }
        return .publishFailed(detail: detail)
    }
}

// MARK: - Auto-resolve obsolete threads

extension GitHubForge {
    /// Auto-resolve Baton's own review threads GitHub has flagged outdated (opt-in
    /// via `[publish].resolve_outdated_threads`). For each obsolete thread, post a
    /// reply carrying ``BatonMarker/autoResolved`` (token-independent provenance so
    /// `learn` never counts it as human signal), then invoke `resolveReviewThread`.
    ///
    /// Best-effort: a failed thread read or a per-thread permission/error is recorded
    /// in `report` and skipped — auto-resolution never aborts a successful publish.
    func resolveObsoleteThreads(context: PublishContext, report: inout PublishReport) async {
        guard let prNumber = context.prNumber else { return }
        let reader = ReviewThreadReader(gh: gh, maxAttempts: options.maxAttempts)
        let threads: [ReviewThreadReader.ThreadsResponse.ThreadNode]
        do {
            threads = try await reader
                .pullRequest(owner: context.owner, name: context.name, number: prNumber)
                .reviewThreads.nodes
        } catch {
            report.warnings.append(
                "Thread auto-resolution skipped (could not read review threads): \(describe(error))"
            )
            return
        }
        for thread in threads where isObsoleteBatonThread(thread) {
            do {
                try await resolveOne(thread, prNumber: prNumber, repo: context.repo)
                report.threadsResolved += 1
            } catch {
                report.threadsResolveSkipped += 1
                if report.threadsResolveSkipped == 1 {
                    report.warnings.append(
                        "Thread auto-resolution skipped: \(describe(error)) "
                            + "The review and Check Runs were still posted."
                    )
                }
            }
        }
    }

    /// A thread is obsolete iff GitHub flagged it outdated, it is still unresolved,
    /// it is Baton-authored (carries the finding marker), and it has not already been
    /// auto-resolved (idempotency for re-runs).
    private func isObsoleteBatonThread(_ thread: ReviewThreadReader.ThreadsResponse.ThreadNode) -> Bool {
        thread.isOutdated && !thread.isResolved
            && thread.hasComment(containing: BatonMarker.finding)
            && !thread.hasComment(containing: BatonMarker.autoResolved)
    }

    private func resolveOne(
        _ thread: ReviewThreadReader.ThreadsResponse.ThreadNode,
        prNumber: Int,
        repo: String
    ) async throws {
        guard let rootCommentId = thread.comments.nodes.first?.databaseId else {
            throw ForgeError.publishFailed(detail: "thread \(thread.id) has no comment to reply to")
        }
        // Marker before mutation: if the resolve later fails, the thread is still
        // attributed to automation and a re-run retries the resolve (still unresolved).
        try await postReply(
            prNumber: prNumber, repo: repo, inReplyTo: rootCommentId,
            body: BatonMarker.autoResolvedReplyBody(reason: "the finding's anchor is outdated")
        )
        try await resolveReviewThread(threadId: thread.id)
    }

    private func postReply(prNumber: Int, repo: String, inReplyTo: Int, body: String) async throws {
        let json = try GitHubAPIBodies.json(GitHubAPIBodies.ReplyComment(body: body, in_reply_to: inReplyTo))
        let path = "/repos/\(repo)/pulls/\(prNumber)/comments"
        _ = try await api.run(["api", "--method", "POST", path, "--input", "-"], stdin: json) { result in
            Self.threadResolveError(result)
        }
    }

    /// Map a terminal reply failure: a transient is preserved, a forbidden becomes
    /// the degradable ``ForgeError/threadResolveForbidden``, anything else fails.
    static func threadResolveError(_ result: GHResult) -> ForgeError {
        if let transient = GHApiClient.transientError(result) { return transient }
        let detail = GHApiClient.errorText(result)
        let text = detail.lowercased()
        let forbidden = text.contains("403") || text.contains("422") || text.contains("forbidden")
            || text.contains("not accessible by integration") || text.contains("must have write access")
        return forbidden ? .threadResolveForbidden(detail: detail) : .publishFailed(detail: detail)
    }

    private func describe(_ error: Error) -> String {
        (error as? ForgeError)?.errorDescription ?? "\(error)"
    }
}
