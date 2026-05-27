import Testing
@testable import BatonKit

@Suite("Core domain types")
struct CoreTypesTests {
    @Test("Severity is ordered low < medium < high")
    func severityOrdering() {
        #expect(Severity.low < Severity.medium)
        #expect(Severity.medium < Severity.high)
        #expect(Severity.allCases == [.low, .medium, .high])
    }

    @Test("Finding dedupe key is (file, line, severity, title)")
    func dedupeKey() {
        let a = Finding(file: "a.swift", line: 10, severity: .high, title: "X", body: "one")
        let b = Finding(file: "a.swift", line: 10, severity: .high, title: "X", body: "two")
        #expect(a.dedupeKey == b.dedupeKey)
    }

    @Test("AgentKind lists every supported agent for help text")
    func agentKindHelp() {
        #expect(AgentKind.allCases.count == 4)
        #expect(AgentKind.listForHelp == "claude, codex, gemini, opencode")
    }

    @Test("Error formatter renders description and recovery")
    func errorFormatting() {
        struct Sample: BatonError {
            var errorDescription: String? { "boom" }
            var recoverySuggestion: String? { "try again" }
        }
        let rendered = BatonErrorFormatter().format(Sample())
        #expect(rendered == "✗ boom\n  → try again")
    }
}
