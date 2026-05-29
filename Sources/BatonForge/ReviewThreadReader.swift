import BatonKit
import Foundation

/// Reads a pull request's review threads — resolution/outdated state, the resolving
/// actor, and each thread's comments — via one GraphQL call.
///
/// Shared by `publish` auto-resolution (``GitHubForge``) and `learn` signal
/// collection (``GitHubLearnForge``) so the query, decoder, and comment paging live
/// in one place. All GitHub access goes through the injected ``GHRunning`` so the
/// read stays unit-testable with a recording mock.
struct ReviewThreadReader {
    private let gh: GHRunning
    private let maxAttempts: Int

    init(gh: GHRunning, maxAttempts: Int = 3) {
        self.gh = gh
        self.maxAttempts = maxAttempts
    }

    /// The decoded pull-request payload (author + review threads).
    ///
    /// - Throws: ``ForgeError`` on transport, parse, or GraphQL-level failure.
    func pullRequest(owner: String, name: String, number: Int) async throws -> ThreadsResponse.PullRequest {
        let body = try LearnAPIBodies.json(ReviewThreadsRequest(owner: owner, name: name, number: number))
        let result = try await GHApiClient(gh: gh, maxAttempts: maxAttempts)
            .run(["api", "graphql", "--input", "-"], stdin: body) { result in
                // A thread read has no degrade path: any terminal failure is hard.
                GHApiClient.transientError(result) ?? .publishFailed(detail: GHApiClient.errorText(result))
            }
        let decoded = try LearnAPIBodies.decode(ThreadsResponse.self, from: result.stdout)
        if let errors = decoded.errors, !errors.isEmpty {
            throw ForgeError.publishFailed(
                detail: "GitHub GraphQL error: " + errors.map(\.message).joined(separator: "; ")
            )
        }
        guard let pr = decoded.data?.repository?.pullRequest else {
            throw ForgeError.publishFailed(detail: "GitHub GraphQL response omitted the pull request payload")
        }
        return pr
    }

    // MARK: - GraphQL query

    /// Reads review threads, their resolution/outdated state, the resolving actor,
    /// and each thread's comments. Comments are paged to 100 — Baton threads are
    /// small (a finding plus a few replies), so this comfortably covers the
    /// `<!-- baton:auto-resolved -->` marker scan.
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
              comments(first: 100) {
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
}

extension ReviewThreadReader.ThreadsResponse.ThreadNode {
    /// Whether any of this thread's comments contains `marker`.
    func hasComment(containing marker: String) -> Bool {
        comments.nodes.contains { ($0.body ?? "").contains(marker) }
    }
}
