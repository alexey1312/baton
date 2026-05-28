/// Resolves the diff base ref using the priority `--base` > scope default > `HEAD`.
public enum BaseResolver {
    /// Apply the priority order: explicit flag > scope-default > built-in `HEAD`.
    public static func resolve(flag: String?, scopeDefault: String?) -> String {
        flag ?? scopeDefault ?? ConfigDefaults.base
    }

    /// Ensure `ref` is present in the local repository.
    public static func validate(_ ref: String, git: GitRunner) throws {
        guard git.refExists(ref) else {
            throw GitError.invalidBaseRef(ref: ref)
        }
    }
}
