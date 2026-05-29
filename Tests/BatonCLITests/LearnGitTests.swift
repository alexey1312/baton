@testable import BatonCLI
import BatonKit
import Foundation
import Testing

struct LearnGitTests {
    @Test("writeEdits writes full contents, creating parent directories")
    func writesContents() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("learn-write-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try LearnGit.writeEdits([
            ProposedEdit(path: "baton.toml", newContents: "name = \"root\"\n"),
            ProposedEdit(path: "ios/.baton/skills/SKILL.md", newContents: "# skill\n"),
        ], repoRoot: root)

        let toml = try String(contentsOf: root.appendingPathComponent("baton.toml"), encoding: .utf8)
        let skill = try String(
            contentsOf: root.appendingPathComponent("ios/.baton/skills/SKILL.md"), encoding: .utf8
        )
        #expect(toml == "name = \"root\"\n")
        #expect(skill == "# skill\n")
    }

    @Test("writeEdits removes a file for a nil-contents (deletion) edit")
    func deletesOnNilContents() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("learn-del-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("baton.toml")
        try Data("old".utf8).write(to: target)

        try LearnGit.writeEdits([ProposedEdit(path: "baton.toml", newContents: nil)], repoRoot: root)
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }
}
