import Foundation

/// Pull-request context recovered from the GitHub Actions environment.
public struct GitHubActionsContext: Sendable, Equatable {
    public var repository: String?
    public var prNumber: Int?
    public var headSHA: String?
    public var eventName: String?

    public init(
        repository: String? = nil,
        prNumber: Int? = nil,
        headSHA: String? = nil,
        eventName: String? = nil
    ) {
        self.repository = repository
        self.prNumber = prNumber
        self.headSHA = headSHA
        self.eventName = eventName
    }

    /// Whether we have enough state to be considered in PR context.
    public var isPullRequest: Bool {
        prNumber != nil
    }
}

/// Reads the GitHub Actions environment to recover PR context.
public enum GitHubEnv {
    /// Detect PR context. Returns `nil` outside of GitHub Actions.
    public static func detect(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileReader: (String) -> Data? = { try? Data(contentsOf: URL(fileURLWithPath: $0)) }
    ) -> GitHubActionsContext? {
        guard env["GITHUB_ACTIONS"] == "true" || env["GITHUB_REPOSITORY"] != nil else { return nil }

        var context = GitHubActionsContext(
            repository: env["GITHUB_REPOSITORY"],
            headSHA: env["GITHUB_SHA"],
            eventName: env["GITHUB_EVENT_NAME"]
        )

        if let path = env["GITHUB_EVENT_PATH"], let data = fileReader(path) {
            context.prNumber = parsePRNumber(from: data)
        }
        return context
    }

    /// Extract the PR number from a Github Actions `pull_request` event payload.
    static func parsePRNumber(from data: Data) -> Int? {
        guard let any = try? JSONSerialization.jsonObject(with: data),
              let object = any as? [String: Any]
        else { return nil }
        if let pr = object["pull_request"] as? [String: Any], let number = pr["number"] as? Int {
            return number
        }
        return object["number"] as? Int
    }
}
