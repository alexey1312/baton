import Foundation

/// Errors raised while parsing, validating, or cascading `baton.toml` files.
public enum ConfigError: BatonError {
    /// TOML syntax or a type/structure mismatch in a file.
    case malformedTOML(path: String, underlying: String)
    /// An `[agent].kind` value that is not a supported agent.
    case invalidAgentKind(path: String, value: String)
    /// Two `[[reviews]]` in one file share a `name`.
    case duplicateReviewName(path: String, name: String)
    /// Two `[[skills]]` in one file share a `name`.
    case duplicateSkillName(path: String, name: String)
    /// A review references a skill name that resolves nowhere.
    case unresolvedSkill(scope: String, review: String, skill: String)
    /// No `baton.toml` exists anywhere in the repository.
    case noConfigFound(repoRoot: String)
    /// A scope has reviews but no `[agent]` block resolvable in its chain.
    case noResolvableAgent(scope: String)
    /// A remote skill omits the required `ref` under a pinning policy.
    case remoteSkillMissingRef(scope: String, skill: String, source: String)

    public var errorDescription: String? {
        switch self {
        case let .malformedTOML(path, underlying):
            "Invalid baton.toml at \(path): \(underlying)"
        case let .invalidAgentKind(path, value):
            "Unknown agent kind '\(value)' in \(path)"
        case let .duplicateReviewName(path, name):
            "Duplicate review name '\(name)' in \(path)"
        case let .duplicateSkillName(path, name):
            "Duplicate skill name '\(name)' in \(path)"
        case let .unresolvedSkill(scope, review, skill):
            "Review '\(review)' in scope '\(scope)' references undefined skill '\(skill)'"
        case let .noConfigFound(repoRoot):
            "No baton.toml found anywhere under \(repoRoot)"
        case let .noResolvableAgent(scope):
            "Scope '\(scope)' has reviews but no resolvable [agent] block"
        case let .remoteSkillMissingRef(scope, skill, source):
            "Remote skill '\(skill)' (\(source)) in scope '\(scope)' is missing a pinned ref"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .malformedTOML:
            "Fix the TOML syntax or field types and try again."
        case .invalidAgentKind:
            "Set [agent].kind to one of: \(AgentKind.listForHelp)."
        case .duplicateReviewName:
            "Give each [[reviews]] entry a unique name within the file."
        case .duplicateSkillName:
            "Give each [[skills]] entry a unique name within the file."
        case let .unresolvedSkill(_, _, skill):
            "Declare a [[skills]] entry named '\(skill)' or correct the skill name."
        case .noConfigFound:
            "Run `baton init` to create a baton.toml."
        case let .noResolvableAgent(scope):
            "Add an [agent] block at or above the '\(scope)' scope."
        case .remoteSkillMissingRef:
            "Pin the skill to a commit SHA via `ref`, or pass --allow-unpinned."
        }
    }
}
