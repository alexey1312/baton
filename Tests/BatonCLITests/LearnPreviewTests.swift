@testable import BatonCLI
import BatonKit
import Testing

struct LearnPreviewTests {
    private func candidate(_ title: String, _ weight: Int) -> RuleCandidate {
        RuleCandidate(
            finding: FindingIdentity(file: "ios/A.swift", line: 1, title: title, severity: .high),
            weight: weight,
            threadCount: 1
        )
    }

    private func result() -> LearnRunResult {
        LearnRunResult(
            proposals: [
                ScopeProposal(
                    scopePath: "ios",
                    edits: [ProposedEdit(path: "ios/baton.toml", newContents: "x", summary: "relax SQLi rule")],
                    droppedPaths: ["ios/Sources/App.swift"],
                    candidates: [candidate("noisy", -3), candidate("good", 2)],
                    bucketCounts: [.ignored: 2, .accepted: 1],
                    signalVolume: 3
                ),
            ],
            skipped: [ScopeSkip(scopePath: "web", reason: .belowMinSignal(volume: 0, required: 1))],
            allCandidates: [candidate("noisy", -3)]
        )
    }

    @Test("terminal preview lists edits, signal summary, dropped paths, and skips")
    func terminal() {
        let text = LearnPreview.terminal(result(), useColors: false)
        #expect(text.contains("ios: 1 proposed edit(s)"))
        #expect(text.contains("ios/baton.toml"))
        #expect(text.contains("1 relax / 1 reinforce"))
        #expect(text.contains("dropped (out of allowlist): ios/Sources/App.swift"))
        #expect(text.contains("web: skipped — below min_signal (0 < 1)"))
    }

    @Test("markdown body lists per-scope edits for the rolling PR")
    func markdown() {
        let md = LearnPreview.markdown(result())
        #expect(md.contains("## Baton learn"))
        #expect(md.contains("### `ios`"))
        #expect(md.contains("- `ios/baton.toml` — relax SQLi rule"))
        // A refused edit must never appear in the PR body.
        #expect(!md.contains("App.swift"))
    }

    @Test("empty result renders a friendly no-signal message")
    func empty() {
        let text = LearnPreview.terminal(LearnRunResult(), useColors: false)
        #expect(text.contains("No signal"))
    }
}
