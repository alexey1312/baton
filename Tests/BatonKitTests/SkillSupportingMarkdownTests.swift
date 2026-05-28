#if !os(Windows)
// Windows is best-effort: these tests spawn subprocesses (git, POSIX coreutils)
// and create symlinks, both restricted on the Windows runner.
@testable import BatonKit
import Foundation
import Testing

/// Build a local-only resolver rooted at `root` (cache and `remotes/` siblings).
private func localResolver(_ root: URL) -> SkillResolver {
    SkillTestFixtures.resolver(
        repoRoot: root,
        cacheDir: root.appendingPathComponent("cache"),
        remotesRoot: root
    )
}

// MARK: - Supporting markdown inlining

struct SkillSupportingMarkdownTests {
    @Test("Codex-layout references/*.md are inlined alphabetically (local)")
    func localCodexLayoutReferences() throws {
        try SkillTestFixtures.withTempDir { root in
            let dir = root.appendingPathComponent("skills/x", isDirectory: true)
            try SkillTestFixtures.writeFile(dir, "SKILL.md", "# Main")
            let refs = dir.appendingPathComponent("references", isDirectory: true)
            // Created in reverse order on purpose; output must still be alphabetical.
            try SkillTestFixtures.writeFile(refs, "b.md", "B-body")
            try SkillTestFixtures.writeFile(refs, "a.md", "A-body")

            let resolved = try localResolver(root).resolve(
                SkillConfig(name: "x", source: "./skills/x"),
                declaringConfigDir: root,
                security: nil
            )

            #expect(resolved.body.hasPrefix("# Main"))
            let aRange = try #require(resolved.body.range(of: "## Reference: references/a"))
            let bRange = try #require(resolved.body.range(of: "## Reference: references/b"))
            #expect(aRange.lowerBound < bRange.lowerBound)
            #expect(resolved.body.contains("A-body"))
            #expect(resolved.body.contains("B-body"))
        }
    }

    @Test("Claude-layout root-level + examples/ references inline alphabetically (local)")
    func localClaudeLayoutReferences() throws {
        try SkillTestFixtures.withTempDir { root in
            let dir = root.appendingPathComponent("skills/x", isDirectory: true)
            try SkillTestFixtures.writeFile(dir, "SKILL.md", "main-body")
            try SkillTestFixtures.writeFile(dir, "reference.md", "root-ref")
            let examples = dir.appendingPathComponent("examples", isDirectory: true)
            try SkillTestFixtures.writeFile(examples, "sample.md", "sample-body")

            let resolved = try localResolver(root).resolve(
                SkillConfig(name: "x", source: "./skills/x"),
                declaringConfigDir: root,
                security: nil
            )

            #expect(resolved.body.hasPrefix("main-body"))
            let examplesRange = try #require(resolved.body.range(of: "## Reference: examples/sample"))
            let referenceRange = try #require(resolved.body.range(of: "## Reference: reference"))
            #expect(examplesRange.lowerBound < referenceRange.lowerBound)
            #expect(resolved.body.contains("sample-body"))
            #expect(resolved.body.contains("root-ref"))
        }
    }

    @Test("Codex-layout references inline for a cloned remote skill")
    func remoteReferencesInlined() throws {
        try SkillTestFixtures.withTempDir { root in
            let remote = root.appendingPathComponent("remotes/org/skills", isDirectory: true)
            let git = try SkillTestFixtures.initRepo(remote)
            let skillDir = remote.appendingPathComponent("skills/owasp", isDirectory: true)
            try SkillTestFixtures.writeFile(skillDir, "SKILL.md", "owasp-body")
            let refs = skillDir.appendingPathComponent("references", isDirectory: true)
            try SkillTestFixtures.writeFile(refs, "security.md", "secrules")
            let sha = try SkillTestFixtures.commitAll(git)

            let resolved = try SkillTestFixtures.remoteResolver(root: root).resolve(
                SkillConfig(name: "owasp", source: "org/skills/owasp", ref: sha),
                declaringConfigDir: root,
                security: nil
            )

            #expect(resolved.body.contains("owasp-body"))
            #expect(resolved.body.contains("## Reference: references/security"))
            #expect(resolved.body.contains("secrules"))
        }
    }

    @Test("body is unchanged when no supporting markdown is present")
    func noSupportingMarkdown() throws {
        try SkillTestFixtures.withTempDir { root in
            let dir = root.appendingPathComponent("skills/x", isDirectory: true)
            try SkillTestFixtures.writeFile(dir, "SKILL.md", "only-body")

            let resolved = try localResolver(root).resolve(
                SkillConfig(name: "x", source: "./skills/x"),
                declaringConfigDir: root,
                security: nil
            )

            #expect(resolved.body == "only-body")
            #expect(!resolved.body.contains("## Reference:"))
        }
    }

    @Test("non-markdown files in references/, scripts/, assets/ are ignored")
    func nonMarkdownIgnored() throws {
        try SkillTestFixtures.withTempDir { root in
            let dir = root.appendingPathComponent("skills/x", isDirectory: true)
            try SkillTestFixtures.writeFile(dir, "SKILL.md", "main")
            try SkillTestFixtures.writeFile(
                dir.appendingPathComponent("references", isDirectory: true),
                "notes.txt",
                "ignored text"
            )
            try SkillTestFixtures.writeFile(
                dir.appendingPathComponent("scripts", isDirectory: true),
                "foo.py",
                "print('ignored')"
            )
            try SkillTestFixtures.writeFile(
                dir.appendingPathComponent("assets", isDirectory: true),
                "logo.png",
                "PNGDATA"
            )

            let resolved = try localResolver(root).resolve(
                SkillConfig(name: "x", source: "./skills/x"),
                declaringConfigDir: root,
                security: nil
            )

            #expect(resolved.body == "main")
            #expect(!resolved.body.contains("notes"))
            #expect(!resolved.body.contains("foo"))
            #expect(!resolved.body.contains("PNGDATA"))
        }
    }

    @Test("references are inlined alphabetically regardless of creation order")
    func referencesAreSortedAlphabetically() throws {
        try SkillTestFixtures.withTempDir { root in
            let dir = root.appendingPathComponent("skills/x", isDirectory: true)
            try SkillTestFixtures.writeFile(dir, "SKILL.md", "main")
            let refs = dir.appendingPathComponent("references", isDirectory: true)
            // Create in reverse alphabetical order.
            try SkillTestFixtures.writeFile(refs, "zeta.md", "Z")
            try SkillTestFixtures.writeFile(refs, "kappa.md", "K")
            try SkillTestFixtures.writeFile(refs, "alpha.md", "A")

            let resolved = try localResolver(root).resolve(
                SkillConfig(name: "x", source: "./skills/x"),
                declaringConfigDir: root,
                security: nil
            )

            let alpha = try #require(resolved.body.range(of: "## Reference: references/alpha"))
            let kappa = try #require(resolved.body.range(of: "## Reference: references/kappa"))
            let zeta = try #require(resolved.body.range(of: "## Reference: references/zeta"))
            #expect(alpha.lowerBound < kappa.lowerBound)
            #expect(kappa.lowerBound < zeta.lowerBound)
        }
    }

    @Test("reference symlinked outside the skill directory is rejected")
    func referenceSymlinkEscapeRejected() throws {
        try SkillTestFixtures.withTempDir { root in
            let outside = root.appendingPathComponent("outside", isDirectory: true)
            try SkillTestFixtures.writeFile(outside, "secret.md", "TOP SECRET")
            let dir = root.appendingPathComponent("skills/x", isDirectory: true)
            try SkillTestFixtures.writeFile(dir, "SKILL.md", "main")
            let refs = dir.appendingPathComponent("references", isDirectory: true)
            try FileManager.default.createDirectory(at: refs, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                at: refs.appendingPathComponent("escape.md"),
                withDestinationURL: outside.appendingPathComponent("secret.md")
            )

            do {
                _ = try localResolver(root).resolve(
                    SkillConfig(name: "x", source: "./skills/x"),
                    declaringConfigDir: root,
                    security: nil
                )
                Issue.record("expected symlinkEscape")
            } catch let error as SkillError {
                guard case .symlinkEscape = error else {
                    Issue.record("wrong error: \(error)")
                    return
                }
            }
        }
    }

    @Test("local main body symlinked outside the skill directory is rejected")
    func localBodySymlinkEscapeRejected() throws {
        try SkillTestFixtures.withTempDir { root in
            let outside = root.appendingPathComponent("outside", isDirectory: true)
            try SkillTestFixtures.writeFile(outside, "secret.md", "TOP SECRET")
            let dir = root.appendingPathComponent("skills/x", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                at: dir.appendingPathComponent("SKILL.md"),
                withDestinationURL: outside.appendingPathComponent("secret.md")
            )

            do {
                _ = try localResolver(root).resolve(
                    SkillConfig(name: "x", source: "./skills/x"),
                    declaringConfigDir: root,
                    security: nil
                )
                Issue.record("expected symlinkEscape")
            } catch let error as SkillError {
                guard case .symlinkEscape = error else {
                    Issue.record("wrong error: \(error)")
                    return
                }
            }
        }
    }

    @Test("README.md fallback still inlines supporting markdown")
    func readmeFallbackInlinesReferences() throws {
        try SkillTestFixtures.withTempDir { root in
            let dir = root.appendingPathComponent("skills/x", isDirectory: true)
            try SkillTestFixtures.writeFile(dir, "README.md", "readme-body")
            try SkillTestFixtures.writeFile(
                dir.appendingPathComponent("references", isDirectory: true),
                "a.md",
                "ref-a"
            )

            let resolved = try localResolver(root).resolve(
                SkillConfig(name: "x", source: "./skills/x"),
                declaringConfigDir: root,
                security: nil
            )

            #expect(resolved.body.contains("readme-body"))
            #expect(resolved.body.contains("## Reference: references/a"))
            #expect(resolved.body.contains("ref-a"))
            // Body file itself must not be double-inlined as a reference.
            #expect(!resolved.body.contains("## Reference: README"))
        }
    }

    @Test("SKILL.md body is not double-inlined as a reference")
    func bodyNotDoubleInlined() throws {
        try SkillTestFixtures.withTempDir { root in
            let dir = root.appendingPathComponent("skills/x", isDirectory: true)
            try SkillTestFixtures.writeFile(dir, "SKILL.md", "main")
            try SkillTestFixtures.writeFile(
                dir.appendingPathComponent("references", isDirectory: true),
                "a.md",
                "ref-a"
            )

            let resolved = try localResolver(root).resolve(
                SkillConfig(name: "x", source: "./skills/x"),
                declaringConfigDir: root,
                security: nil
            )

            #expect(!resolved.body.contains("## Reference: SKILL"))
            // "main" appears exactly once: as the body. Never as a reference body.
            let occurrences = resolved.body.components(separatedBy: "main").count - 1
            #expect(occurrences == 1)
        }
    }

    @Test("files under .git/, .build/, node_modules/ are skipped")
    func wellKnownDirsSkipped() throws {
        try SkillTestFixtures.withTempDir { root in
            let dir = root.appendingPathComponent("skills/x", isDirectory: true)
            try SkillTestFixtures.writeFile(dir, "SKILL.md", "main")
            // None of these should be inlined.
            try SkillTestFixtures.writeFile(
                dir.appendingPathComponent(".git", isDirectory: true),
                "config.md",
                "git-config"
            )
            try SkillTestFixtures.writeFile(
                dir.appendingPathComponent(".build", isDirectory: true),
                "artifact.md",
                "build-artifact"
            )
            try SkillTestFixtures.writeFile(
                dir.appendingPathComponent("node_modules", isDirectory: true)
                    .appendingPathComponent("pkg", isDirectory: true),
                "readme.md",
                "vendored"
            )

            let resolved = try localResolver(root).resolve(
                SkillConfig(name: "x", source: "./skills/x"),
                declaringConfigDir: root,
                security: nil
            )

            #expect(resolved.body == "main")
            #expect(!resolved.body.contains("git-config"))
            #expect(!resolved.body.contains("build-artifact"))
            #expect(!resolved.body.contains("vendored"))
        }
    }
}
#endif
