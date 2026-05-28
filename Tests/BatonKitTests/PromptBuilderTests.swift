@testable import BatonKit
import Foundation
import Testing

struct PromptBuilderTests {
    @Test("sections appear in the fixed order with skills in an untrusted block")
    func ordering() throws {
        let prompt = PromptBuilder.build(
            reviewName: "security",
            instructions: "Focus on auth.",
            skills: [ResolvedSkill(name: "owasp", body: "OWASP RULES", sourceDescription: "x")],
            context: .diff,
            diff: "diff --git a/a b/a"
        )
        let role = try #require(prompt.range(of: "# Role"))
        let review = try #require(prompt.range(of: "# Review: security"))
        let skills = try #require(prompt.range(of: "UNTRUSTED"))
        let output = try #require(prompt.range(of: "# Output format"))
        let diff = try #require(prompt.range(of: "# Diff"))
        #expect(role.lowerBound < review.lowerBound)
        #expect(review.lowerBound < skills.lowerBound)
        #expect(skills.lowerBound < output.lowerBound)
        #expect(output.lowerBound < diff.lowerBound)
        #expect(prompt.contains("Focus on auth."))
        #expect(prompt.contains("OWASP RULES"))
    }

    @Test("review instructions are loaded from prompt_file relative to the scope dir")
    func promptFile() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("baton-prompt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "FROM FILE".write(to: dir.appendingPathComponent("rev.md"), atomically: true, encoding: .utf8)

        let review = ReviewConfig(name: "r", promptFile: "rev.md")
        let instructions = try PromptBuilder.instructions(for: review, configDir: dir)
        #expect(instructions == "FROM FILE")
    }

    @Test("repo context adds the cross-file note; diff context forbids tool access")
    func contextNote() {
        let diffPrompt = PromptBuilder.build(
            reviewName: "r", instructions: "x", skills: [], context: .diff, diff: "d"
        )
        #expect(diffPrompt.contains("only the diff"))
        let repoPrompt = PromptBuilder.build(
            reviewName: "r", instructions: "x", skills: [], context: .repo, diff: "d"
        )
        #expect(repoPrompt.contains("copy of the repository"))
    }
}
