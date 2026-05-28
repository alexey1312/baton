import BatonKit
import Foundation

/// Opens or updates the single rolling `learn` draft pull request via the injected
/// ``GHRunning``. A token lacking PR-write permission degrades the run to preview
/// (a warning, not a failure), mirroring the MVP Check Run caveat.
///
/// The `learn` branch contents are force-updated by the CLI's git step before this
/// runs; this type owns only the PR create/update decision.
public struct GitHubLearnDelivery: LearnDelivering {
    private let gh: GHRunning
    private let options: GitHubForge.Options

    public init(gh: GHRunning = LiveGHRunner(), options: GitHubForge.Options = GitHubForge.Options()) {
        self.gh = gh
        self.options = options
    }

    public func deliver(_ request: LearnDeliveryRequest) async throws -> LearnDeliveryReport {
        let owner = String(request.repo.split(separator: "/").first ?? "")
        do {
            if let existing = try await findExistingPR(request: request, owner: owner) {
                try await updatePR(number: existing, request: request)
                return LearnDeliveryReport(pullRequestNumber: existing, updated: true)
            }
            let number = try await createPR(request: request)
            return LearnDeliveryReport(pullRequestNumber: number, created: true)
        } catch let error as ForgeError {
            guard case .writePermissionDenied = error else { throw error }
            return LearnDeliveryReport(
                degradedToPreview: true,
                warnings: [
                    "The token cannot open or update the learn pull request (a write-scoped GitHub App " +
                        "token is required, e.g. the Actions GITHUB_TOKEN). Emitted preview output instead.",
                ]
            )
        }
    }

    // MARK: - Lookup

    private func findExistingPR(request: LearnDeliveryRequest, owner: String) async throws -> Int? {
        let path = "/repos/\(request.repo)/pulls?state=open&head=\(owner):\(request.branch)"
        let result = try await call(method: "GET", path: path, stdin: nil)
        let items = LearnAPIBodies.decode([LearnAPIBodies.PRListItem].self, from: result.stdout) ?? []
        return items.first?.number
    }

    // MARK: - Write

    private func createPR(request: LearnDeliveryRequest) async throws -> Int? {
        let json = try LearnAPIBodies.json(LearnAPIBodies.CreatePRRequest(
            title: request.title,
            head: request.branch,
            base: request.base ?? "main",
            body: request.body,
            draft: request.draft
        ))
        let result = try await call(method: "POST", path: "/repos/\(request.repo)/pulls", stdin: json)
        return LearnAPIBodies.decode(LearnAPIBodies.PRResponse.self, from: result.stdout)?.number
    }

    private func updatePR(number: Int, request: LearnDeliveryRequest) async throws {
        let json = try LearnAPIBodies.json(LearnAPIBodies.UpdatePRRequest(
            title: request.title, body: request.body
        ))
        _ = try await call(method: "PATCH", path: "/repos/\(request.repo)/pulls/\(number)", stdin: json)
    }

    // MARK: - gh invocation

    private func call(method: String, path: String, stdin: String?) async throws -> GHResult {
        var args = ["api", "--method", method, path]
        if stdin != nil { args += ["--input", "-"] }

        var lastError = ""
        for attempt in 1 ... max(1, options.maxAttempts) {
            let result = try await gh.run(args, stdin: stdin)
            if result.isSuccess { return result }
            lastError = ghErrorText(result)
            let mapped = mapError(result)
            if case .serverError = mapped, attempt < options.maxAttempts { continue }
            if case .rateLimited = mapped, attempt < options.maxAttempts { continue }
            throw mapped
        }
        throw ForgeError.publishFailed(detail: lastError)
    }

    private func mapError(_ result: GHResult) -> ForgeError {
        let detail = ghErrorText(result)
        let text = detail.lowercased()
        if text.contains("rate limit") || text.contains("429") { return .rateLimited(detail: detail) }
        if let status = httpStatus(text), (500 ... 599).contains(status) { return .serverError(detail: detail) }
        let denied = text.contains("403") || text.contains("422") || text.contains("forbidden")
            || text.contains("not accessible by integration") || text.contains("must have write access")
        return denied ? .writePermissionDenied(detail: detail) : .publishFailed(detail: detail)
    }

    private func ghErrorText(_ result: GHResult) -> String {
        let combined = (result.stderr + "\n" + result.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
        return combined.isEmpty ? "gh exited with status \(result.status)" : combined
    }

    private func httpStatus(_ text: String) -> Int? {
        guard let range = text.range(of: #"http (\d{3})"#, options: .regularExpression) else { return nil }
        return Int(text[range].suffix(3))
    }
}
