/// A discovered scope: a subtree owning a `baton.toml`.
public struct ScopeConfig: Sendable, Equatable {
    /// Repo-relative scope root (`""` for the repository root).
    public var path: String
    /// Repo-relative path to this scope's `baton.toml`.
    public var configPath: String
    /// The parsed config for this scope.
    public var config: BatonConfig
    /// Skills auto-discovered under this scope's `.baton/skills/`.
    public var autoSkills: [SkillConfig]

    public init(path: String, configPath: String, config: BatonConfig, autoSkills: [SkillConfig] = []) {
        self.path = path
        self.configPath = configPath
        self.config = config
        self.autoSkills = autoSkills
    }

    /// Whether this scope's root is an ancestor of (or equal to) `other`'s path.
    public func isAncestorOrSelf(of other: String) -> Bool {
        if path.isEmpty { return true } // repository root owns everything
        return other == path || other.hasPrefix(path + "/")
    }

    /// Depth of the scope root (number of path components; root is 0).
    public var depth: Int {
        path.isEmpty ? 0 : path.split(separator: "/").count
    }
}
