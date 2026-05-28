@testable import BatonKit
import Foundation
import Testing

struct LearnAnalysisTests {
    // MARK: - Builders

    private func thread(
        id: String = "T",
        pr: Int = 1,
        prAuthor: String = "author",
        file: String,
        baton: Bool = true,
        resolution: ThreadResolution = .unresolved,
        automation: Bool = false,
        reactions: [Reaction] = [],
        title: String = "rule"
    ) -> ReviewThreadSignal {
        ReviewThreadSignal(
            threadId: id, pullRequest: pr, prAuthor: prAuthor, file: file, line: 1,
            isBatonAuthored: baton, resolution: resolution,
            resolutionActor: resolution == .resolved ? (automation ? "baton[bot]" : "human") : nil,
            resolvedByAutomation: automation, reactions: reactions,
            finding: baton ? FindingIdentity(file: file, line: 1, title: title, severity: .high) : nil
        )
    }

    private func scope(_ path: String) -> ScopeConfig {
        ScopeConfig(
            path: path,
            configPath: path.isEmpty ? "baton.toml" : "\(path)/baton.toml",
            config: BatonConfig(agent: AgentConfig(kind: .claude))
        )
    }

    private let up = Reaction(kind: .thumbsUp, author: "bob")
    private let down = Reaction(kind: .thumbsDown, author: "bob")

    // MARK: - Attribution

    @Test("thread attributed to the deepest owning scope")
    func attributionDeepest() {
        let scopes = [scope(""), scope("ios"), scope("ios/feature")]
        let t = thread(file: "ios/feature/A.swift")
        let groups = SignalAnalysis.attribute([t], scopes: scopes)
        #expect(groups["ios/feature"]?.count == 1)
        #expect(groups["ios"] == nil)
    }

    @Test("thread on a file outside any scope is dropped")
    func attributionOutside() {
        let scopes = [scope("ios")]
        let t = thread(file: "web/A.ts")
        let groups = SignalAnalysis.attribute([t], scopes: scopes)
        #expect(groups.isEmpty)
    }

    // MARK: - Bucketing

    @Test("buckets reflect resolution and authorship")
    func buckets() {
        #expect(SignalAnalysis.bucket(thread(file: "a", resolution: .resolved)) == .accepted)
        #expect(SignalAnalysis.bucket(thread(file: "a", resolution: .unresolved)) == .ignored)
        #expect(SignalAnalysis.bucket(thread(file: "a", resolution: .outdated)) == .outdated)
        #expect(SignalAnalysis.bucket(thread(file: "a", baton: false)) == .humanAuthored)
        // Resolved only by Baton automation is not "accepted".
        #expect(SignalAnalysis.bucket(thread(file: "a", resolution: .resolved, automation: true)) == .ignored)
    }

    // MARK: - Weighting

    @Test("upvoted resolved finding is a reinforce candidate")
    func reinforce() {
        let t = thread(file: "a", resolution: .resolved, reactions: [up])
        #expect(SignalAnalysis.weight(t) == 2)
        #expect(SignalAnalysis.candidates([t]).first?.direction == .reinforce)
    }

    @Test("downvoted unresolved finding is a relax candidate")
    func relax() {
        let t = thread(file: "a", resolution: .unresolved, reactions: [down, down])
        #expect(SignalAnalysis.weight(t) == -3)
        #expect(SignalAnalysis.candidates([t]).first?.direction == .relax)
    }

    @Test("outdated thread is weighted lower than a resolved/unresolved equivalent")
    func outdatedLow() {
        let outdated = thread(file: "a", resolution: .outdated, reactions: [up])
        let resolved = thread(file: "a", resolution: .resolved, reactions: [up])
        #expect(SignalAnalysis.weight(outdated) < SignalAnalysis.weight(resolved))
    }

    @Test("reaction augments rather than replaces resolution")
    func augmentNotReplace() {
        // Resolved but net-negative reactions must not be a reinforce candidate.
        let t = thread(file: "a", resolution: .resolved, reactions: [down, down])
        #expect(SignalAnalysis.weight(t) == -1)
        #expect(SignalAnalysis.candidates([t]).first?.direction == .relax)
    }

    @Test("pull request author's own reaction is not counted")
    func authorSelfReaction() {
        let selfUp = Reaction(kind: .thumbsUp, author: "author")
        let t = thread(prAuthor: "author", file: "a", resolution: .unresolved, reactions: [selfUp, down])
        // author's +1 excluded; only bob's -1 counts → net -1, plus unresolved -1.
        #expect(t.netReactionWeight == -1)
        #expect(SignalAnalysis.weight(t) == -2)
    }

    @Test("resolution by Baton automation contributes no resolution weight")
    func automationNotSignal() {
        let auto = thread(file: "a", resolution: .resolved, automation: true)
        let human = thread(file: "a", resolution: .resolved, automation: false)
        #expect(SignalAnalysis.weight(auto) == 0)
        #expect(SignalAnalysis.weight(human) == 1)
    }

    @Test("candidates are grouped per finding and sorted most-negative first")
    func candidateRanking() {
        let pos = thread(id: "A", file: "a", resolution: .resolved, reactions: [up], title: "good")
        let neg1 = thread(id: "B", file: "b", resolution: .unresolved, reactions: [down], title: "bad")
        let neg2 = thread(id: "C", file: "b", resolution: .unresolved, reactions: [down], title: "bad")
        let candidates = SignalAnalysis.candidates([pos, neg1, neg2])
        #expect(candidates.count == 2)
        #expect(candidates.first?.finding.title == "bad")
        #expect(candidates.first?.threadCount == 2)
        #expect(candidates.first?.direction == .relax)
    }

    @Test("signal volume counts only Baton-authored threads")
    func volumeBatonOnly() {
        let threads = [
            thread(file: "a", baton: true),
            thread(file: "b", baton: true),
            thread(file: "c", baton: false),
        ]
        #expect(SignalAnalysis.signalVolume(threads) == 2)
        #expect(SignalAnalysis.humanAuthoredThreads(threads).count == 1)
    }

    // MARK: - Edit allowlist

    @Test("setup edits are allowed, source/test/CI/deps are refused")
    func allowlistBasics() {
        let allow = EditAllowlist(scopePath: "ios", localSkillDirs: ["ios/.baton/skills"])
        #expect(allow.isAllowed("ios/baton.toml"))
        #expect(allow.isAllowed("ios/.baton/skills/owasp/SKILL.md"))
        #expect(allow.isAllowed("ios/AGENTS.md"))
        #expect(!allow.isAllowed("ios/Sources/App.swift"))
        #expect(!allow.isAllowed("ios/Tests/AppTests.swift"))
        #expect(!allow.isAllowed(".github/workflows/ci.yml"))
        #expect(!allow.isAllowed("ios/Package.swift"))
        // Outside the scope is refused even if it is a baton.toml.
        #expect(!allow.isAllowed("web/baton.toml"))
    }

    @Test("filter drops out-of-allowlist edits, keeps permitted ones")
    func allowlistFilter() {
        let allow = EditAllowlist(scopePath: "", localSkillDirs: [".baton/skills"])
        let edits = [
            ProposedEdit(path: "baton.toml", newContents: "x"),
            ProposedEdit(path: "Sources/main.swift", newContents: "y"),
            ProposedEdit(path: ".baton/skills/sec/SKILL.md", newContents: "z"),
        ]
        let kept = allow.filter(edits)
        #expect(kept.map(\.path) == ["baton.toml", ".baton/skills/sec/SKILL.md"])
    }

    @Test("root scope still refuses source, manifests, and CI despite owning all paths")
    func allowlistRootScopeRefusesSource() {
        let allow = EditAllowlist(scopePath: "", localSkillDirs: [".baton/skills"])
        #expect(allow.isAllowed("baton.toml"))
        #expect(allow.isAllowed("CLAUDE.md"))
        #expect(allow.isAllowed(".baton/skills/sec/SKILL.md"))
        #expect(!allow.isAllowed("Sources/App.swift"))
        #expect(!allow.isAllowed("Package.swift"))
        #expect(!allow.isAllowed(".github/workflows/ci.yml"))
    }

    @Test("`..` traversal is refused even toward an allowed skill dir")
    func allowlistRejectsTraversal() {
        let allow = EditAllowlist(scopePath: "ios", localSkillDirs: ["ios/.baton/skills"])
        #expect(!allow.isAllowed("ios/.baton/skills/../../Sources/App.swift"))
        #expect(!allow.isAllowed("ios/../web/baton.toml"))
    }
}
