import BatonKit
import Foundation

/// Encodable bodies for the `gh api --input -` calls and helpers to decode the
/// subset of GitHub responses Baton needs.
enum GitHubAPIBodies {
    /// Body for `POST /repos/{owner}/{repo}/pulls/{pr}/reviews`.
    struct ReviewRequest: Encodable {
        let event: String
        let body: String
        let commit_id: String
        let comments: [ReviewComment]
    }

    /// One inline comment within a review request.
    struct ReviewComment: Encodable {
        let path: String
        let line: Int
        let side: String
        let body: String
    }

    /// Body for `POST /repos/{owner}/{repo}/check-runs`.
    struct CheckRunRequest: Encodable {
        let name: String
        let head_sha: String
        let status: String
        let conclusion: String
        let output: CheckRunOutput
    }

    /// The `output` block of a Check Run request.
    struct CheckRunOutput: Encodable {
        let title: String
        let summary: String
    }

    /// Body for `POST /repos/{owner}/{repo}/pulls/{pr}/comments` posting a reply to
    /// an existing review thread (the auto-resolve provenance marker).
    struct ReplyComment: Encodable {
        let body: String
        let in_reply_to: Int
    }

    /// Body for the GraphQL `resolveReviewThread` mutation call.
    struct GraphQLResolveThread: Encodable {
        let query: String
        let variables: Variables

        struct Variables: Encodable {
            let threadId: String
        }
    }

    /// A previously-posted review comment, as returned by
    /// `GET /repos/{owner}/{repo}/pulls/{pr}/comments`.
    struct ExistingComment: Decodable {
        let path: String?
        let line: Int?
        let body: String?
    }

    /// Encode an `Encodable` body to a compact JSON string for `gh api --input -`.
    static func json(_ value: some Encodable) throws -> String {
        let data = try JSONCodec.encode(value)
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    /// Decode the list of existing PR review comments from a `gh api` response.
    static func decodeExistingComments(_ stdout: String) -> [ExistingComment] {
        guard let data = stdout.data(using: .utf8),
              let comments = try? JSONCodec.decode([ExistingComment].self, from: data)
        else { return [] }
        return comments
    }
}
