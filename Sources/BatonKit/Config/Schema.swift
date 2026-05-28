/// The raw, as-declared contents of a single `baton.toml` file.
///
/// This is the decode target for `swift-toml`. All sections are optional so that a
/// scope may declare only the parts it overrides; the cascade (see `Cascade`)
/// combines these raw configs into an ``EffectiveConfig``.
public struct BatonConfig: Codable, Equatable, Sendable {
    public var agent: AgentConfig?
    public var defaults: DefaultsConfig?
    public var skills: [SkillConfig]?
    public var reviews: [ReviewConfig]?
    public var disabledReviews: [String]?
    public var security: SecurityConfig?
    public var learn: LearnConfig?

    public init(
        agent: AgentConfig? = nil,
        defaults: DefaultsConfig? = nil,
        skills: [SkillConfig]? = nil,
        reviews: [ReviewConfig]? = nil,
        disabledReviews: [String]? = nil,
        security: SecurityConfig? = nil,
        learn: LearnConfig? = nil
    ) {
        self.agent = agent
        self.defaults = defaults
        self.skills = skills
        self.reviews = reviews
        self.disabledReviews = disabledReviews
        self.security = security
        self.learn = learn
    }

    enum CodingKeys: String, CodingKey {
        case agent, defaults, skills, reviews, security, learn
        case disabledReviews = "disabled_reviews"
    }
}

/// Where an agent looks for material: only the diff, or a repository copy.
public enum ReviewContext: String, Codable, Sendable {
    case diff
    case repo
}

/// How an oversized scope diff is split before review.
public enum ChunkStrategy: String, Codable, Sendable {
    case byFile = "by-file"
    case byHunk = "by-hunk"
}

/// The `[agent]` block. Inherited closest-wins as a whole block.
public struct AgentConfig: Codable, Equatable, Sendable {
    public var kind: AgentKind
    public var model: String?
    public var binary: String?
    public var args: [String]?
    public var context: ReviewContext?
    /// Run the CLI hermetically (ignore the user's global MCP/extensions/plugins).
    /// Defaults to ``ConfigDefaults/sandbox`` when unset.
    public var sandbox: Bool?

    public init(
        kind: AgentKind,
        model: String? = nil,
        binary: String? = nil,
        args: [String]? = nil,
        context: ReviewContext? = nil,
        sandbox: Bool? = nil
    ) {
        self.kind = kind
        self.model = model
        self.binary = binary
        self.args = args
        self.context = context
        self.sandbox = sandbox
    }
}

/// The `[defaults]` block. Merged field-by-field, closest-wins.
public struct DefaultsConfig: Codable, Equatable, Sendable {
    public var base: String?
    public var failOn: Severity?
    public var maxConcurrency: Int?
    public var diffBudget: Int?
    public var chunkStrategy: ChunkStrategy?
    public var timeout: Int?

    public init(
        base: String? = nil,
        failOn: Severity? = nil,
        maxConcurrency: Int? = nil,
        diffBudget: Int? = nil,
        chunkStrategy: ChunkStrategy? = nil,
        timeout: Int? = nil
    ) {
        self.base = base
        self.failOn = failOn
        self.maxConcurrency = maxConcurrency
        self.diffBudget = diffBudget
        self.chunkStrategy = chunkStrategy
        self.timeout = timeout
    }

    enum CodingKeys: String, CodingKey {
        case base, timeout
        case failOn = "fail_on"
        case maxConcurrency = "max_concurrency"
        case diffBudget = "diff_budget"
        case chunkStrategy = "chunk_strategy"
    }
}

/// A `[[skills]]` entry. Union across the chain; closest-wins by `name`.
public struct SkillConfig: Codable, Equatable, Sendable {
    public var name: String
    public var source: String
    public var ref: String?
    public var subpath: String?

    public init(name: String, source: String, ref: String? = nil, subpath: String? = nil) {
        self.name = name
        self.source = source
        self.ref = ref
        self.subpath = subpath
    }
}

/// A `[[reviews]]` entry. Inherited down the chain; same `name` overrides.
public struct ReviewConfig: Codable, Equatable, Sendable {
    public var name: String
    public var skills: [String]?
    public var glob: [String]?
    public var failOn: Severity?
    public var context: ReviewContext?
    public var prompt: String?
    public var promptFile: String?

    public init(
        name: String,
        skills: [String]? = nil,
        glob: [String]? = nil,
        failOn: Severity? = nil,
        context: ReviewContext? = nil,
        prompt: String? = nil,
        promptFile: String? = nil
    ) {
        self.name = name
        self.skills = skills
        self.glob = glob
        self.failOn = failOn
        self.context = context
        self.prompt = prompt
        self.promptFile = promptFile
    }

    enum CodingKeys: String, CodingKey {
        case name, skills, glob, context, prompt
        case failOn = "fail_on"
        case promptFile = "prompt_file"
    }
}

/// The `[security]` block. Honored only at the repository-root scope.
public struct SecurityConfig: Codable, Equatable, Sendable {
    public var requirePinnedSkills: Bool?
    public var allowedSkillSources: [String]?
    /// Per-skill budget, in kilobytes, for inlined supporting markdown.
    public var referencesBudgetKb: Int?

    public init(
        requirePinnedSkills: Bool? = nil,
        allowedSkillSources: [String]? = nil,
        referencesBudgetKb: Int? = nil
    ) {
        self.requirePinnedSkills = requirePinnedSkills
        self.allowedSkillSources = allowedSkillSources
        self.referencesBudgetKb = referencesBudgetKb
    }

    enum CodingKeys: String, CodingKey {
        case requirePinnedSkills = "require_pinned_skills"
        case allowedSkillSources = "allowed_skill_sources"
        case referencesBudgetKb = "references_budget_kb"
    }
}

/// The `[learn]` block. Split cascade: delivery fields (`branch`, `base`,
/// `reviewers`, `team_reviewers`, `labels`, `draft`) are read only from the
/// repository-root scope; analysis fields (`lookback_days`, `min_signal`,
/// `enabled`) cascade field-by-field, closest-wins, like `[defaults]`.
public struct LearnConfig: Codable, Equatable, Sendable {
    // Delivery (root-only): there is one rolling PR per repository.
    public var branch: String?
    public var base: String?
    public var reviewers: [String]?
    public var teamReviewers: [String]?
    public var labels: [String]?
    public var draft: Bool?
    // Analysis (cascading closest-wins).
    public var lookbackDays: Int?
    public var minSignal: Int?
    public var enabled: Bool?

    public init(
        branch: String? = nil,
        base: String? = nil,
        reviewers: [String]? = nil,
        teamReviewers: [String]? = nil,
        labels: [String]? = nil,
        draft: Bool? = nil,
        lookbackDays: Int? = nil,
        minSignal: Int? = nil,
        enabled: Bool? = nil
    ) {
        self.branch = branch
        self.base = base
        self.reviewers = reviewers
        self.teamReviewers = teamReviewers
        self.labels = labels
        self.draft = draft
        self.lookbackDays = lookbackDays
        self.minSignal = minSignal
        self.enabled = enabled
    }

    enum CodingKeys: String, CodingKey {
        case branch, base, reviewers, labels, draft
        case teamReviewers = "team_reviewers"
        case lookbackDays = "lookback_days"
        case minSignal = "min_signal"
        case enabled
    }
}
