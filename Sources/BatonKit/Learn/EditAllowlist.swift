import Foundation

/// One edit the agent proposed: a repo-relative path and its new contents
/// (`nil` contents means a deletion). `summary` is optional human-readable text.
public struct ProposedEdit: Sendable, Equatable {
    public var path: String
    public var newContents: String?
    public var summary: String?

    public init(path: String, newContents: String?, summary: String? = nil) {
        self.path = path
        self.newContents = newContents
        self.summary = summary
    }
}

/// Enforces the review-setup edit allowlist by inspecting the paths the agent
/// actually changed. Edits are restricted to: a scope's own `baton.toml`, local
/// skill directories (`.baton/skills/**` and any local `[[skills]]` source dir),
/// and agent-facing docs. Source code, tests, CI workflows, and dependency
/// manifests are refused. The guard never trusts a self-reported proposal — it
/// drops any changed path outside the allowlist.
public struct EditAllowlist: Sendable {
    /// Repo-relative scope root (`""` for the repository root).
    public let scopePath: String
    /// Repo-relative local skill directories the scope may edit.
    public let localSkillDirs: [String]

    /// Agent-facing doc filenames editable anywhere within a scope.
    private static let agentDocNames: Set<String> = [
        "AGENTS.md", "CLAUDE.md", "GEMINI.md", "OPENCODE.md", "AGENT.md",
    ]

    public init(scopePath: String, localSkillDirs: [String] = []) {
        self.scopePath = scopePath
        self.localSkillDirs = localSkillDirs.map(Self.normalize)
    }

    /// Whether `path` (repo-relative) is an allowed review-setup edit for the scope.
    public func isAllowed(_ path: String) -> Bool {
        let clean = Self.normalize(path)
        guard withinScope(clean) else { return false }
        if Self.lastComponent(clean) == "baton.toml" { return true }
        if Self.agentDocNames.contains(Self.lastComponent(clean)) { return true }
        if isInLocalSkillDir(clean) { return true }
        return false
    }

    /// Filter `edits` to the allowed subset, dropping any out-of-allowlist path.
    public func filter(_ edits: [ProposedEdit]) -> [ProposedEdit] {
        edits.filter { isAllowed($0.path) }
    }

    // MARK: - Helpers

    private func withinScope(_ path: String) -> Bool {
        guard !scopePath.isEmpty else { return true } // root owns everything
        return path == scopePath || path.hasPrefix(scopePath + "/")
    }

    private func isInLocalSkillDir(_ path: String) -> Bool {
        for dir in localSkillDirs where path == dir || path.hasPrefix(dir + "/") {
            return true
        }
        return false
    }

    private static func lastComponent(_ path: String) -> String {
        String(path.split(separator: "/").last ?? "")
    }

    /// Normalize a path: trim a leading `./`, collapse redundant slashes, strip a
    /// trailing slash. Keeps comparisons stable across how sources are declared.
    private static func normalize(_ path: String) -> String {
        var result = path
        while result.hasPrefix("./") {
            result.removeFirst(2)
        }
        while result.hasPrefix("/") {
            result.removeFirst()
        }
        while result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}
