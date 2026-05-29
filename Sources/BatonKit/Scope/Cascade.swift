/// Computes the effective configuration for a scope via a root-to-scope,
/// closest-wins cascade with provenance.
public enum Cascade {
    /// The ancestor chain for `target`, ordered root (shallowest) to target (deepest).
    public static func chain(for target: ScopeConfig, in all: [ScopeConfig]) -> [ScopeConfig] {
        all.filter { $0.isAncestorOrSelf(of: target.path) }
            .sorted { $0.depth < $1.depth }
    }

    /// Compute the effective config for `target` using its ancestor chain in `all`.
    public static func effective(for target: ScopeConfig, in all: [ScopeConfig]) throws -> EffectiveConfig {
        let chain = chain(for: target, in: all)
        var prov = ConfigProvenance()

        let agent = resolveAgent(chain, &prov)
        let defaults = resolveDefaults(chain, &prov)
        let (skills, skillDirs) = resolveSkills(chain, &prov)
        let (reviews, reviewDirs) = resolveReviews(chain, &prov)
        let security = resolveSecurity(chain, &prov)
        let learn = resolveLearn(chain, &prov)
        let publish = resolvePublish(chain, &prov)
        let render = resolveRender(chain, &prov)

        // Each review must have a resolvable agent: the scope's `[agent]` block or
        // the review's own `[[reviews]].agent` override.
        for review in reviews where agent == nil && review.agent == nil {
            throw ConfigError.noResolvableAgent(scope: displayPath(target.path))
        }

        // Every review's referenced skills must resolve.
        let knownSkills = Set(skills.map(\.name))
        for review in reviews {
            for skill in review.skills ?? [] where !knownSkills.contains(skill) {
                throw ConfigError.unresolvedSkill(
                    scope: displayPath(target.path),
                    review: review.name,
                    skill: skill
                )
            }
        }

        return EffectiveConfig(
            scopePath: target.path,
            agent: agent,
            defaults: defaults,
            skills: skills,
            reviews: reviews,
            security: security,
            learn: learn,
            publish: publish,
            render: render,
            skillDeclaringDirs: skillDirs,
            reviewDeclaringDirs: reviewDirs,
            provenance: prov
        )
    }

    // MARK: - Section resolvers

    private static func resolveAgent(_ chain: [ScopeConfig], _ prov: inout ConfigProvenance) -> AgentConfig? {
        var agent: AgentConfig?
        for scope in chain where scope.config.agent != nil {
            agent = scope.config.agent
            prov.record("agent", .file(scope.configPath))
        }
        return agent
    }

    private static func resolveDefaults(
        _ chain: [ScopeConfig],
        _ prov: inout ConfigProvenance
    ) -> EffectiveDefaults {
        var result = EffectiveDefaults()

        for scope in chain {
            guard let d = scope.config.defaults else { continue }
            let file = ProvenanceSource.file(scope.configPath)
            if let v = d.base { result.base = v; prov.record("defaults.base", file) }
            if let v = d.failOn { result.failOn = v; prov.record("defaults.fail_on", file) }
            if let v = d.maxConcurrency {
                result.maxConcurrency = v
                prov.record("defaults.max_concurrency", file)
            }
            // A non-positive budget would mark every hunk truncated; treat it as
            // unconfigured so the inherited/default budget stands (cf. max_concurrency).
            if let v = d.diffBudget, v > 0 { result.diffBudget = v; prov.record("defaults.diff_budget", file) }
            if let v = d.chunkStrategy {
                result.chunkStrategy = v
                prov.record("defaults.chunk_strategy", file)
            }
            if let v = d.timeout { result.timeout = v; prov.record("defaults.timeout", file) }
        }

        result.maxConcurrency = max(result.maxConcurrency, 1)
        return result
    }

    /// Resolve skills closest-wins, tracking the repo-relative directory of the
    /// scope that declared each (its `baton.toml` lives at `scope.path`), so an
    /// inherited skill's relative local `source` anchors to where it was declared.
    private static func resolveSkills(
        _ chain: [ScopeConfig],
        _ prov: inout ConfigProvenance
    ) -> ([SkillConfig], [String: String]) {
        var order: [String] = []
        var byName: [String: SkillConfig] = [:]
        var sources: [String: ProvenanceSource] = [:]
        var dirs: [String: String] = [:]

        func upsert(_ skill: SkillConfig, _ source: ProvenanceSource, dir: String) {
            if byName[skill.name] == nil { order.append(skill.name) }
            byName[skill.name] = skill
            sources[skill.name] = source
            dirs[skill.name] = dir
        }

        for scope in chain {
            // Auto-discovered skills are prepended so explicit entries override them.
            for skill in scope.autoSkills {
                let label = scope.path.isEmpty ? ".baton/skills" : "\(scope.path)/.baton/skills"
                upsert(skill, .autoDiscovered(label), dir: scope.path)
            }
            for skill in scope.config.skills ?? [] {
                upsert(skill, .file(scope.configPath), dir: scope.path)
            }
        }

        for (name, source) in sources {
            prov.record("skills.\(name)", source)
        }
        return (order.compactMap { byName[$0] }, dirs)
    }

    private static func resolveReviews(
        _ chain: [ScopeConfig],
        _ prov: inout ConfigProvenance
    ) -> ([ReviewConfig], [String: String]) {
        var order: [String] = []
        var byName: [String: ReviewConfig] = [:]
        var sources: [String: ProvenanceSource] = [:]
        var dirs: [String: String] = [:]

        for scope in chain {
            // Disable inherited reviews first, so a scope may disable then redefine.
            for name in scope.config.disabledReviews ?? [] {
                byName[name] = nil
                sources[name] = nil
                dirs[name] = nil
                order.removeAll { $0 == name }
            }
            for review in scope.config.reviews ?? [] {
                if byName[review.name] == nil { order.append(review.name) }
                byName[review.name] = review
                sources[review.name] = .file(scope.configPath)
                dirs[review.name] = scope.path
            }
        }

        for (name, source) in sources {
            prov.record("reviews.\(name)", source)
        }
        return (order.compactMap { byName[$0] }, dirs)
    }

    private static func resolveSecurity(
        _ chain: [ScopeConfig],
        _ prov: inout ConfigProvenance
    ) -> SecurityConfig? {
        // Security is honored only at the repository-root scope (chain head).
        guard let root = chain.first, let security = root.config.security else { return nil }
        prov.record("security", .file(root.configPath))
        return security
    }

    private static func resolvePublish(
        _ chain: [ScopeConfig],
        _ prov: inout ConfigProvenance
    ) -> EffectivePublish {
        // Publish is honored only at the repository-root scope (chain head): there
        // is one publish per pull request, so this is not a per-scope cascade.
        var result = EffectivePublish()
        guard let root = chain.first, let publish = root.config.publish else { return result }
        if let v = publish.resolveOutdatedThreads {
            result.resolveOutdatedThreads = v
            prov.record("publish.resolve_outdated_threads", .file(root.configPath))
        }
        return result
    }

    private static func resolveRender(
        _ chain: [ScopeConfig],
        _ prov: inout ConfigProvenance
    ) -> EffectiveRender {
        // Render templates are honored only at the repository-root scope.
        var result = EffectiveRender()
        guard let root = chain.first, let render = root.config.render else { return result }
        let file = ProvenanceSource.file(root.configPath)
        if let v = render
            .markdownTemplate { result.markdownTemplate = v; prov.record("render.markdown_template", file) }
        if let v = render.learnPrBodyTemplate {
            result.learnPrBodyTemplate = v
            prov.record("render.learn_pr_body_template", file)
        }
        return result
    }

    private static func resolveLearn(
        _ chain: [ScopeConfig],
        _ prov: inout ConfigProvenance
    ) -> EffectiveLearn {
        var result = EffectiveLearn()
        // Analysis fields cascade field-by-field, closest-wins (like `[defaults]`).
        for scope in chain {
            guard let learn = scope.config.learn else { continue }
            let file = ProvenanceSource.file(scope.configPath)
            if let v = learn.lookbackDays { result.lookbackDays = v; prov.record("learn.lookback_days", file) }
            if let v = learn.minSignal { result.minSignal = v; prov.record("learn.min_signal", file) }
            if let v = learn.enabled { result.enabled = v; prov.record("learn.enabled", file) }
            if let v = learn.countAuthorReactions {
                result.countAuthorReactions = v
                prov.record("learn.count_author_reactions", file)
            }
        }
        // Clamp to sane minimums: a 0/negative min_signal would make every scope
        // pass volume gating, and a 0/negative lookback would read an empty window.
        result.minSignal = max(result.minSignal, 1)
        result.lookbackDays = max(result.lookbackDays, 1)
        // Delivery fields are read only from the repository-root scope (chain head).
        if let root = chain.first, let learn = root.config.learn {
            resolveLearnDelivery(learn, configPath: root.configPath, into: &result, &prov)
        }
        return result
    }

    private static func resolveLearnDelivery(
        _ learn: LearnConfig,
        configPath: String,
        into result: inout EffectiveLearn,
        _ prov: inout ConfigProvenance
    ) {
        let file = ProvenanceSource.file(configPath)
        if let v = learn.branch { result.branch = v; prov.record("learn.branch", file) }
        if let v = learn.base { result.base = v; prov.record("learn.base", file) }
        if let v = learn.reviewers { result.reviewers = v; prov.record("learn.reviewers", file) }
        if let v = learn.teamReviewers { result.teamReviewers = v; prov.record("learn.team_reviewers", file) }
        if let v = learn.labels { result.labels = v; prov.record("learn.labels", file) }
        if let v = learn.draft { result.draft = v; prov.record("learn.draft", file) }
    }

    private static func displayPath(_ path: String) -> String {
        path.isEmpty ? "(root)" : path
    }
}
