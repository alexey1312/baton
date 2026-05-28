/// Routes a collected diff to scopes and (within a scope) to reviews.
public enum DiffRouter {
    /// The scope that owns `path` (deepest ancestor); `nil` if outside any scope.
    public static func owner(of path: String, scopes: [ScopeConfig]) -> ScopeConfig? {
        scopes
            .filter { $0.isAncestorOrSelf(of: path) }
            .max { $0.depth < $1.depth }
    }

    /// Partition `diff` per scope by ownership; files outside any scope are dropped.
    /// Returns a dictionary keyed by `scope.path` ( `""` for the root scope).
    public static func group(_ diff: RepoDiff, scopes: [ScopeConfig]) -> [String: [FileChange]] {
        var groups: [String: [FileChange]] = [:]
        for file in diff.files {
            guard let owner = owner(of: file.path, scopes: scopes) else { continue }
            groups[owner.path, default: []].append(file)
        }
        return groups
    }

    /// Filter `files` to those matching a review's `glob`. `nil` or empty `glob`
    /// disables filtering (every file passes).
    public static func filter(_ files: [FileChange], glob: [String]?) -> [FileChange] {
        guard let glob, !glob.isEmpty else { return files }
        return files.filter { Glob.matchesAny(glob, path: $0.path) }
    }
}
