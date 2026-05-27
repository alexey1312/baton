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
        let skills = resolveSkills(chain, &prov)
        let reviews = resolveReviews(chain, &prov)
        let security = resolveSecurity(chain, &prov)

        // A scope with reviews must have a resolvable agent block.
        if !reviews.isEmpty, agent == nil {
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
            if let v = d.diffBudget { result.diffBudget = v; prov.record("defaults.diff_budget", file) }
            if let v = d.chunkStrategy {
                result.chunkStrategy = v
                prov.record("defaults.chunk_strategy", file)
            }
            if let v = d.timeout { result.timeout = v; prov.record("defaults.timeout", file) }
        }

        result.maxConcurrency = max(result.maxConcurrency, 1)
        return result
    }

    private static func resolveSkills(_ chain: [ScopeConfig], _ prov: inout ConfigProvenance) -> [SkillConfig] {
        var order: [String] = []
        var byName: [String: SkillConfig] = [:]
        var sources: [String: ProvenanceSource] = [:]

        func upsert(_ skill: SkillConfig, _ source: ProvenanceSource) {
            if byName[skill.name] == nil { order.append(skill.name) }
            byName[skill.name] = skill
            sources[skill.name] = source
        }

        for scope in chain {
            // Auto-discovered skills are prepended so explicit entries override them.
            for skill in scope.autoSkills {
                upsert(skill, .autoDiscovered(scope.path.isEmpty ? ".baton/skills" : "\(scope.path)/.baton/skills"))
            }
            for skill in scope.config.skills ?? [] {
                upsert(skill, .file(scope.configPath))
            }
        }

        for (name, source) in sources {
            prov.record("skills.\(name)", source)
        }
        return order.compactMap { byName[$0] }
    }

    private static func resolveReviews(_ chain: [ScopeConfig], _ prov: inout ConfigProvenance) -> [ReviewConfig] {
        var order: [String] = []
        var byName: [String: ReviewConfig] = [:]
        var sources: [String: ProvenanceSource] = [:]

        for scope in chain {
            // Disable inherited reviews first, so a scope may disable then redefine.
            for name in scope.config.disabledReviews ?? [] {
                byName[name] = nil
                sources[name] = nil
                order.removeAll { $0 == name }
            }
            for review in scope.config.reviews ?? [] {
                if byName[review.name] == nil { order.append(review.name) }
                byName[review.name] = review
                sources[review.name] = .file(scope.configPath)
            }
        }

        for (name, source) in sources {
            prov.record("reviews.\(name)", source)
        }
        return order.compactMap { byName[$0] }
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

    private static func displayPath(_ path: String) -> String {
        path.isEmpty ? "(root)" : path
    }
}
