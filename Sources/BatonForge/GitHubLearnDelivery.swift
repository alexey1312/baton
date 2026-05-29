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
    private let maxAttempts: Int

    public init(gh: GHRunning = LiveGHRunner(), maxAttempts: Int = 3) {
        self.gh = gh
        self.maxAttempts = maxAttempts
    }

    private var client: GHApiClient {
        GHApiClient(gh: gh, maxAttempts: maxAttempts)
    }

    public func deliver(_ request: LearnDeliveryRequest) async throws -> LearnDeliveryReport {
        let owner = String(request.repo.split(separator: "/").first ?? "")
        do {
            if let existing = try await findExistingPR(request: request, owner: owner) {
                try await updatePR(number: existing, request: request)
                return LearnDeliveryReport(outcome: .updated(existing))
            }
            let number = try await createPR(request: request)
            return LearnDeliveryReport(outcome: .created(number))
        } catch let error as ForgeError {
            guard case .writePermissionDenied = error else { throw error }
            return LearnDeliveryReport(
                outcome: .degradedToPreview,
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
        // A parse failure here must NOT look like "no existing PR" — that would make
        // delivery open a duplicate rolling PR and break the single-PR guarantee.
        let items = try LearnAPIBodies.decode([LearnAPIBodies.PRListItem].self, from: result.stdout)
        return items.first?.number
    }

    // MARK: - Write

    private func createPR(request: LearnDeliveryRequest) async throws -> Int {
        let json = try LearnAPIBodies.json(LearnAPIBodies.CreatePRRequest(
            title: request.title,
            head: request.branch,
            base: request.base ?? "main",
            body: request.body,
            draft: request.draft
        ))
        let result = try await call(method: "POST", path: "/repos/\(request.repo)/pulls", stdin: json)
        return try LearnAPIBodies.decode(LearnAPIBodies.PRResponse.self, from: result.stdout).number
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
        return try await client.run(args, stdin: stdin, mapError: Self.mapError)
    }

    /// Map a terminal failure. A 403/permission error degrades delivery to preview;
    /// a 422 (Validation Failed — e.g. "no commits between base and head") is a real
    /// error and must NOT degrade, so it falls through to publishFailed.
    static func mapError(_ result: GHResult) -> ForgeError {
        if let transient = GHApiClient.transientError(result) { return transient }
        let detail = GHApiClient.errorText(result)
        let text = detail.lowercased()
        let denied = text.contains("403") || text.contains("forbidden")
            || text.contains("not accessible by integration") || text.contains("must have write access")
        return denied ? .writePermissionDenied(detail: detail) : .publishFailed(detail: detail)
    }
}
