@testable import BatonCLI
import BatonKit
import Testing

struct LearnPlanningTests {
    private func scope(_ path: String) -> ScopeConfig {
        ScopeConfig(path: path, configPath: path.isEmpty ? "baton.toml" : "\(path)/baton.toml", config: BatonConfig())
    }

    private func effective(_ path: String, skills: [SkillConfig]) -> EffectiveConfig {
        EffectiveConfig(
            scopePath: path,
            agent: nil,
            defaults: EffectiveDefaults(),
            skills: skills,
            reviews: [],
            security: nil,
            provenance: ConfigProvenance()
        )
    }

    @Test("local skill dirs include .baton/skills and in-scope relative sources only")
    func localSkillDirs() {
        let skills = [
            SkillConfig(name: "rel", source: "./skills/sec"),
            SkillConfig(name: "abs", source: "/etc/evil"),
            SkillConfig(name: "tilde", source: "~/skills"),
            SkillConfig(name: "remote", source: "owner/repo"),
            SkillConfig(name: "escape", source: "../shared/skills"),
        ]
        let dirs = LearnPlanning.localSkillDirs(scope: scope("ios"), effective: effective("ios", skills: skills))
        // Absolute, ~, remote, and `..`-traversing sources are excluded; only the
        // scope's own `.baton/skills` and the in-scope relative dir remain.
        #expect(Set(dirs) == ["ios/.baton/skills", "ios/skills/sec"])
    }

    @Test("at the root scope dirs are not prefixed")
    func localSkillDirsRoot() {
        let dirs = LearnPlanning.localSkillDirs(
            scope: scope(""),
            effective: effective("", skills: [SkillConfig(name: "rel", source: "./skills/x")])
        )
        #expect(Set(dirs) == [".baton/skills", "skills/x"])
    }
}
