#if !os(Windows)
// Windows is best-effort: these tests spawn subprocesses (git / POSIX coreutils
// like echo, cat / a /bin/sh fixture) that are unavailable on the Windows runner.
@testable import BatonKit
import Foundation
import Testing

/// Shared fixtures for the skill-resolution test suites.
enum SkillTestFixtures {
    /// Build a throwaway directory tree, run `body`, and clean up.
    static func withTempDir(_ body: (URL) throws -> Void) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("baton-skill-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    /// Create a directory and write a file inside it.
    static func writeFile(_ dir: URL, _ name: String, _ contents: String) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try contents.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    /// Initialize a git repository at `dir` with a deterministic identity.
    @discardableResult
    static func initRepo(_ dir: URL) throws -> GitRunner {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let git = GitRunner(repoRoot: dir)
        _ = try git.run(["init", "-q", "-b", "main"])
        _ = try git.run(["config", "user.email", "test@example.com"])
        _ = try git.run(["config", "user.name", "Test"])
        _ = try git.run(["config", "commit.gpgsign", "false"])
        // Allow by-SHA shallow fetches against this on-disk "remote".
        _ = try git.run(["config", "uploadpack.allowAnySHA1InWant", "true"])
        _ = try git.run(["config", "uploadpack.allowReachableSHA1InWant", "true"])
        return git
    }

    /// Commit the current tree and return the resulting commit SHA.
    static func commitAll(_ git: GitRunner, message: String = "commit") throws -> String {
        _ = try git.run(["add", "."])
        _ = try git.run(["commit", "-q", "-m", message])
        return try git.revParse("HEAD")
    }

    /// A resolver whose `owner/repo` references map to on-disk `file://` repositories
    /// under `remotesRoot/<owner>/<repo>`.
    static func resolver(
        repoRoot: URL,
        cacheDir: URL,
        remotesRoot: URL,
        allowUnpinned: Bool = false
    ) -> SkillResolver {
        SkillResolver(
            repoRoot: repoRoot,
            cacheDir: cacheDir,
            git: GitRunner(repoRoot: repoRoot),
            allowUnpinned: allowUnpinned,
            urlMapping: { owner, repo in
                let path = remotesRoot
                    .appendingPathComponent(owner, isDirectory: true)
                    .appendingPathComponent(repo, isDirectory: true)
                return "file://\(path.path)"
            }
        )
    }

    /// Convenience: a resolver and remotes-root sharing a temp `root`.
    static func remoteResolver(root: URL, allowUnpinned: Bool = false) -> SkillResolver {
        resolver(
            repoRoot: root,
            cacheDir: root.appendingPathComponent("cache"),
            remotesRoot: root.appendingPathComponent("remotes"),
            allowUnpinned: allowUnpinned
        )
    }
}

// MARK: - SkillSource classification & cache dir

struct SkillSourceTests {
    @Test("classify distinguishes local and remote sources")
    func classify() {
        #expect(SkillSource.classify("./skills/x") == .local(path: "./skills/x"))
        #expect(SkillSource.classify("../shared") == .local(path: "../shared"))
        #expect(SkillSource.classify("/abs/path") == .local(path: "/abs/path"))
        #expect(SkillSource.classify("~/skills") == .local(path: "~/skills"))
        #expect(SkillSource.classify("org/skills") == .remote(owner: "org", repo: "skills", skill: nil))
        #expect(SkillSource.classify("org/skills/owasp") == .remote(owner: "org", repo: "skills", skill: "owasp"))
    }

    @Test("defaultCacheDir honors BATON_CACHE_DIR")
    func defaultCacheDirOverride() {
        let url = SkillResolver.defaultCacheDir(environment: ["BATON_CACHE_DIR": "/tmp/batoncache"])
        #expect(url.path == "/tmp/batoncache/skills")
    }

    @Test("defaultCacheDir falls back to ~/.cache/baton/skills")
    func defaultCacheDirFallback() {
        let url = SkillResolver.defaultCacheDir(environment: [:])
        #expect(url.path.hasSuffix("/.cache/baton/skills"))
    }
}

// MARK: - Local resolution

struct LocalSkillResolverTests {
    @Test("local source resolves relative to the declaring baton.toml directory")
    func localRelative() throws {
        try SkillTestFixtures.withTempDir { root in
            // ios/baton.toml declares ./skills/style -> ios/skills/style/SKILL.md
            let iosDir = root.appendingPathComponent("ios", isDirectory: true)
            let styleDir = iosDir.appendingPathComponent("skills/style", isDirectory: true)
            try SkillTestFixtures.writeFile(styleDir, "SKILL.md", "# Style guide")

            let r = SkillTestFixtures.resolver(
                repoRoot: root,
                cacheDir: root.appendingPathComponent("cache"),
                remotesRoot: root
            )
            let skill = SkillConfig(name: "style", source: "./skills/style")
            let resolved = try r.resolve(skill, declaringConfigDir: iosDir, security: nil)
            #expect(resolved.name == "style")
            #expect(resolved.body == "# Style guide")
        }
    }

    @Test("local source prefers SKILL.md over README.md")
    func localPrefersSkillMd() throws {
        try SkillTestFixtures.withTempDir { root in
            let dir = root.appendingPathComponent("skills/x", isDirectory: true)
            try SkillTestFixtures.writeFile(dir, "SKILL.md", "from-skill")
            try SkillTestFixtures.writeFile(dir, "README.md", "from-readme")
            let r = SkillTestFixtures.resolver(
                repoRoot: root,
                cacheDir: root.appendingPathComponent("cache"),
                remotesRoot: root
            )
            let resolved = try r.resolve(
                SkillConfig(name: "x", source: "./skills/x"),
                declaringConfigDir: root,
                security: nil
            )
            #expect(resolved.body == "from-skill")
        }
    }

    @Test("local source falls back to README.md when SKILL.md is absent")
    func localReadmeFallback() throws {
        try SkillTestFixtures.withTempDir { root in
            let dir = root.appendingPathComponent("skills/x", isDirectory: true)
            try SkillTestFixtures.writeFile(dir, "README.md", "from-readme")
            let r = SkillTestFixtures.resolver(
                repoRoot: root,
                cacheDir: root.appendingPathComponent("cache"),
                remotesRoot: root
            )
            let resolved = try r.resolve(
                SkillConfig(name: "x", source: "./skills/x"),
                declaringConfigDir: root,
                security: nil
            )
            #expect(resolved.body == "from-readme")
        }
    }

    @Test("local source missing both SKILL.md and README.md fails")
    func localMissingFails() throws {
        try SkillTestFixtures.withTempDir { root in
            let dir = root.appendingPathComponent("skills/x", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let r = SkillTestFixtures.resolver(
                repoRoot: root,
                cacheDir: root.appendingPathComponent("cache"),
                remotesRoot: root
            )
            #expect(throws: SkillError.self) {
                _ = try r.resolve(
                    SkillConfig(name: "x", source: "./skills/x"),
                    declaringConfigDir: root,
                    security: nil
                )
            }
        }
    }

    @Test("subpath narrows the local resolved directory")
    func localSubpath() throws {
        try SkillTestFixtures.withTempDir { root in
            // ../shared with subpath skills/owasp
            let target = root.appendingPathComponent("shared/skills/owasp", isDirectory: true)
            try SkillTestFixtures.writeFile(target, "SKILL.md", "owasp-body")
            let declaringDir = root.appendingPathComponent("ios", isDirectory: true)
            try FileManager.default.createDirectory(at: declaringDir, withIntermediateDirectories: true)
            let r = SkillTestFixtures.resolver(
                repoRoot: root,
                cacheDir: root.appendingPathComponent("cache"),
                remotesRoot: root
            )
            let resolved = try r.resolve(
                SkillConfig(name: "owasp", source: "../shared", subpath: "skills/owasp"),
                declaringConfigDir: declaringDir,
                security: nil
            )
            #expect(resolved.body == "owasp-body")
        }
    }

    @Test("local skill is exempt from pin enforcement and allowlist")
    func localExempt() throws {
        try SkillTestFixtures.withTempDir { root in
            let dir = root.appendingPathComponent("skills/x", isDirectory: true)
            try SkillTestFixtures.writeFile(dir, "SKILL.md", "local-body")
            let r = SkillTestFixtures.resolver(
                repoRoot: root,
                cacheDir: root.appendingPathComponent("cache"),
                remotesRoot: root
            )
            // Pinning required + restrictive allowlist; a local skill must still resolve.
            let security = SecurityConfig(requirePinnedSkills: true, allowedSkillSources: ["org/*"])
            let resolved = try r.resolve(
                SkillConfig(name: "x", source: "./skills/x"),
                declaringConfigDir: root,
                security: security
            )
            #expect(resolved.body == "local-body")
        }
    }
}

// MARK: - Remote resolution & cache reuse

struct RemoteSkillResolverTests {
    @Test("remote owner/repo/skill resolves via skills.sh skills/<name> path")
    func remoteSkillsSubdir() throws {
        try SkillTestFixtures.withTempDir { root in
            let remote = root.appendingPathComponent("remotes/org/skills", isDirectory: true)
            let git = try SkillTestFixtures.initRepo(remote)
            try SkillTestFixtures.writeFile(
                remote.appendingPathComponent("skills/owasp"),
                "SKILL.md",
                "owasp-remote"
            )
            let sha = try SkillTestFixtures.commitAll(git)

            let r = SkillTestFixtures.remoteResolver(root: root)
            let resolved = try r.resolve(
                SkillConfig(name: "owasp", source: "org/skills/owasp", ref: sha),
                declaringConfigDir: root,
                security: nil
            )
            #expect(resolved.body == "owasp-remote")
        }
    }

    @Test("remote owner/repo/skill falls back to <repo>/<name> when skills/<name> is absent")
    func remoteSkillsFallback() throws {
        try SkillTestFixtures.withTempDir { root in
            let remote = root.appendingPathComponent("remotes/org/skills", isDirectory: true)
            let git = try SkillTestFixtures.initRepo(remote)
            // No skills/ dir; skill lives at repo-root/<name>.
            try SkillTestFixtures.writeFile(remote.appendingPathComponent("owasp"), "SKILL.md", "owasp-fallback")
            let sha = try SkillTestFixtures.commitAll(git)

            let r = SkillTestFixtures.remoteResolver(root: root)
            let resolved = try r.resolve(
                SkillConfig(name: "owasp", source: "org/skills/owasp", ref: sha),
                declaringConfigDir: root,
                security: nil
            )
            #expect(resolved.body == "owasp-fallback")
        }
    }

    @Test("remote owner/repo reads body from repository root, README.md fallback")
    func remoteRootReadme() throws {
        try SkillTestFixtures.withTempDir { root in
            let remote = root.appendingPathComponent("remotes/org/skills", isDirectory: true)
            let git = try SkillTestFixtures.initRepo(remote)
            try SkillTestFixtures.writeFile(remote, "README.md", "root-readme")
            let sha = try SkillTestFixtures.commitAll(git)

            let r = SkillTestFixtures.remoteResolver(root: root)
            let resolved = try r.resolve(
                SkillConfig(name: "skills", source: "org/skills", ref: sha),
                declaringConfigDir: root,
                security: nil
            )
            #expect(resolved.body == "root-readme")
        }
    }

    @Test("remote subpath overrides skills.sh lookup")
    func remoteSubpath() throws {
        try SkillTestFixtures.withTempDir { root in
            let remote = root.appendingPathComponent("remotes/org/skills", isDirectory: true)
            let git = try SkillTestFixtures.initRepo(remote)
            try SkillTestFixtures.writeFile(
                remote.appendingPathComponent("custom/place"),
                "SKILL.md",
                "custom-body"
            )
            let sha = try SkillTestFixtures.commitAll(git)

            let r = SkillTestFixtures.remoteResolver(root: root)
            let resolved = try r.resolve(
                SkillConfig(name: "x", source: "org/skills/owasp", ref: sha, subpath: "custom/place"),
                declaringConfigDir: root,
                security: nil
            )
            #expect(resolved.body == "custom-body")
        }
    }

    @Test("remote subpath that does not exist fails")
    func remoteSubpathMissing() throws {
        try SkillTestFixtures.withTempDir { root in
            let remote = root.appendingPathComponent("remotes/org/skills", isDirectory: true)
            let git = try SkillTestFixtures.initRepo(remote)
            try SkillTestFixtures.writeFile(remote, "SKILL.md", "root")
            let sha = try SkillTestFixtures.commitAll(git)

            let r = SkillTestFixtures.remoteResolver(root: root)
            #expect(throws: SkillError.self) {
                _ = try r.resolve(
                    SkillConfig(name: "x", source: "org/skills", ref: sha, subpath: "nope/here"),
                    declaringConfigDir: root,
                    security: nil
                )
            }
        }
    }

    @Test("cache is reused for an already-cloned ref")
    func remoteCacheReuse() throws {
        try SkillTestFixtures.withTempDir { root in
            let remote = root.appendingPathComponent("remotes/org/skills", isDirectory: true)
            let git = try SkillTestFixtures.initRepo(remote)
            try SkillTestFixtures.writeFile(remote.appendingPathComponent("skills/owasp"), "SKILL.md", "v1")
            let sha = try SkillTestFixtures.commitAll(git)

            let cacheDir = root.appendingPathComponent("cache")
            let r = SkillTestFixtures.remoteResolver(root: root)
            let skill = SkillConfig(name: "owasp", source: "org/skills/owasp", ref: sha)
            _ = try r.resolve(skill, declaringConfigDir: root, security: nil)

            // Mutate the cached checkout; a reuse must read the cached (mutated) copy,
            // proving no re-clone happened.
            let cachedFile = cacheDir
                .appendingPathComponent("org__skills__\(sha)", isDirectory: true)
                .appendingPathComponent("skills/owasp/SKILL.md")
            #expect(FileManager.default.fileExists(atPath: cachedFile.path))
            try "mutated".write(to: cachedFile, atomically: true, encoding: .utf8)

            let again = try r.resolve(skill, declaringConfigDir: root, security: nil)
            #expect(again.body == "mutated")
        }
    }
}

// MARK: - Pin enforcement

struct SkillPinEnforcementTests {
    @Test("unpinned remote skill is rejected by default with the right recovery suggestion")
    func unpinnedRejected() throws {
        try SkillTestFixtures.withTempDir { root in
            let remote = root.appendingPathComponent("remotes/org/skills", isDirectory: true)
            let git = try SkillTestFixtures.initRepo(remote)
            try SkillTestFixtures.writeFile(remote.appendingPathComponent("skills/owasp"), "SKILL.md", "x")
            _ = try SkillTestFixtures.commitAll(git)

            let r = SkillTestFixtures.remoteResolver(root: root)
            let skill = SkillConfig(name: "owasp", source: "org/skills/owasp")
            do {
                _ = try r.resolve(skill, declaringConfigDir: root, security: nil)
                Issue.record("expected missingRequiredRef")
            } catch let error as SkillError {
                guard case .missingRequiredRef = error else {
                    Issue.record("wrong error: \(error)")
                    return
                }
                let suggestion = try #require(error.recoverySuggestion)
                #expect(suggestion.contains("ref"))
                #expect(suggestion.contains("--allow-unpinned"))
            }
        }
    }

    @Test("--allow-unpinned bypasses the pin requirement")
    func allowUnpinnedBypass() throws {
        try SkillTestFixtures.withTempDir { root in
            let remote = root.appendingPathComponent("remotes/org/skills", isDirectory: true)
            let git = try SkillTestFixtures.initRepo(remote)
            try SkillTestFixtures.writeFile(remote.appendingPathComponent("skills/owasp"), "SKILL.md", "head-body")
            _ = try SkillTestFixtures.commitAll(git)

            let r = SkillTestFixtures.remoteResolver(root: root, allowUnpinned: true)
            let resolved = try r.resolve(
                SkillConfig(name: "owasp", source: "org/skills/owasp"),
                declaringConfigDir: root,
                security: nil
            )
            #expect(resolved.body == "head-body")
        }
    }

    @Test("pinned remote skill with a valid SHA resolves")
    func pinnedResolves() throws {
        try SkillTestFixtures.withTempDir { root in
            let remote = root.appendingPathComponent("remotes/org/skills", isDirectory: true)
            let git = try SkillTestFixtures.initRepo(remote)
            try SkillTestFixtures.writeFile(
                remote.appendingPathComponent("skills/owasp"),
                "SKILL.md",
                "pinned-body"
            )
            let sha = try SkillTestFixtures.commitAll(git)

            let r = SkillTestFixtures.remoteResolver(root: root)
            let resolved = try r.resolve(
                SkillConfig(name: "owasp", source: "org/skills/owasp", ref: sha),
                declaringConfigDir: root,
                security: SecurityConfig(requirePinnedSkills: true)
            )
            #expect(resolved.body == "pinned-body")
        }
    }

    @Test("pinned remote skill with a non-existent SHA fails")
    func pinnedBadShaFails() throws {
        try SkillTestFixtures.withTempDir { root in
            let remote = root.appendingPathComponent("remotes/org/skills", isDirectory: true)
            let git = try SkillTestFixtures.initRepo(remote)
            try SkillTestFixtures.writeFile(remote.appendingPathComponent("skills/owasp"), "SKILL.md", "x")
            _ = try SkillTestFixtures.commitAll(git)

            let r = SkillTestFixtures.remoteResolver(root: root)
            #expect(throws: SkillError.self) {
                _ = try r.resolve(
                    SkillConfig(
                        name: "owasp",
                        source: "org/skills/owasp",
                        ref: "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
                    ),
                    declaringConfigDir: root,
                    security: nil
                )
            }
        }
    }
}

// MARK: - Allowlist & symlink escape

struct SkillSecurityTests {
    @Test("remote source outside the allowlist is rejected")
    func allowlistRejects() throws {
        try SkillTestFixtures.withTempDir { root in
            // The remote exists, but the allowlist must reject before/regardless of clone.
            let remote = root.appendingPathComponent("remotes/attacker/evil", isDirectory: true)
            let git = try SkillTestFixtures.initRepo(remote)
            try SkillTestFixtures.writeFile(remote, "SKILL.md", "evil")
            let sha = try SkillTestFixtures.commitAll(git)

            let r = SkillTestFixtures.remoteResolver(root: root)
            let security = SecurityConfig(allowedSkillSources: ["org/*", "trusted/skills"])
            do {
                _ = try r.resolve(
                    SkillConfig(name: "evil", source: "attacker/evil", ref: sha),
                    declaringConfigDir: root,
                    security: security
                )
                Issue.record("expected sourceNotAllowed")
            } catch let error as SkillError {
                guard case .sourceNotAllowed = error else {
                    Issue.record("wrong error: \(error)")
                    return
                }
                let suggestion = try #require(error.recoverySuggestion)
                #expect(suggestion.contains("allowed_skill_sources"))
            }
        }
    }

    @Test("remote source matching a glob pattern is allowed")
    func allowlistAccepts() throws {
        try SkillTestFixtures.withTempDir { root in
            let remote = root.appendingPathComponent("remotes/org/skills", isDirectory: true)
            let git = try SkillTestFixtures.initRepo(remote)
            try SkillTestFixtures.writeFile(remote, "SKILL.md", "allowed-body")
            let sha = try SkillTestFixtures.commitAll(git)

            let r = SkillTestFixtures.remoteResolver(root: root)
            let resolved = try r.resolve(
                SkillConfig(name: "skills", source: "org/skills", ref: sha),
                declaringConfigDir: root,
                security: SecurityConfig(allowedSkillSources: ["org/*"])
            )
            #expect(resolved.body == "allowed-body")
        }
    }

    @Test("allowlist does not apply to local sources")
    func allowlistBypassedForLocal() throws {
        try SkillTestFixtures.withTempDir { root in
            let dir = root.appendingPathComponent("skills/x", isDirectory: true)
            try SkillTestFixtures.writeFile(dir, "SKILL.md", "local")
            let r = SkillTestFixtures.resolver(
                repoRoot: root,
                cacheDir: root.appendingPathComponent("cache"),
                remotesRoot: root
            )
            let resolved = try r.resolve(
                SkillConfig(name: "x", source: "./skills/x"),
                declaringConfigDir: root,
                security: SecurityConfig(allowedSkillSources: ["org/*"])
            )
            #expect(resolved.body == "local")
        }
    }

    @Test("symlink escape inside a cloned skill repo is rejected")
    func symlinkEscapeRejected() throws {
        try SkillTestFixtures.withTempDir { root in
            // A secret file outside the repo; the repo's SKILL.md symlinks to it.
            let outside = root.appendingPathComponent("outside", isDirectory: true)
            try SkillTestFixtures.writeFile(outside, "secret.md", "TOP SECRET")

            let remote = root.appendingPathComponent("remotes/org/skills", isDirectory: true)
            let git = try SkillTestFixtures.initRepo(remote)
            let skillDir = remote.appendingPathComponent("skills/owasp", isDirectory: true)
            try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                at: skillDir.appendingPathComponent("SKILL.md"),
                withDestinationURL: outside.appendingPathComponent("secret.md")
            )
            // git tracks symlinks; add and commit it.
            let sha = try SkillTestFixtures.commitAll(git)

            let r = SkillTestFixtures.remoteResolver(root: root)
            do {
                _ = try r.resolve(
                    SkillConfig(name: "owasp", source: "org/skills/owasp", ref: sha),
                    declaringConfigDir: root,
                    security: nil
                )
                Issue.record("expected symlinkEscape")
            } catch let error as SkillError {
                guard case .symlinkEscape = error else {
                    Issue.record("wrong error: \(error)")
                    return
                }
                let suggestion = try #require(error.recoverySuggestion)
                #expect(suggestion.contains("symlink"))
            }
        }
    }
}

// swiftlint:enable file_length
#endif
