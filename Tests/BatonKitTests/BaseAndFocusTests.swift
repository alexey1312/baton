@testable import BatonKit
import Foundation
import Testing

struct BaseAndFocusTests {
    @Test("base priority: --base flag > scope default > HEAD")
    func basePriority() {
        #expect(BaseResolver.resolve(flag: "origin/main", scopeDefault: "origin/develop") == "origin/main")
        #expect(BaseResolver.resolve(flag: nil, scopeDefault: "origin/develop") == "origin/develop")
        #expect(BaseResolver.resolve(flag: nil, scopeDefault: nil) == "HEAD")
    }

    @Test("GitHubEnv.detect returns nil outside GitHub Actions")
    func envDetectNil() {
        #expect(GitHubEnv.detect(env: [:]) == nil)
        #expect(GitHubEnv.detect(env: ["IRRELEVANT": "1"]) == nil)
    }

    @Test("GitHubEnv.detect reads repo and head from environment")
    func envDetect() throws {
        let env = [
            "GITHUB_ACTIONS": "true",
            "GITHUB_REPOSITORY": "alexey1312/swift-baton",
            "GITHUB_SHA": "abcdef",
            "GITHUB_EVENT_NAME": "pull_request",
        ]
        let ctx = try #require(GitHubEnv.detect(env: env, fileReader: { _ in nil }))
        #expect(ctx.repository == "alexey1312/swift-baton")
        #expect(ctx.headSHA == "abcdef")
        #expect(ctx.eventName == "pull_request")
        #expect(ctx.prNumber == nil)
    }

    @Test("GitHubEnv parses PR number from a pull_request event payload")
    func prNumber() {
        let payload = Data(#"{"pull_request":{"number":7},"action":"opened"}"#.utf8)
        #expect(GitHubEnv.parsePRNumber(from: payload) == 7)
        let issuesPayload = Data(#"{"number":12}"#.utf8)
        #expect(GitHubEnv.parsePRNumber(from: issuesPayload) == 12)
        #expect(GitHubEnv.parsePRNumber(from: Data("{}".utf8)) == nil)
    }
}
