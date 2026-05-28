@testable import BatonKit
import Foundation
import Testing

struct ScopeDiscoveryTests {
    /// Build a throwaway repository tree and clean it up after the test.
    private func withTempRepo(_ build: (URL) throws -> Void, _ body: (URL) throws -> Void) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("baton-disco-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try build(root)
        try body(root)
    }

    private func writeConfig(_ root: URL, _ relativeDir: String, _ contents: String) throws {
        let dir = relativeDir.isEmpty ? root : root.appendingPathComponent(relativeDir, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try contents.write(to: dir.appendingPathComponent("baton.toml"), atomically: true, encoding: .utf8)
    }

    @Test("nested baton.toml files each define a scope; excluded dirs are skipped")
    func nestedAndExcluded() throws {
        try withTempRepo({ root in
            try writeConfig(root, "", "[agent]\nkind = \"claude\"\n")
            try writeConfig(root, "ios", "[[reviews]]\nname = \"r\"\n")
            try writeConfig(root, "web/api", "[[reviews]]\nname = \"r\"\n")
            try writeConfig(root, "node_modules/pkg", "[agent]\nkind = \"codex\"\n")
            try writeConfig(root, "target/gen", "[agent]\nkind = \"codex\"\n")
        }, { root in
            let result = try ScopeDiscovery.discover(repoRoot: root)
            let paths = Set(result.scopes.map(\.path))
            #expect(paths == ["", "ios", "web/api"])
        })
    }

    // Creating symlinks requires elevated privileges / Developer Mode on Windows.
    #if !os(Windows)
    @Test("symlinked directories are not descended")
    func symlinkNotFollowed() throws {
        try withTempRepo({ root in
            try writeConfig(root, "", "[agent]\nkind = \"claude\"\n")
            try writeConfig(root, "real", "[[reviews]]\nname = \"r\"\n")
            // ios/link -> ../real (a symlink to a directory inside the repo)
            let iosDir = root.appendingPathComponent("ios", isDirectory: true)
            try FileManager.default.createDirectory(at: iosDir, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                at: iosDir.appendingPathComponent("link"),
                withDestinationURL: root.appendingPathComponent("real")
            )
        }, { root in
            let result = try ScopeDiscovery.discover(repoRoot: root)
            #expect(!result.scopes.contains { $0.path.contains("link") })
        })
    }
    #endif

    @Test("auto-discovered skills are attached to their scope")
    func autoSkills() throws {
        try withTempRepo({ root in
            try writeConfig(root, "", "[agent]\nkind = \"claude\"\n")
            let skillDir = root.appendingPathComponent(".baton/skills/owasp-top10", isDirectory: true)
            try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
            try "# OWASP".write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }, { root in
            let result = try ScopeDiscovery.discover(repoRoot: root)
            let rootScope = try #require(result.scopes.first { $0.path.isEmpty })
            #expect(rootScope.autoSkills.contains { $0.name == "owasp-top10" })
        })
    }

    @Test("no baton.toml anywhere fails with init recovery")
    func noConfig() throws {
        try withTempRepo({ root in
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("src"),
                withIntermediateDirectories: true
            )
        }, { root in
            #expect(throws: ConfigError.self) {
                _ = try ScopeDiscovery.discover(repoRoot: root)
            }
        })
    }
}
