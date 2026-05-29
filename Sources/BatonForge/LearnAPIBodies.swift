import BatonKit
import Foundation

/// Encodable request bodies and response decoders for the `learn` GitHub reads
/// (merged PRs, review-thread resolution via GraphQL, reactions via the Reactions
/// API) and the rolling-PR writes.
enum LearnAPIBodies {
    // The review-threads GraphQL query, request, and decoder now live in
    // ``ReviewThreadReader`` (shared by publish auto-resolution and learn signal).

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
