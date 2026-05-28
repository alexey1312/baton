@testable import BatonKit
import Testing

struct CascadeTests {
    private func root(_ config: BatonConfig, autoSkills: [SkillConfig] = []) -> ScopeConfig {
        ScopeConfig(path: "", configPath: "baton.toml", config: config, autoSkills: autoSkills)
    }

    private func scope(_ path: String, _ config: BatonConfig, autoSkills: [SkillConfig] = []) -> ScopeConfig {
        ScopeConfig(path: path, configPath: "\(path)/baton.toml", config: config, autoSkills: autoSkills)
    }

    // MARK: - Agent block

    @Test("child agent block replaces the ancestor block entirely")
    func agentBlockReplaced() throws {
        let r = root(BatonConfig(agent: AgentConfig(kind: .codex, model: "o3", context: .repo)))
        let c = scope("ios", BatonConfig(agent: AgentConfig(kind: .claude)))
        let eff = try Cascade.effective(for: c, in: [r, c])
        #expect(eff.agent?.kind == .claude)
        #expect(eff.agent?.model == nil)
        #expect(eff.agent?.context == nil)
    }

    @Test("scope without an agent block inherits the nearest ancestor block")
    func agentInherited() throws {
        let r = root(BatonConfig(agent: AgentConfig(kind: .claude, model: "m")))
        let c = scope("ios", BatonConfig(reviews: [ReviewConfig(name: "r")]))
        let eff = try Cascade.effective(for: c, in: [r, c])
        #expect(eff.agent?.kind == .claude)
        #expect(eff.agent?.model == "m")
    }

    // MARK: - Skills

    @Test("skills union with closest-wins on name collision")
    func skillsUnion() throws {
        let r = root(BatonConfig(skills: [SkillConfig(name: "owasp", source: "org/skills", ref: "aaaa")]))
        let c = scope("ios", BatonConfig(skills: [
            SkillConfig(name: "owasp", source: "org/skills", ref: "bbbb"),
            SkillConfig(name: "swift-style", source: "./style"),
        ]))
        let eff = try Cascade.effective(for: c, in: [r, c])
        #expect(eff.skills.first { $0.name == "owasp" }?.ref == "bbbb")
        #expect(eff.skills.contains { $0.name == "swift-style" })
    }

    @Test("auto-discovered skill is prepended and overridden by an explicit entry")
    func autoSkillOverridden() throws {
        let c = scope(
            "ios",
            BatonConfig(skills: [SkillConfig(name: "owasp", source: "org/skills", ref: "x")]),
            autoSkills: [SkillConfig(name: "owasp", source: "./.baton/skills/owasp")]
        )
        let eff = try Cascade.effective(for: c, in: [c])
        #expect(eff.skills.count == 1)
        #expect(eff.skills.first?.ref == "x")
        #expect(eff.provenance.source(for: "skills.owasp") == .file("ios/baton.toml"))
    }

    // MARK: - Defaults

    @Test("defaults merge field-by-field closest-wins")
    func defaultsFieldByField() throws {
        let r = root(BatonConfig(defaults: DefaultsConfig(failOn: .low, diffBudget: 60000)))
        let c = scope("ios", BatonConfig(defaults: DefaultsConfig(failOn: .high)))
        let eff = try Cascade.effective(for: c, in: [r, c])
        #expect(eff.defaults.failOn == .high)
        #expect(eff.defaults.diffBudget == 60000)
    }

    @Test("unset fields fall back to documented defaults")
    func defaultsFallback() throws {
        let c = scope("ios", BatonConfig(agent: AgentConfig(kind: .claude)))
        let eff = try Cascade.effective(for: c, in: [c])
        #expect(eff.defaults.base == "HEAD")
        #expect(eff.defaults.failOn == .high)
        #expect(eff.defaults.maxConcurrency == 4)
        #expect(eff.defaults.diffBudget == 120_000)
        #expect(eff.defaults.chunkStrategy == .byFile)
        #expect(eff.defaults.timeout == 600)
    }

    @Test("max_concurrency is forced to at least one")
    func maxConcurrencyFloor() throws {
        let c = scope("ios", BatonConfig(defaults: DefaultsConfig(maxConcurrency: 0)))
        let eff = try Cascade.effective(for: c, in: [c])
        #expect(eff.defaults.maxConcurrency == 1)
    }

    // MARK: - Reviews

    @Test("reviews are inherited, same-name overrides, disabled removes")
    func reviewsInheritance() throws {
        let r = root(BatonConfig(reviews: [
            ReviewConfig(name: "security", prompt: "root prompt"),
            ReviewConfig(name: "legacy-style"),
        ]))
        let c = scope("ios", BatonConfig(
            agent: AgentConfig(kind: .claude),
            reviews: [ReviewConfig(name: "security", glob: ["**/*.swift"], prompt: "child prompt")],
            disabledReviews: ["legacy-style"]
        ))
        // Root needs an agent so the chain is valid for both scopes.
        let rWithAgent = root(BatonConfig(
            agent: AgentConfig(kind: .claude),
            reviews: r.config.reviews
        ))
        let eff = try Cascade.effective(for: c, in: [rWithAgent, c])
        let security = eff.reviews.first { $0.name == "security" }
        #expect(security?.prompt == "child prompt")
        #expect(security?.glob == ["**/*.swift"])
        #expect(!eff.reviews.contains { $0.name == "legacy-style" })
    }

    @Test("disabled_reviews naming a non-existent review is a no-op")
    func disabledNoop() throws {
        let c = scope("ios", BatonConfig(
            agent: AgentConfig(kind: .claude),
            reviews: [ReviewConfig(name: "security")],
            disabledReviews: ["does-not-exist"]
        ))
        let eff = try Cascade.effective(for: c, in: [c])
        #expect(eff.reviews.map(\.name) == ["security"])
    }

    // MARK: - Security

    @Test("security is root-only; non-root security is ignored")
    func securityRootOnly() throws {
        let r = root(BatonConfig(
            agent: AgentConfig(kind: .claude),
            security: SecurityConfig(requirePinnedSkills: true, allowedSkillSources: ["org/*"])
        ))
        let c = scope("ios", BatonConfig(security: SecurityConfig(requirePinnedSkills: false)))
        let eff = try Cascade.effective(for: c, in: [r, c])
        #expect(eff.requirePinnedSkills == true)
        #expect(eff.security?.allowedSkillSources == ["org/*"])
    }

    @Test("references budget defaults to 1 MiB and honors security.references_budget_kb")
    func referencesBudget() throws {
        let dflt = root(BatonConfig(agent: AgentConfig(kind: .claude)))
        let effDefault = try Cascade.effective(for: dflt, in: [dflt])
        #expect(effDefault.referencesBudgetBytes == 1024 * 1024)

        let configured = root(BatonConfig(
            agent: AgentConfig(kind: .claude),
            security: SecurityConfig(referencesBudgetKb: 512)
        ))
        let eff = try Cascade.effective(for: configured, in: [configured])
        #expect(eff.referencesBudgetBytes == 512 * 1024)
    }

    // MARK: - Provenance

    @Test("provenance attributes each effective value to its source")
    func provenance() throws {
        let r = root(BatonConfig(
            agent: AgentConfig(kind: .claude),
            defaults: DefaultsConfig(diffBudget: 60000)
        ))
        let c = scope("ios", BatonConfig(defaults: DefaultsConfig(failOn: .high)))
        let eff = try Cascade.effective(for: c, in: [r, c])
        #expect(eff.provenance.source(for: "defaults.diff_budget") == .file("baton.toml"))
        #expect(eff.provenance.source(for: "defaults.fail_on") == .file("ios/baton.toml"))
        #expect(eff.provenance.source(for: "defaults.chunk_strategy") == .builtinDefault)
    }

    // MARK: - Validation

    @Test("reviews without a resolvable agent block fail")
    func noResolvableAgent() {
        let c = scope("ios", BatonConfig(reviews: [ReviewConfig(name: "security")]))
        #expect(throws: ConfigError.self) {
            try Cascade.effective(for: c, in: [c])
        }
    }

    @Test("a review referencing an undefined skill fails")
    func unresolvedSkill() {
        let c = scope("ios", BatonConfig(
            agent: AgentConfig(kind: .claude),
            reviews: [ReviewConfig(name: "security", skills: ["missing"])]
        ))
        #expect(throws: ConfigError.self) {
            try Cascade.effective(for: c, in: [c])
        }
    }
}
