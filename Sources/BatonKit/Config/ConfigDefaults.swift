/// Built-in default values applied when a field is unset everywhere in the chain.
public enum ConfigDefaults {
    /// Diff base when none is configured (`HEAD`).
    public static let base = "HEAD"
    /// Severity threshold that fails a review locally.
    public static let failOn: Severity = .high
    /// Concurrent `(scope, review)` tasks.
    public static let maxConcurrency = 4
    /// Bytes per scope before structural chunking.
    public static let diffBudget = 120_000
    /// How an oversized diff is split.
    public static let chunkStrategy: ChunkStrategy = .byFile
    /// Seconds allowed per agent invocation.
    public static let timeout = 600
    /// Agent material context.
    public static let context: ReviewContext = .diff
    /// Whether remote skills must be SHA-pinned.
    public static let requirePinnedSkills = true
}
