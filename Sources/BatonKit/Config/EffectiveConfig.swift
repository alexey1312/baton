/// Where an effective configuration value came from.
public enum ProvenanceSource: Equatable, Sendable, CustomStringConvertible {
    /// A specific `baton.toml` file (repo-relative path).
    case file(String)
    /// A built-in default (no `baton.toml` set this value).
    case builtinDefault
    /// Auto-discovered under a scope's `.baton/skills/`.
    case autoDiscovered(String)

    public var description: String {
        switch self {
        case let .file(path): path
        case .builtinDefault: "(default)"
        case let .autoDiscovered(path): "\(path) (auto-discovered)"
        }
    }
}

/// Records, per effective value, the source it was resolved from.
///
/// Keys are dotted field identifiers, e.g. `agent`, `defaults.fail_on`,
/// `skills.owasp`, `reviews.security`.
public struct ConfigProvenance: Equatable, Sendable {
    public var entries: [String: ProvenanceSource]

    public init(_ entries: [String: ProvenanceSource] = [:]) {
        self.entries = entries
    }

    public mutating func record(_ key: String, _ source: ProvenanceSource) {
        entries[key] = source
    }

    /// The source of a value, defaulting to the built-in default.
    public func source(for key: String) -> ProvenanceSource {
        entries[key] ?? .builtinDefault
    }
}

/// The fully resolved `[defaults]` values for a scope (no optionals).
public struct EffectiveDefaults: Equatable, Sendable {
    public var base: String
    public var failOn: Severity
    public var maxConcurrency: Int
    public var diffBudget: Int
    public var chunkStrategy: ChunkStrategy
    public var timeout: Int

    public init(
        base: String = ConfigDefaults.base,
        failOn: Severity = ConfigDefaults.failOn,
        maxConcurrency: Int = ConfigDefaults.maxConcurrency,
        diffBudget: Int = ConfigDefaults.diffBudget,
        chunkStrategy: ChunkStrategy = ConfigDefaults.chunkStrategy,
        timeout: Int = ConfigDefaults.timeout
    ) {
        self.base = base
        self.failOn = failOn
        self.maxConcurrency = maxConcurrency
        self.diffBudget = diffBudget
        self.chunkStrategy = chunkStrategy
        self.timeout = timeout
    }
}

/// The fully resolved `[learn]` values for a scope.
///
/// Analysis fields (``lookbackDays``, ``minSignal``, ``enabled``) are resolved
/// closest-wins from the scope's chain; delivery fields are resolved only from the
/// repository-root scope (one rolling PR per repository).
public struct EffectiveLearn: Equatable, Sendable {
    // Analysis (cascading).
    public var lookbackDays: Int
    public var minSignal: Int
    public var enabled: Bool
    // Delivery (root-only).
    public var branch: String
    public var base: String?
    public var reviewers: [String]
    public var teamReviewers: [String]
    public var labels: [String]
    public var draft: Bool

    public init(
        lookbackDays: Int = ConfigDefaults.learnLookbackDays,
        minSignal: Int = ConfigDefaults.learnMinSignal,
        enabled: Bool = ConfigDefaults.learnEnabled,
        branch: String = ConfigDefaults.learnBranch,
        base: String? = nil,
        reviewers: [String] = [],
        teamReviewers: [String] = [],
        labels: [String] = [],
        draft: Bool = ConfigDefaults.learnDraft
    ) {
        self.lookbackDays = lookbackDays
        self.minSignal = minSignal
        self.enabled = enabled
        self.branch = branch
        self.base = base
        self.reviewers = reviewers
        self.teamReviewers = teamReviewers
        self.labels = labels
        self.draft = draft
    }
}

/// The fully resolved `[publish]` values, read only from the repository-root
/// scope (one publish per pull request).
public struct EffectivePublish: Equatable, Sendable {
    public var resolveOutdatedThreads: Bool

    public init(resolveOutdatedThreads: Bool = ConfigDefaults.resolveOutdatedThreads) {
        self.resolveOutdatedThreads = resolveOutdatedThreads
    }
}

/// The fully resolved `[render]` values, read only from the repository-root scope.
/// `nil` template paths mean the bundled default is used.
public struct EffectiveRender: Equatable, Sendable {
    public var markdownTemplate: String?
    public var learnPrBodyTemplate: String?

    public init(markdownTemplate: String? = nil, learnPrBodyTemplate: String? = nil) {
        self.markdownTemplate = markdownTemplate
        self.learnPrBodyTemplate = learnPrBodyTemplate
    }
}

/// The effective configuration computed for a single scope after the cascade.
public struct EffectiveConfig: Sendable {
    /// Repo-relative scope root (`""` for the repository root).
    public var scopePath: String
    /// Resolved `[agent]` block (closest-wins as a whole block), if any.
    public var agent: AgentConfig?
    /// Resolved defaults.
    public var defaults: EffectiveDefaults
    /// Resolved skills (auto-discovered prepended, closest-wins by name).
    public var skills: [SkillConfig]
    /// Repo-relative directory of the `baton.toml` that declared each resolved
    /// skill, keyed by skill name. A skill inherited from an ancestor scope keeps
    /// the ancestor's directory so its relative local `source` resolves there, not
    /// against a descendant consuming scope.
    public var skillDeclaringDirs: [String: String]
    /// Resolved reviews (inherited, override/disable applied).
    public var reviews: [ReviewConfig]
    /// Repo-relative directory of the `baton.toml` that declared each resolved
    /// review, keyed by review name. Used to anchor a relative `prompt_file` to the
    /// declaring scope rather than a descendant consuming scope.
    public var reviewDeclaringDirs: [String: String]
    /// Root-only security policy.
    public var security: SecurityConfig?
    /// Resolved `[learn]` block (analysis cascades, delivery root-only).
    public var learn: EffectiveLearn
    /// Resolved `[publish]` block (root-only).
    public var publish: EffectivePublish
    /// Resolved `[render]` block (root-only).
    public var render: EffectiveRender
    /// Provenance for `config --explain`.
    public var provenance: ConfigProvenance

    public init(
        scopePath: String,
        agent: AgentConfig?,
        defaults: EffectiveDefaults,
        skills: [SkillConfig],
        reviews: [ReviewConfig],
        security: SecurityConfig?,
        learn: EffectiveLearn = EffectiveLearn(),
        publish: EffectivePublish = EffectivePublish(),
        render: EffectiveRender = EffectiveRender(),
        skillDeclaringDirs: [String: String] = [:],
        reviewDeclaringDirs: [String: String] = [:],
        provenance: ConfigProvenance
    ) {
        self.scopePath = scopePath
        self.agent = agent
        self.defaults = defaults
        self.skills = skills
        self.reviews = reviews
        self.security = security
        self.learn = learn
        self.publish = publish
        self.render = render
        self.skillDeclaringDirs = skillDeclaringDirs
        self.reviewDeclaringDirs = reviewDeclaringDirs
        self.provenance = provenance
    }

    /// The effective `require_pinned_skills` policy (root security, default `true`).
    public var requirePinnedSkills: Bool {
        security?.requirePinnedSkills ?? ConfigDefaults.requirePinnedSkills
    }

    /// The effective per-skill references byte budget: root security
    /// `references_budget_kb` converted to bytes, else ``ConfigDefaults/referencesBudgetBytes``.
    public var referencesBudgetBytes: Int {
        (security?.referencesBudgetKb).map { $0 * 1024 } ?? ConfigDefaults.referencesBudgetBytes
    }
}
