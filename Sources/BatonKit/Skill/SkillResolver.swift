import Foundation

/// Resolves a ``SkillConfig`` into a ``ResolvedSkill`` — reading the body from a
/// local path or a SHA-pinned remote repository, enforcing the skill-security
/// policy (mandatory pinning, source allowlist, symlink-escape rejection).
///
/// The resolver is independent of prompt assembly: it returns the raw markdown
/// body. Embedding that body inside a delimited untrusted block is the caller's
/// responsibility (see ``ResolvedSkill``).
public struct SkillResolver: Sendable {
    /// The repository root (used as the `GitRunner` working directory for clones).
    private let repoRoot: URL
    /// The directory where remote skill checkouts are cached.
    private let cacheDir: URL
    /// A `GitRunner` whose `repoRoot` is the repository under review (used to detect
    /// `git` availability; clone runs use a runner pointed at the clone directory).
    private let git: GitRunner
    /// Whether `--allow-unpinned` was passed, bypassing mandatory SHA pinning.
    private let allowUnpinned: Bool
    /// Maps an `owner/repo` reference to a clone URL. Overridable for testing.
    private let urlMapping: @Sendable (_ owner: String, _ repo: String) -> String

    public init(
        repoRoot: URL,
        cacheDir: URL,
        git: GitRunner,
        allowUnpinned: Bool = false
    ) {
        self.init(
            repoRoot: repoRoot,
            cacheDir: cacheDir,
            git: git,
            allowUnpinned: allowUnpinned,
            urlMapping: { owner, repo in "https://github.com/\(owner)/\(repo).git" }
        )
    }

    /// Internal initializer that injects a custom `owner/repo` → URL mapping so tests
    /// can point remote sources at on-disk `file://` repositories.
    init(
        repoRoot: URL,
        cacheDir: URL,
        git: GitRunner,
        allowUnpinned: Bool = false,
        urlMapping: @escaping @Sendable (_ owner: String, _ repo: String) -> String
    ) {
        self.repoRoot = repoRoot
        self.cacheDir = cacheDir
        self.git = git
        self.allowUnpinned = allowUnpinned
        self.urlMapping = urlMapping
    }

    /// The default cache directory: `$BATON_CACHE_DIR` or `~/.cache/baton/skills`.
    public static func defaultCacheDir(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment["BATON_CACHE_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
                .appendingPathComponent("skills", isDirectory: true)
        }
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        return home
            .appendingPathComponent(".cache", isDirectory: true)
            .appendingPathComponent("baton", isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
    }

    /// Resolve `skill` declared by the `baton.toml` at `declaringConfigDir`, honoring
    /// the root-scope `security` policy.
    public func resolve(
        _ skill: SkillConfig,
        declaringConfigDir: URL,
        security: SecurityConfig?
    ) throws -> ResolvedSkill {
        switch SkillSource.classify(skill.source) {
        case let .local(path):
            try resolveLocal(skill, path: path, declaringConfigDir: declaringConfigDir)
        case let .remote(owner, repo, skillSegment):
            try resolveRemote(
                skill,
                owner: owner,
                repo: repo,
                skillSegment: skillSegment,
                security: security
            )
        }
    }

    // MARK: - Local

    private func resolveLocal(
        _ skill: SkillConfig,
        path: String,
        declaringConfigDir: URL
    ) throws -> ResolvedSkill {
        let fileManager = FileManager.default
        let expanded = (path as NSString).expandingTildeInPath
        var base = if expanded.hasPrefix("/") {
            URL(fileURLWithPath: expanded, isDirectory: true)
        } else {
            URL(fileURLWithPath: expanded, isDirectory: true, relativeTo: declaringConfigDir)
        }
        if let subpath = skill.subpath, !subpath.isEmpty {
            base = base.appendingPathComponent(subpath, isDirectory: true)
        }
        let dir = base.standardizedFileURL

        guard let bodyURL = bodyFileURL(in: dir, fileManager: fileManager) else {
            throw SkillError.missingSkillFile(name: skill.name, searchedPath: dir.path)
        }
        let body = try readBody(bodyURL, skillName: skill.name)
        return ResolvedSkill(
            name: skill.name,
            body: body,
            sourceDescription: "local: \(dir.path)"
        )
    }

    // MARK: - Remote

    private func resolveRemote(
        _ skill: SkillConfig,
        owner: String,
        repo: String,
        skillSegment: String?,
        security: SecurityConfig?
    ) throws -> ResolvedSkill {
        // 1. Allowlist (remote-only).
        if let allowlist = security?.allowedSkillSources, !allowlist.isEmpty {
            guard Glob.matchesAny(allowlist, path: skill.source) else {
                throw SkillError.sourceNotAllowed(
                    name: skill.name,
                    source: skill.source,
                    allowlist: allowlist
                )
            }
        }

        // 2. Mandatory SHA pinning (remote-only).
        let pinningRequired = (security?.requirePinnedSkills ?? true) && !allowUnpinned
        if pinningRequired, skill.ref == nil || skill.ref?.isEmpty == true {
            throw SkillError.missingRequiredRef(name: skill.name, source: skill.source)
        }

        // 3. git availability.
        guard gitAvailable() else {
            throw SkillError.gitUnavailable(name: skill.name)
        }

        // 4. Clone (reusing the cache when the ref is already checked out).
        let cloneURL = urlMapping(owner, repo)
        let checkout = try ensureClone(
            skill: skill,
            owner: owner,
            repo: repo,
            cloneURL: cloneURL
        )

        // 5. Locate the skill directory (subpath, then skills.sh fallback).
        let skillDir = try locateRemoteSkillDir(
            skill: skill,
            repo: repo,
            skillSegment: skillSegment,
            checkout: checkout
        )

        // 6. Find body file.
        let fileManager = FileManager.default
        guard let bodyURL = bodyFileURL(in: skillDir, fileManager: fileManager) else {
            throw SkillError.missingSkillFile(name: skill.name, searchedPath: skillDir.path)
        }

        // 7. Symlink-escape check against the checkout root.
        try assertNoSymlinkEscape(bodyURL, within: checkout, skillName: skill.name)

        let body = try readBody(bodyURL, skillName: skill.name)
        return ResolvedSkill(
            name: skill.name,
            body: body,
            sourceDescription: "remote: \(skill.source)\(skill.ref.map { "@\($0)" } ?? "")"
        )
    }

    /// Clone `cloneURL` into the cache at the pinned SHA (or HEAD), reusing an existing
    /// checkout when the ref is already present.
    private func ensureClone(
        skill: SkillConfig,
        owner: String,
        repo: String,
        cloneURL: String
    ) throws -> URL {
        let fileManager = FileManager.default
        let refToken = skill.ref?.isEmpty == false ? skill.ref! : "head"
        let dirName = "\(owner)__\(repo)__\(refToken)"
        let dest = cacheDir.appendingPathComponent(dirName, isDirectory: true)
        let destGit = GitRunner(repoRoot: dest)

        // Cache reuse: a pinned ref already checked out needs no re-clone.
        if fileManager.fileExists(atPath: dest.appendingPathComponent(".git").path) {
            if let ref = skill.ref, !ref.isEmpty {
                if destGit.refExists(ref) {
                    return dest
                }
            } else {
                // Unpinned HEAD checkout: reuse whatever was cloned.
                return dest
            }
            // Stale/incomplete checkout — start clean.
            try? fileManager.removeItem(at: dest)
        }

        try fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        if let ref = skill.ref, !ref.isEmpty {
            try cloneAtSHA(ref: ref, cloneURL: cloneURL, dest: dest, skill: skill)
        } else {
            try cloneHead(cloneURL: cloneURL, dest: dest, skill: skill)
        }
        return dest
    }

    /// Shallow-clone the default branch HEAD into `dest`.
    private func cloneHead(cloneURL: String, dest: URL, skill: SkillConfig) throws {
        let runner = GitRunner(repoRoot: repoRoot)
        do {
            _ = try runner.run(["clone", "--depth", "1", cloneURL, dest.path])
        } catch let error as GitError {
            try mapCloneError(error, skill: skill)
        }
    }

    /// Fetch and check out a specific commit SHA into `dest`.
    ///
    /// Uses `git init` + `fetch --depth 1 origin <sha>` so we can pin to a commit
    /// without cloning entire history; falls back to a full fetch when the remote
    /// does not allow fetching an arbitrary SHA shallowly.
    private func cloneAtSHA(ref: String, cloneURL: String, dest: URL, skill: SkillConfig) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: dest, withIntermediateDirectories: true)
        let runner = GitRunner(repoRoot: dest)
        do {
            _ = try runner.run(["init", "-q"])
            _ = try runner.run(["remote", "add", "origin", cloneURL])
            // Try shallow fetch of the exact SHA first.
            let shallow = try runner.capture(["fetch", "--depth", "1", "origin", ref])
            if shallow.status != 0 {
                // Fall back to a full fetch (some servers reject by-SHA shallow fetch).
                let full = try runner.capture(["fetch", "origin"])
                if full.status != 0 {
                    // Could be a bad URL/repo, or the SHA truly missing.
                    if !runner.refExists(ref) {
                        try? fileManager.removeItem(at: dest)
                        throw SkillError.cloneFailed(
                            name: skill.name,
                            source: skill.source,
                            underlying: full.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    }
                }
            }
            guard runner.refExists(ref) else {
                throw SkillError.refNotFound(name: skill.name, source: skill.source, ref: ref)
            }
            _ = try runner.run(["checkout", "-q", ref])
        } catch let error as GitError {
            try? fileManager.removeItem(at: dest)
            try mapCloneError(error, skill: skill)
        }
    }

    /// Map a `GitError` from a clone/fetch into the appropriate ``SkillError``.
    private func mapCloneError(_ error: GitError, skill: SkillConfig) throws -> Never {
        switch error {
        case .gitUnavailable:
            throw SkillError.gitUnavailable(name: skill.name)
        case let .commandFailed(_, _, stderr):
            throw SkillError.cloneFailed(name: skill.name, source: skill.source, underlying: stderr)
        default:
            throw SkillError.cloneFailed(
                name: skill.name,
                source: skill.source,
                underlying: error.errorDescription ?? "clone failed"
            )
        }
    }

    /// Determine the skill directory within a cloned repository, applying `subpath`
    /// when present, otherwise the skills.sh lookup order, otherwise the repo root.
    private func locateRemoteSkillDir(
        skill: SkillConfig,
        repo: String,
        skillSegment: String?,
        checkout: URL
    ) throws -> URL {
        let fileManager = FileManager.default

        if let subpath = skill.subpath, !subpath.isEmpty {
            let dir = checkout.appendingPathComponent(subpath, isDirectory: true)
            guard isDirectory(dir, fileManager: fileManager) else {
                throw SkillError.subpathMissing(
                    name: skill.name,
                    source: skill.source,
                    expectedPath: dir.path
                )
            }
            return dir
        }

        if let skillSegment, !skillSegment.isEmpty {
            // skills.sh convention: try <repo>/skills/<name> then <repo>/<name>.
            let candidates = [
                checkout
                    .appendingPathComponent("skills", isDirectory: true)
                    .appendingPathComponent(skillSegment, isDirectory: true),
                checkout.appendingPathComponent(skillSegment, isDirectory: true),
            ]
            if let found = candidates.first(where: { isDirectory($0, fileManager: fileManager) }) {
                return found
            }
            throw SkillError.subpathMissing(
                name: skill.name,
                source: skill.source,
                expectedPath: candidates[0].path
            )
        }

        // owner/repo with no subpath: body is at the repository root.
        return checkout
    }

    // MARK: - File helpers

    /// Return the body file URL (`SKILL.md` preferred, then `README.md`) in `dir`,
    /// or `nil` when neither exists.
    private func bodyFileURL(in dir: URL, fileManager: FileManager) -> URL? {
        for candidate in ["SKILL.md", "README.md"] {
            let url = dir.appendingPathComponent(candidate)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private func readBody(_ url: URL, skillName: String) throws -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw SkillError.missingSkillFile(name: skillName, searchedPath: url.deletingLastPathComponent().path)
        }
    }

    private func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Reject a body file that resolves, through symlinks, to a path outside `base`.
    private func assertNoSymlinkEscape(_ url: URL, within base: URL, skillName: String) throws {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let resolvedBase = base.resolvingSymlinksInPath().standardizedFileURL
        var basePath = resolvedBase.path
        if !basePath.hasSuffix("/") {
            basePath += "/"
        }
        guard resolved.path == resolvedBase.path || resolved.path.hasPrefix(basePath) else {
            throw SkillError.symlinkEscape(name: skillName, path: resolved.path)
        }
    }

    /// Whether `git` is invokable (independent of the repository working directory).
    ///
    /// Probes the injected ``git`` runner first when its working directory exists, so
    /// a custom executable is honored; otherwise probes from a directory guaranteed to
    /// exist so a missing working directory is not mistaken for a missing `git`.
    private func gitAvailable() -> Bool {
        if FileManager.default.fileExists(atPath: git.repoRoot.path),
           let output = try? git.capture(["--version"])
        {
            return output.status == 0
        }
        let probeDir = FileManager.default.fileExists(atPath: repoRoot.path)
            ? repoRoot
            : URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let probe = GitRunner(repoRoot: probeDir)
        return (try? probe.capture(["--version"]))?.status == 0
    }
}
