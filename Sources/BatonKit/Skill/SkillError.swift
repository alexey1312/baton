import Foundation

/// Errors raised while resolving a `[[skills]]` declaration into an instruction bundle.
///
/// Every case conforms to ``BatonError`` and carries an actionable
/// ``recoverySuggestion`` so the CLI can render `✗ <description>` / `  → <recovery>`.
public enum SkillError: BatonError {
    /// Neither `SKILL.md` nor `README.md` was found at the resolved skill directory.
    case missingSkillFile(name: String, searchedPath: String)
    /// `git` is not available on `PATH` and a remote skill must be cloned.
    case gitUnavailable(name: String)
    /// The shallow clone of a remote skill repository failed.
    case cloneFailed(name: String, source: String, underlying: String)
    /// The pinned commit `ref` (SHA) does not exist in the cloned repository.
    case refNotFound(name: String, source: String, ref: String)
    /// The resolved `subpath` (or skills.sh lookup path) is absent in the repository.
    case subpathMissing(name: String, source: String, expectedPath: String)
    /// A skill path resolves, via a symlink, to a location outside its skill directory.
    case symlinkEscape(name: String, path: String)
    /// A remote skill omits a required `ref` while pin enforcement is in effect.
    case missingRequiredRef(name: String, source: String)
    /// A remote skill's `ref` is present but not a full commit SHA (e.g. a mutable
    /// branch or tag), so the audited-bytes guarantee would not hold.
    case refNotPinned(name: String, source: String, ref: String)
    /// A remote `source` does not match any pattern in `allowed_skill_sources`.
    case sourceNotAllowed(name: String, source: String, allowlist: [String])
    /// The resolved skill directory could not be enumerated (race, permission denial,
    /// directory replaced after `SKILL.md` lookup succeeded).
    case skillDirectoryUnreadable(name: String, path: String)
    /// A supporting reference file under the skill directory could not be read
    /// (encoding, permissions, mid-walk I/O failure). Carries the original error.
    case referenceReadFailed(name: String, path: String, underlying: String)
    /// The cumulative size of inlined reference files exceeds the per-skill budget.
    /// Authors should narrow the skill source via `subpath` or split the bundle.
    case referencesBudgetExceeded(name: String, limitBytes: Int)

    public var errorDescription: String? {
        switch self {
        case let .missingSkillFile(name, searchedPath):
            "Skill '\(name)' has no SKILL.md or README.md at \(searchedPath)"
        case let .gitUnavailable(name):
            "git is required to clone remote skill '\(name)' but was not found on PATH"
        case let .cloneFailed(name, source, underlying):
            "Failed to clone remote skill '\(name)' from \(source): \(underlying)"
        case let .refNotFound(name, source, ref):
            "Pinned ref '\(ref)' for skill '\(name)' (\(source)) was not found in the repository"
        case let .subpathMissing(name, source, expectedPath):
            "Skill '\(name)' (\(source)) has no directory at \(expectedPath)"
        case let .symlinkEscape(name, path):
            "Skill '\(name)' resolves via a symlink to \(path), which is outside its skill directory" +
                " or has no existing target"
        case let .missingRequiredRef(name, source):
            "Remote skill '\(name)' (\(source)) is missing a pinned commit ref"
        case let .refNotPinned(name, source, ref):
            "Remote skill '\(name)' (\(source)) ref '\(ref)' is not a full commit SHA"
        case let .sourceNotAllowed(name, source, _):
            "Remote skill '\(name)' source '\(source)' is not in allowed_skill_sources"
        case let .skillDirectoryUnreadable(name, path):
            "Skill '\(name)' directory at \(path) could not be enumerated"
        case let .referenceReadFailed(name, path, underlying):
            "Skill '\(name)' reference file \(path) could not be read: \(underlying)"
        case let .referencesBudgetExceeded(name, limitBytes):
            "Skill '\(name)' inlined references exceed the \(limitBytes)-byte budget"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case let .missingSkillFile(_, searchedPath):
            "Add a SKILL.md or README.md at \(searchedPath)."
        case .gitUnavailable:
            "Install git and ensure it is on your PATH."
        case .cloneFailed:
            "Check the skill `source` and verify your network connectivity."
        case .refNotFound:
            "Verify the commit SHA in `ref` exists on the remote."
        case let .subpathMissing(_, _, expectedPath):
            "Correct the `subpath` or `source`; expected a directory at \(expectedPath)."
        case .symlinkEscape:
            "Remove the escaping symlink or point the skill at a path within its skill directory."
        case .missingRequiredRef:
            "Pin the skill to a commit SHA via `ref`, or pass --allow-unpinned."
        case .refNotPinned:
            "Use a full 40- or 64-character commit SHA in `ref` (not a branch or tag), or pass --allow-unpinned."
        case let .sourceNotAllowed(_, _, allowlist):
            "Add the source to allowed_skill_sources (currently: \(allowlist.joined(separator: ", ")))."
        case .skillDirectoryUnreadable:
            "Ensure the skill directory exists and is readable; rerun once the underlying issue is resolved."
        case .referenceReadFailed:
            "Ensure the file exists, is UTF-8 encoded, and is readable by the current user."
        case .referencesBudgetExceeded:
            "Raise `references_budget_kb` in [security], narrow the skill source with `subpath`," +
                " drop unused references, or split the bundle."
        }
    }
}
