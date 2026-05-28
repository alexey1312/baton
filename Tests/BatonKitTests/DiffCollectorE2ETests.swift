@testable import BatonKit
import Foundation
import Testing

struct DiffCollectorE2ETests {
    /// Build a throwaway git repository with a clean initial commit, run `body`, and
    /// clean up.
    private func withTempRepo(_ body: (URL, GitRunner) throws -> Void) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("baton-git-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let git = GitRunner(repoRoot: root)
        // Disable git hooks/config interference and pin a deterministic identity.
        _ = try git.run(["init", "-q", "-b", "main"])
        _ = try git.run(["config", "user.email", "test@example.com"])
        _ = try git.run(["config", "user.name", "Test"])
        _ = try git.run(["config", "commit.gpgsign", "false"])

        try "hello\n".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        _ = try git.run(["add", "."])
        _ = try git.run(["commit", "-q", "-m", "init"])

        try body(root, git)
    }

    @Test("modified + untracked are collected against HEAD")
    func modifiedAndUntracked() throws {
        try withTempRepo { root, git in
            // Modify the tracked file.
            try "hello\nworld\n".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
            // Add an untracked file.
            try "new\n".write(to: root.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

            let diff = try DiffCollector(git: git).collect(base: "HEAD")
            let byPath = Dictionary(uniqueKeysWithValues: diff.files.map { ($0.path, $0) })

            let modified = try #require(byPath["a.txt"])
            #expect(modified.changeKind == .modified)
            #expect(!modified.hunks.isEmpty)

            let added = try #require(byPath["b.txt"])
            #expect(added.changeKind == .added)
            #expect(!added.hunks.isEmpty)
            #expect(added.patch.contains("@@ -0,0"))
        }
    }

    @Test("empty diff returns no files")
    func emptyDiff() throws {
        try withTempRepo { _, git in
            let diff = try DiffCollector(git: git).collect(base: "HEAD")
            #expect(diff.isEmpty)
        }
    }

    @Test("invalid base ref throws with a fetch recovery suggestion")
    func invalidBase() throws {
        try withTempRepo { _, git in
            #expect(throws: GitError.self) {
                _ = try DiffCollector(git: git).collect(base: "origin/does-not-exist")
            }
        }
    }
}
