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
    /// Resolved reviews (inherited, override/disable applied).
    public var reviews: [ReviewConfig]
    /// Root-only security policy.
    public var security: SecurityConfig?
    /// Provenance for `config --explain`.
    public var provenance: ConfigProvenance

    public init(
        scopePath: String,
        agent: AgentConfig?,
        defaults: EffectiveDefaults,
        skills: [SkillConfig],
        reviews: [ReviewConfig],
        security: SecurityConfig?,
        provenance: ConfigProvenance
    ) {
        self.scopePath = scopePath
        self.agent = agent
        self.defaults = defaults
        self.skills = skills
        self.reviews = reviews
        self.security = security
        self.provenance = provenance
    }

    /// The effective `require_pinned_skills` policy (root security, default `true`).
    public var requirePinnedSkills: Bool {
        security?.requirePinnedSkills ?? ConfigDefaults.requirePinnedSkills
    }
}
