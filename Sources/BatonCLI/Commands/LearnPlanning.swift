import BatonKit
import Foundation

/// Builds the per-scope ``LearnScopePlan`` list (effective config + allowlisted
/// local skill directories) from a repository's discovered scopes.
enum LearnPlanning {
    static func plans(discovery: DiscoveryResult, repoRoot: URL) throws -> [LearnScopePlan] {
        try discovery.scopes
            .sorted { $0.depth < $1.depth }
            .map { scope in
                let effective = try Cascade.effective(for: scope, in: discovery.scopes)
                return LearnScopePlan(
                    scope: scope,
                    effective: effective,
                    configDir: repoRoot.appendingPathComponent(scope.path, isDirectory: true),
                    localSkillDirs: localSkillDirs(scope: scope, effective: effective)
                )
            }
    }

    /// Repo-relative directories the scope may edit: its own `.baton/skills` plus
    /// any local `[[skills]]` source directory. Absolute, `~`, and `..`-traversing
    /// sources are rejected so the allowlist only ever widens within the repo.
    static func localSkillDirs(scope: ScopeConfig, effective: EffectiveConfig) -> [String] {
        var dirs = [join(scope.path, ".baton/skills")]
        for skill in effective.skills {
            guard case let .local(path) = SkillSource.classify(skill.source) else { continue }
            let clean = strip(path)
            guard !path.hasPrefix("/"), !path.hasPrefix("~"), !clean.split(separator: "/").contains("..") else {
                continue
            }
            dirs.append(join(scope.path, clean))
        }
        return Array(Set(dirs))
    }

    private static func join(_ scopePath: String, _ rel: String) -> String {
        let clean = strip(rel)
        return scopePath.isEmpty ? clean : "\(scopePath)/\(clean)"
    }

    private static func strip(_ path: String) -> String {
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
