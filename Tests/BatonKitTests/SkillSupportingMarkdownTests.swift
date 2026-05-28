#if !os(Windows)
// Windows is best-effort: these tests spawn subprocesses (git, POSIX coreutils)
// and create symlinks, both restricted on the Windows runner.
@testable import BatonKit
import Foundation
import Testing

/// Build a local-only resolver rooted at `root` (cache and `remotes/` siblings).
private func localResolver(
    _ root: URL,
    referencesBudgetBytes: Int = ConfigDefaults.referencesBudgetBytes
) -> SkillResolver {
    SkillTestFixtures.resolver(
        repoRoot: root,
        cacheDir: root.appendingPathComponent("cache"),
        remotesRoot: root,
        referencesBudgetBytes: referencesBudgetBytes
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
            let occurrences = resolved.body.components(separatedBy: "main").count - 1
            #expect(occurrences == 1)
        }
    }
}

// MARK: - Edge cases (extension-author surprises and budget)

struct SkillSupportingMarkdownEdgeCaseTests {
    @Test("same basename in different sub-paths is preserved separately")
    func sameBasenameDifferentPath() throws {
        try SkillTestFixtures.withTempDir { root in
            let dir = root.appendingPathComponent("skills/x", isDirectory: true)
            try SkillTestFixtures.writeFile(dir, "SKILL.md", "main")
            try SkillTestFixtures.writeFile(
                dir.appendingPathComponent("a", isDirectory: true),
                "x.md",
                "A/x body"
            )
            try SkillTestFixtures.writeFile(
                dir.appendingPathComponent("b", isDirectory: true),
                "x.md",
                "B/x body"
            )

            let resolved = try localResolver(root).resolve(
                SkillConfig(name: "x", source: "./skills/x"),
                declaringConfigDir: root,
                security: nil
            )

            #expect(resolved.body.contains("## Reference: a/x"))
            #expect(resolved.body.contains("## Reference: b/x"))
            #expect(resolved.body.contains("A/x body"))
            #expect(resolved.body.contains("B/x body"))
            let aLabel = try #require(resolved.body.range(of: "## Reference: a/x"))
            let bLabel = try #require(resolved.body.range(of: "## Reference: b/x"))
            #expect(aLabel.lowerBound < bLabel.lowerBound)
        }
    }

    @Test("references nested three levels deep are inlined with full relative path")
    func deeplyNestedReferences() throws {
        try SkillTestFixtures.withTempDir { root in
            let dir = root.appendingPathComponent("skills/x", isDirectory: true)
            try SkillTestFixtures.writeFile(dir, "SKILL.md", "main")
            let deep = dir
                .appendingPathComponent("docs", isDirectory: true)
                .appendingPathComponent("guides", isDirectory: true)
                .appendingPathComponent("advanced", isDirectory: true)
            try SkillTestFixtures.writeFile(deep, "topic.md", "deep-body")

            let resolved = try localResolver(root).resolve(
                SkillConfig(name: "x", source: "./skills/x"),
                declaringConfigDir: root,
                security: nil
            )

            #expect(resolved.body.contains("## Reference: docs/guides/advanced/topic"))
            #expect(resolved.body.contains("deep-body"))
        }
    }

    @Test("uppercase .MD extension is inlined and stripped from the label")
    func uppercaseMdExtension() throws {
        try SkillTestFixtures.withTempDir { root in
            let dir = root.appendingPathComponent("skills/x", isDirectory: true)
            try SkillTestFixtures.writeFile(dir, "SKILL.md", "main")
            try SkillTestFixtures.writeFile(
                dir.appendingPathComponent("references", isDirectory: true),
                "Notes.MD",
                "shouty"
            )

            let resolved = try localResolver(root).resolve(
                SkillConfig(name: "x", source: "./skills/x"),
                declaringConfigDir: root,
                security: nil
            )

            #expect(resolved.body.contains("## Reference: references/Notes"))
            #expect(!resolved.body.contains("references/Notes.MD"))
            #expect(resolved.body.contains("shouty"))
        }
    }

    @Test("non-UTF-8 reference file surfaces referenceReadFailed")
    func nonUTF8ReferenceFails() throws {
        try SkillTestFixtures.withTempDir { root in
            let dir = root.appendingPathComponent("skills/x", isDirectory: true)
            try SkillTestFixtures.writeFile(dir, "SKILL.md", "main")
            let refs = dir.appendingPathComponent("references", isDirectory: true)
            try FileManager.default.createDirectory(at: refs, withIntermediateDirectories: true)
            let bad = refs.appendingPathComponent("broken.md")
            try Data([0xFF, 0xFE, 0xFD, 0x00, 0xC3, 0x28]).write(to: bad)

            do {
                _ = try localResolver(root).resolve(
                    SkillConfig(name: "x", source: "./skills/x"),
                    declaringConfigDir: root,
                    security: nil
                )
                Issue.record("expected referenceReadFailed")
            } catch let error as SkillError {
                guard case let .referenceReadFailed(_, path, _) = error else {
                    Issue.record("wrong error: \(error)")
                    return
                }
                #expect(path.hasSuffix("broken.md"))
            }
        }
    }

    @Test("hidden directories like .vscode/.idea are skipped")
    func hiddenDirectoriesSkipped() throws {
        try SkillTestFixtures.withTempDir { root in
            let dir = root.appendingPathComponent("skills/x", isDirectory: true)
            try SkillTestFixtures.writeFile(dir, "SKILL.md", "main")
            try SkillTestFixtures.writeFile(
                dir.appendingPathComponent(".vscode", isDirectory: true),
                "notes.md",
                "vscode-notes"
            )
            try SkillTestFixtures.writeFile(
                dir.appendingPathComponent(".idea", isDirectory: true),
                "scratch.md",
                "idea-scratch"
            )
            try SkillTestFixtures.writeFile(dir, ".hidden.md", "dotfile")

            let resolved = try localResolver(root).resolve(
                SkillConfig(name: "x", source: "./skills/x"),
                declaringConfigDir: root,
                security: nil
            )

            #expect(resolved.body == "main")
            #expect(!resolved.body.contains("vscode-notes"))
            #expect(!resolved.body.contains("idea-scratch"))
            #expect(!resolved.body.contains("dotfile"))
        }
    }

    @Test("dangling symlink inside the skill directory is rejected")
    func danglingSymlinkRejected() throws {
        try SkillTestFixtures.withTempDir { root in
            let dir = root.appendingPathComponent("skills/x", isDirectory: true)
            try SkillTestFixtures.writeFile(dir, "SKILL.md", "main")
            let refs = dir.appendingPathComponent("references", isDirectory: true)
            try FileManager.default.createDirectory(at: refs, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                at: refs.appendingPathComponent("dangling.md"),
                withDestinationURL: refs.appendingPathComponent("does-not-exist.md")
            )

            do {
                _ = try localResolver(root).resolve(
                    SkillConfig(name: "x", source: "./skills/x"),
                    declaringConfigDir: root,
                    security: nil
                )
                Issue.record("expected symlinkEscape for dangling target")
            } catch let error as SkillError {
                guard case .symlinkEscape = error else {
                    Issue.record("wrong error: \(error)")
                    return
                }
            }
        }
    }

    @Test("cumulative references exceeding the configured byte budget are rejected")
    func referencesBudgetExceeded() throws {
        try SkillTestFixtures.withTempDir { root in
            let dir = root.appendingPathComponent("skills/x", isDirectory: true)
            try SkillTestFixtures.writeFile(dir, "SKILL.md", "main")
            let refs = dir.appendingPathComponent("references", isDirectory: true)
            // Two ~200 KB files sum to ~400 KB > the configured 256 KB budget.
            let chunk = String(repeating: "x", count: 200 * 1024)
            try SkillTestFixtures.writeFile(refs, "a.md", chunk)
            try SkillTestFixtures.writeFile(refs, "b.md", chunk)

            do {
                _ = try localResolver(root, referencesBudgetBytes: 256 * 1024).resolve(
                    SkillConfig(name: "x", source: "./skills/x"),
                    declaringConfigDir: root,
                    security: nil
                )
                Issue.record("expected referencesBudgetExceeded")
            } catch let error as SkillError {
                guard case let .referencesBudgetExceeded(_, limitBytes) = error else {
                    Issue.record("wrong error: \(error)")
                    return
                }
                #expect(limitBytes == 256 * 1024)
            }
        }
    }

    @Test("the default budget (1 MiB) admits references the old 256 KB cap rejected")
    func defaultBudgetAdmitsLargeReferences() throws {
        try SkillTestFixtures.withTempDir { root in
            let dir = root.appendingPathComponent("skills/x", isDirectory: true)
            try SkillTestFixtures.writeFile(dir, "SKILL.md", "main")
            let refs = dir.appendingPathComponent("references", isDirectory: true)
            // ~400 KB total: over the legacy 256 KB cap, comfortably under the 1 MiB default.
            let chunk = String(repeating: "x", count: 200 * 1024)
            try SkillTestFixtures.writeFile(refs, "a.md", chunk)
            try SkillTestFixtures.writeFile(refs, "b.md", chunk)

            let resolved = try localResolver(root).resolve(
                SkillConfig(name: "x", source: "./skills/x"),
                declaringConfigDir: root,
                security: nil
            )

            #expect(resolved.body.contains("## Reference: references/a"))
            #expect(resolved.body.contains("## Reference: references/b"))
        }
    }

    @Test("files under .git/, .build/, node_modules/ are skipped")
    func wellKnownDirsSkipped() throws {
        try SkillTestFixtures.withTempDir { root in
            let dir = root.appendingPathComponent("skills/x", isDirectory: true)
            try SkillTestFixtures.writeFile(dir, "SKILL.md", "main")
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
