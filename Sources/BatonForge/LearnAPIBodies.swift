import BatonKit
import Foundation

/// Encodable request bodies and response decoders for the `learn` GitHub reads
/// (merged PRs, review-thread resolution via GraphQL, reactions via the Reactions
/// API) and the rolling-PR writes.
enum LearnAPIBodies {
    // MARK: - GraphQL: review threads + resolution

    /// The GraphQL query reading review threads, their resolution/outdated state,
    /// the resolving actor, and each thread's first comment.
    static let reviewThreadsQuery = """
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          author { login }
          reviewThreads(first: 100) {
            nodes {
              id
              isResolved
              isOutdated
              resolvedBy { login }
              comments(first: 1) {
                nodes { databaseId body path line }
              }
            }
          }
        }
      }
    }
    """

    struct ReviewThreadsRequest: Encodable {
        let query: String
        let variables: Variables

        struct Variables: Encodable {
            let owner: String
            let name: String
            let number: Int
        }

        init(owner: String, name: String, number: Int) {
            query = reviewThreadsQuery
            variables = Variables(owner: owner, name: name, number: number)
        }
    }

    // MARK: - GraphQL response decoding

    struct ThreadsResponse: Decodable {
        // GitHub returns query-level failures as HTTP 200 with a populated `errors`
        // array and null `data`, so both must be modeled to tell a real failure
        // apart from a pull request that genuinely has no review threads.
        let data: DataField?
        let errors: [GraphQLError]?

        struct GraphQLError: Decodable { let message: String }
        struct DataField: Decodable { let repository: Repository? }
        struct Repository: Decodable { let pullRequest: PullRequest? }
        struct PullRequest: Decodable {
            let author: Actor?
            let reviewThreads: ThreadConnection
        }

        struct ThreadConnection: Decodable { let nodes: [ThreadNode] }
        struct ThreadNode: Decodable {
            let id: String
            let isResolved: Bool
            let isOutdated: Bool
            let resolvedBy: Actor?
            let comments: CommentConnection
        }

        struct CommentConnection: Decodable { let nodes: [CommentNode] }
        struct CommentNode: Decodable {
            let databaseId: Int?
            let body: String?
            let path: String?
            let line: Int?
        }

        struct Actor: Decodable { let login: String }
    }

    // MARK: - REST: merged pull requests

    struct ClosedPR: Decodable {
        let number: Int
        let mergedAt: Date?
        let user: User?

        struct User: Decodable { let login: String }

        enum CodingKeys: String, CodingKey {
            case number, user
            case mergedAt = "merged_at"
        }
    }

    // MARK: - REST: reactions

    struct ReactionResponse: Decodable {
        let content: String
        let user: User?

        struct User: Decodable { let login: String }
    }

    // MARK: - REST: rolling PR write

    struct CreatePRRequest: Encodable {
        let title: String
        let head: String
        let base: String
        let body: String
        let draft: Bool
    }

    struct UpdatePRRequest: Encodable {
        let title: String
        let body: String
    }

    struct PRResponse: Decodable {
        let number: Int
    }

    struct PRListItem: Decodable {
        let number: Int
    }

    // MARK: - Encoding / decoding helpers

    static func json(_ value: some Encodable) throws -> String {
        let data = try JSONCodec.encode(value)
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    /// Decode a `gh` JSON response, raising ``ForgeError`` when the payload cannot
    /// be parsed. `gh` exiting 0 does not guarantee a well-formed body (e.g. a
    /// truncated response or a drifted schema), so a parse failure must surface
    /// rather than be silently treated as "no data".
    static func decode<T: Decodable>(_ type: T.Type, from stdout: String) throws -> T {
        guard let data = stdout.data(using: .utf8) else {
            throw ForgeError.publishFailed(detail: "gh returned non-UTF-8 output")
        }
        do {
            return try JSONCodec.decodeWithISO8601Date(type, from: data)
        } catch {
            throw ForgeError.publishFailed(detail: "could not parse the gh JSON response: \(error)")
        }
    }
}
