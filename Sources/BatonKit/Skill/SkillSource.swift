import Foundation

/// Classifies a ``SkillConfig/source`` string into a local path or a remote reference.
///
/// - Local sources begin with `./`, `../`, `/`, or `~` and resolve against the
///   directory of the declaring `baton.toml`.
/// - Remote sources are `owner/repo` or `owner/repo/skill` references (the
///   `owner/repo/skill` form follows the skills.sh convention).
public enum SkillSource: Sendable, Equatable {
    /// The classified kind of a skill source.
    public enum Kind: Sendable, Equatable {
        /// A local filesystem path (relative to the declaring config, or absolute/tilde).
        case local(path: String)
        /// A remote repository reference.
        ///
        /// - `owner`/`repo` identify the repository.
        /// - `skill` is the trailing skills.sh segment (`owner/repo/skill`), if present.
        case remote(owner: String, repo: String, skill: String?)
    }

    /// Classify `source` into a ``Kind``.
    public static func classify(_ source: String) -> Kind {
        let trimmed = source.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("./")
            || trimmed.hasPrefix("../")
            || trimmed.hasPrefix("/")
            || trimmed.hasPrefix("~")
        {
            return .local(path: trimmed)
        }

        // Remote: split on "/". owner/repo (2 segments) or owner/repo/skill (3+).
        let segments = trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if segments.count >= 3 {
            let owner = segments[0]
            let repo = segments[1]
            // skills.sh skill name is the third segment.
            let skill = segments[2]
            return .remote(owner: owner, repo: repo, skill: skill.isEmpty ? nil : skill)
        }
        if segments.count == 2 {
            return .remote(owner: segments[0], repo: segments[1], skill: nil)
        }
        // A bare token with no slash is treated as a (degenerate) local path so the
        // resolver surfaces a clear missing-file error rather than a malformed clone.
        return .local(path: trimmed)
    }
}
