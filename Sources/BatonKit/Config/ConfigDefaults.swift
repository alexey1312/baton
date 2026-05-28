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
    /// Per-skill byte budget for inlined supporting markdown (1 MiB) when
    /// `[security].references_budget_kb` is unset.
    public static let referencesBudgetBytes = 1024 * 1024
    /// Days of merged-PR history `learn` scans when `[learn].lookback_days` is unset.
    public static let learnLookbackDays = 14
    /// Minimum attributed-thread volume a scope needs before `learn` proposes edits.
    public static let learnMinSignal = 1
    /// Whether `learn` runs for a scope when `[learn].enabled` is unset anywhere in the chain.
    public static let learnEnabled = true
    /// Branch the rolling `learn` pull request lives on when `[learn].branch` is unset.
    public static let learnBranch = "learn"
    /// Whether the rolling `learn` pull request opens as a draft when `[learn].draft` is unset.
    public static let learnDraft = true
}
