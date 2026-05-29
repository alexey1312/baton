import BatonKit
import Foundation

/// Renders a saved run record into local or GitHub-shaped output, purely from the
/// on-disk artifacts (never re-invoking an agent).
enum Renderer {
    /// Render `run` in `format`. `headSHA` is required for `github-review` and
    /// `check-run`; `useColors` applies only to the `terminal` format.
    /// A resolved report template: its source and the path it came from (for errors).
    typealias Template = (source: String, path: String)

    static func render(
        run: LoadedRun,
        format: RenderFormat,
        headSHA: String?,
        useColors: Bool = false,
        markdownTemplate: Template? = nil
    ) throws -> String {
        if format.requiresHeadSHA, (headSHA ?? "").isEmpty {
            throw RenderError.headSHARequired(format: format.rawValue)
        }
        switch format {
        case .terminal: return terminal(run, useColors: useColors)
        case .markdown: return try markdown(run, template: markdownTemplate)
        case .json: return try json(run)
        case .githubReview: return try githubReview(run, headSHA: headSHA ?? "")
        case .checkRun: return try checkRun(run, headSHA: headSHA ?? "")
        case .githubSummary: return githubSummary(run)
        }
    }

    // MARK: - Local formats

    private static func terminal(_ run: LoadedRun, useColors: Bool) -> String {
        let findings = run.results.flatMap(\.findings)
        let failures = run.results.filter(\.taskFailed)
        if findings.isEmpty, failures.isEmpty {
            return NooraUI.success("No findings.", useColors: useColors)
        }
        var lines: [String] = []
        for result in failures {
            let detail = result.errorMessage ?? "review failed"
            lines.append(NooraUI.error(
                "\(displayScope(result.scope)) / \(result.review) — \(detail)",
                useColors: useColors
            ))
        }
        for result in run.results where !result.findings.isEmpty {
            lines.append(scopeReviewHeader(result, useColors: useColors))
            for finding in result.findings {
                let location = finding.line.map { ":\($0)" } ?? ""
                let header = "  \(finding.severity.badge) \(finding.file)\(location) — \(finding.title)"
                lines.append(useColors ? NooraUI.info(header, useColors: true) : header)
                if !finding.body.isEmpty {
                    lines.append("      \(finding.body)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Renders the markdown report from a Jinja template — the user override when set,
    /// otherwise the bundled default (which reproduces the prior built-in output).
    private static func markdown(_ run: LoadedRun, template: Template?) throws -> String {
        let context = try TemplateContext.run(run)
        return try ReportTemplating.render(
            template: template?.source ?? DefaultTemplates.markdown,
            context: context,
            path: template?.path
        )
    }

    private static func json(_ run: LoadedRun) throws -> String {
        struct Payload: Encodable {
            var base: String
            var headSHA: String
            var results: [ReviewTaskResult]
            enum CodingKeys: String, CodingKey {
                case base
                case headSHA = "head_sha"
                case results
            }
        }
        let payload = Payload(base: run.manifest.base, headSHA: run.manifest.headSHA, results: run.results)
        return try String(bytes: JSONCodec.encodePrettySorted(payload), encoding: .utf8) ?? ""
    }

    // MARK: - GitHub formats

    private static func githubReview(_ run: LoadedRun, headSHA: String) throws -> String {
        struct Payload: Encodable {
            var event = "COMMENT"
            var body: String
            var comments: [InlineComment]
        }
        let comments = run.results.flatMap(\.findings).compactMap { finding -> InlineComment? in
            guard let line = finding.line else { return nil }
            return InlineComment(path: finding.file, line: line, body: GitHubPresentation.inlineCommentBody(finding))
        }
        let payload = Payload(body: BatonMarker.lastReviewed(headSHA), comments: comments)
        return try String(bytes: JSONCodec.encodePretty(payload), encoding: .utf8) ?? ""
    }

    private static func checkRun(_ run: LoadedRun, headSHA: String) throws -> String {
        struct CheckRun: Encodable {
            var name: String
            var headSHA: String
            var conclusion: String
            var summary: String
            enum CodingKeys: String, CodingKey {
                case name
                case headSHA = "head_sha"
                case conclusion
                case summary
            }
        }
        struct Payload: Encodable { var checkRuns: [CheckRun] }
        let runs = run.results.map { result in
            CheckRun(
                name: "baton: \(displayScope(result.scope))/\(result.review)",
                headSHA: headSHA,
                conclusion: GitHubPresentation.conclusion(for: result.findings).rawValue,
                summary: GitHubPresentation.summaryBody(
                    scope: result.scope,
                    review: result.review,
                    findings: result.findings
                )
            )
        }
        return try String(bytes: JSONCodec.encodePretty(Payload(checkRuns: runs)), encoding: .utf8) ?? ""
    }

    private static func githubSummary(_ run: LoadedRun) -> String {
        if run.results.isEmpty {
            return "## Baton review\n\nNo findings. ✅\n\n\(BatonMarker.finding)"
        }
        return run.results
            .map { GitHubPresentation.summaryBody(scope: $0.scope, review: $0.review, findings: $0.findings) }
            .joined(separator: "\n\n")
    }

    // MARK: - Helpers

    private static func displayScope(_ scope: String) -> String {
        scope.isEmpty ? "(root)" : scope
    }

    private static func scopeReviewHeader(_ result: ReviewTaskResult, useColors: Bool) -> String {
        let text = "\(displayScope(result.scope)) / \(result.review)"
        return useColors ? NooraUI.info(text, useColors: true) : text
    }
}
