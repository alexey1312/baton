@testable import BatonKit
import Testing

struct ConfigParserTests {
    @Test("parses a full baton.toml with snake_case keys and enums")
    func parsesFull() throws {
        // Note: `disabled_reviews` is a top-level key, so per TOML semantics it
        // must appear before any table/array-of-tables header.
        let toml = """
        disabled_reviews = ["legacy"]

        [agent]
        kind = "claude"
        model = "claude-opus-4-7"
        context = "repo"

        [defaults]
        base = "origin/main"
        fail_on = "medium"
        max_concurrency = 8
        diff_budget = 60000
        chunk_strategy = "by-hunk"
        timeout = 300

        [[skills]]
        name = "owasp"
        source = "org/skills"
        ref = "abc123"

        [[reviews]]
        name = "security"
        skills = ["owasp"]
        glob = ["**/*.swift"]
        fail_on = "high"
        prompt = "Focus on auth."

        [security]
        require_pinned_skills = true
        allowed_skill_sources = ["org/*"]
        """
        let parsed = try ConfigParser.parse(toml, path: "baton.toml")
        let c = parsed.config
        #expect(c.agent?.kind == .claude)
        #expect(c.agent?.context == .repo)
        #expect(c.defaults?.failOn == .medium)
        #expect(c.defaults?.maxConcurrency == 8)
        #expect(c.defaults?.chunkStrategy == .byHunk)
        #expect(c.skills?.first?.ref == "abc123")
        #expect(c.reviews?.first?.glob == ["**/*.swift"])
        #expect(c.disabledReviews == ["legacy"])
        #expect(c.security?.allowedSkillSources == ["org/*"])
        #expect(parsed.warnings.isEmpty)
    }

    @Test("parses security.references_budget_kb")
    func parsesReferencesBudget() throws {
        let parsed = try ConfigParser.parse(
            "[security]\nreferences_budget_kb = 512\n",
            path: "baton.toml"
        )
        #expect(parsed.config.security?.referencesBudgetKb == 512)
        #expect(parsed.warnings.isEmpty)
    }

    @Test("parses the [learn] block with snake_case keys")
    func parsesLearn() throws {
        let toml = """
        [learn]
        branch = "learn"
        base = "main"
        reviewers = ["alice"]
        team_reviewers = ["platform"]
        labels = ["automation"]
        draft = false
        lookback_days = 30
        min_signal = 5
        enabled = false
        """
        let parsed = try ConfigParser.parse(toml, path: "baton.toml")
        let learn = parsed.config.learn
        #expect(learn?.branch == "learn")
        #expect(learn?.base == "main")
        #expect(learn?.reviewers == ["alice"])
        #expect(learn?.teamReviewers == ["platform"])
        #expect(learn?.labels == ["automation"])
        #expect(learn?.draft == false)
        #expect(learn?.lookbackDays == 30)
        #expect(learn?.minSignal == 5)
        #expect(learn?.enabled == false)
        #expect(parsed.warnings.isEmpty)
    }

    @Test("unknown learn keys are ignored with a warning")
    func unknownLearnKey() throws {
        let parsed = try ConfigParser.parse("[learn]\nfrobnicate = true\n", path: "baton.toml")
        #expect(parsed.warnings.contains { $0.contains("'learn.frobnicate'") })
    }

    @Test("unknown agent kind hard-fails with valid-kinds recovery")
    func invalidKind() {
        #expect(throws: ConfigError.self) {
            try ConfigParser.parse("[agent]\nkind = \"gpt\"\n", path: "baton.toml")
        }
    }

    @Test("unknown keys are ignored with a warning")
    func unknownKeys() throws {
        let toml = """
        wat = 1
        [agent]
        kind = "codex"
        frobnicate = true
        """
        let parsed = try ConfigParser.parse(toml, path: "baton.toml")
        #expect(parsed.config.agent?.kind == .codex)
        #expect(parsed.warnings.contains { $0.contains("'wat'") })
        #expect(parsed.warnings.contains { $0.contains("'agent.frobnicate'") })
    }

    @Test("duplicate review names hard-fail")
    func duplicateReview() {
        let toml = """
        [[reviews]]
        name = "security"
        [[reviews]]
        name = "security"
        """
        #expect(throws: ConfigError.self) {
            try ConfigParser.parse(toml, path: "baton.toml")
        }
    }
}
