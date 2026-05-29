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

    // MARK: - Learn block

    @Test("learn analysis field overridden closest-wins, others inherited")
    func learnAnalysisCascade() throws {
        let r = root(BatonConfig(
            agent: AgentConfig(kind: .claude),
            learn: LearnConfig(lookbackDays: 14, minSignal: 3)
        ))
        let c = scope("ios", BatonConfig(learn: LearnConfig(minSignal: 5)))
        let eff = try Cascade.effective(for: c, in: [r, c])
        #expect(eff.learn.minSignal == 5) // child override
        #expect(eff.learn.lookbackDays == 14) // inherited from root
    }

    @Test("learn delivery fields are honored only at the root")
    func learnDeliveryRootOnly() throws {
        let r = root(BatonConfig(
            agent: AgentConfig(kind: .claude),
            learn: LearnConfig(branch: "learn", reviewers: ["alice"])
        ))
        let c = scope("ios", BatonConfig(learn: LearnConfig(branch: "child-learn", reviewers: ["bob"])))
        let eff = try Cascade.effective(for: c, in: [r, c])
        #expect(eff.learn.branch == "learn") // root delivery wins
        #expect(eff.learn.reviewers == ["alice"]) // child delivery ignored
    }

    @Test("learn enabled = false opts a scope out")
    func learnOptOut() throws {
        let r = root(BatonConfig(agent: AgentConfig(kind: .claude), learn: LearnConfig(enabled: true)))
        let c = scope("ios", BatonConfig(learn: LearnConfig(enabled: false)))
        let eff = try Cascade.effective(for: c, in: [r, c])
        #expect(eff.learn.enabled == false)
    }

    @Test("learn count_author_reactions cascades closest-wins and defaults to false")
    func learnCountAuthorReactionsCascade() throws {
        // Default: unset anywhere → false.
        let plain = scope("ios", BatonConfig(agent: AgentConfig(kind: .claude)))
        #expect(try Cascade.effective(for: plain, in: [plain]).learn.countAuthorReactions == false)

        // Child override wins over root.
        let r = root(BatonConfig(
            agent: AgentConfig(kind: .claude),
            learn: LearnConfig(countAuthorReactions: false)
        ))
        let c = scope("ios", BatonConfig(learn: LearnConfig(countAuthorReactions: true)))
        let eff = try Cascade.effective(for: c, in: [r, c])
        #expect(eff.learn.countAuthorReactions == true)
        #expect(eff.provenance.source(for: "learn.count_author_reactions") == .file("ios/baton.toml"))
    }

    @Test("learn enabled defaults to true when unset anywhere in the chain")
    func learnEnabledDefaultsTrue() throws {
        let c = scope("ios", BatonConfig(agent: AgentConfig(kind: .claude)))
        let eff = try Cascade.effective(for: c, in: [c])
        #expect(eff.learn.enabled == true)
        #expect(eff.learn.lookbackDays == 14)
        #expect(eff.learn.minSignal == 1)
        #expect(eff.learn.branch == "learn")
        #expect(eff.learn.draft == true)
    }

    @Test("learn provenance attributes analysis and delivery sources")
    func learnProvenance() throws {
        let r = root(BatonConfig(
            agent: AgentConfig(kind: .claude),
            learn: LearnConfig(branch: "learn", lookbackDays: 30)
        ))
        let c = scope("ios", BatonConfig(learn: LearnConfig(minSignal: 5)))
        let eff = try Cascade.effective(for: c, in: [r, c])
        #expect(eff.provenance.source(for: "learn.lookback_days") == .file("baton.toml"))
        #expect(eff.provenance.source(for: "learn.min_signal") == .file("ios/baton.toml"))
        #expect(eff.provenance.source(for: "learn.branch") == .file("baton.toml"))
        #expect(eff.provenance.source(for: "learn.enabled") == .builtinDefault)
    }

    // MARK: - Publish block

    @Test("publish.resolve_outdated_threads is root-only and defaults to false")
    func publishRootOnly() throws {
        let r = root(BatonConfig(
            agent: AgentConfig(kind: .claude),
            publish: PublishConfig(resolveOutdatedThreads: true)
        ))
        let c = scope("ios", BatonConfig(publish: PublishConfig(resolveOutdatedThreads: false)))
        let eff = try Cascade.effective(for: c, in: [r, c])
        #expect(eff.publish.resolveOutdatedThreads == true) // root wins; child ignored

        let bare = scope("ios", BatonConfig(agent: AgentConfig(kind: .claude)))
        let effDefault = try Cascade.effective(for: bare, in: [bare])
        #expect(effDefault.publish.resolveOutdatedThreads == false) // documented default
        #expect(effDefault.provenance.source(for: "publish.resolve_outdated_threads") == .builtinDefault)
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

    // MARK: - Per-review agent

    @Test("a review's own agent block is preserved through the cascade")
    func perReviewAgentPreserved() throws {
        let r = root(BatonConfig(
            agent: AgentConfig(kind: .claude, model: "haiku"),
            reviews: [
                ReviewConfig(name: "fast"),
                ReviewConfig(name: "deep", agent: AgentConfig(kind: .codex, model: "o3")),
            ]
        ))
        let eff = try Cascade.effective(for: r, in: [r])
        #expect(eff.reviews.first { $0.name == "deep" }?.agent?.kind == .codex)
        #expect(eff.reviews.first { $0.name == "deep" }?.agent?.model == "o3")
        #expect(eff.reviews.first { $0.name == "fast" }?.agent == nil)
    }

    @Test("a scope without an agent block is valid when every review supplies its own")
    func reviewAgentSatisfiesValidation() throws {
        let c = scope("ios", BatonConfig(reviews: [
            ReviewConfig(name: "r", agent: AgentConfig(kind: .gemini)),
        ]))
        let eff = try Cascade.effective(for: c, in: [c])
        #expect(eff.agent == nil)
        #expect(eff.reviews.first?.agent?.kind == .gemini)
    }

    @Test("a review with neither a scope nor its own agent still fails")
    func reviewWithoutAnyAgentFails() {
        let c = scope("ios", BatonConfig(reviews: [
            ReviewConfig(name: "ok", agent: AgentConfig(kind: .gemini)),
            ReviewConfig(name: "bad"),
        ]))
        #expect(throws: ConfigError.self) {
            try Cascade.effective(for: c, in: [c])
        }
    }

    // MARK: - Declaring directories

    @Test("an inherited skill and review keep their declaring scope directory")
    func inheritedDeclaringDirs() throws {
        let r = root(BatonConfig(
            agent: AgentConfig(kind: .claude),
            skills: [SkillConfig(name: "style", source: "./.claude/skills/style")],
            reviews: [ReviewConfig(name: "r", skills: ["style"])]
        ))
        let c = scope("ios", BatonConfig(agent: AgentConfig(kind: .gemini)))
        let eff = try Cascade.effective(for: c, in: [r, c])
        // Inherited from the root scope, so its declaring dir is the root ("").
        #expect(eff.skillDeclaringDirs["style"]?.isEmpty == true)
        #expect(eff.reviewDeclaringDirs["r"]?.isEmpty == true)
    }

    @Test("a locally redefined skill takes the redefining scope's directory")
    func redefinedSkillDeclaringDir() throws {
        let r = root(BatonConfig(skills: [SkillConfig(name: "style", source: "./root-style")]))
        let c = scope("ios", BatonConfig(
            agent: AgentConfig(kind: .claude),
            skills: [SkillConfig(name: "style", source: "./ios-style")],
            reviews: [ReviewConfig(name: "r", skills: ["style"])]
        ))
        let eff = try Cascade.effective(for: c, in: [r, c])
        #expect(eff.skillDeclaringDirs["style"] == "ios")
    }
}

/// Extensions count separately toward type_body_length, keeping the suite under the cap.
extension CascadeTests {
    @Test("learn agent/model cascade closest-wins and default to nil")
    func learnAgentModelCascade() throws {
        // Default: unset anywhere → nil (fall back to the scope's [agent]).
        let plain = scope("ios", BatonConfig(agent: AgentConfig(kind: .claude)))
        let eff0 = try Cascade.effective(for: plain, in: [plain]).learn
        #expect(eff0.agent == nil)
        #expect(eff0.model == nil)

        // Child override wins over root, field-by-field.
        let r = root(BatonConfig(
            agent: AgentConfig(kind: .claude),
            learn: LearnConfig(agent: .codex, model: "opus")
        ))
        let c = scope("ios", BatonConfig(learn: LearnConfig(model: "sonnet")))
        let eff = try Cascade.effective(for: c, in: [r, c])
        #expect(eff.learn.agent == .codex) // inherited from root
        #expect(eff.learn.model == "sonnet") // child override
        #expect(eff.provenance.source(for: "learn.agent") == .file("baton.toml"))
        #expect(eff.provenance.source(for: "learn.model") == .file("ios/baton.toml"))
    }
}
