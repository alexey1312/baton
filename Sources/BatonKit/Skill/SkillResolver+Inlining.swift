import Foundation

extension SkillResolver {
    /// Cumulative byte budget for inlined supporting markdown per skill. Baton sends the
    /// resolved body to a headless agent (`claude --print`, codex/gemini/opencode); an
    /// unbounded walk could silently fill the context window or OOM the agent. The
    /// budget is unconditional — narrow the skill via `subpath` or split the bundle.
    static let referencesBudgetBytes: Int = 256 * 1024

    /// `SKILL.md` first, then `README.md`. `nil` when neither exists.
    func bodyFileURL(in dir: URL, fileManager: FileManager) -> URL? {
        for candidate in ["SKILL.md", "README.md"] {
            let url = dir.appendingPathComponent(candidate)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Inline every supporting `*.md` under `skillDir` (excluding `bodyURL`) into `body`,
    /// alphabetically by relative path, under `## Reference: <path-without-extension>`
    /// headers.
    ///
    /// Baton's agent runs headless — no Read tool, no on-the-fly file access — so any
    /// supporting file not inlined here is invisible to the model. The walk is
    /// recursive across known skill conventions (Codex `references/`, Claude-style
    /// root-level `reference.md` or `examples/sample.md`) and skips hidden directories
    /// and `node_modules/` as a paranoia guard against a misconfigured skill source
    /// pointing at a project root.
    func inlineSupportingMarkdown(
        body: String,
        bodyURL: URL,
        skillDir: URL,
        skillName: String
    ) throws -> String {
        let supporting = try collectSupportingMarkdown(
            in: skillDir,
            bodyURL: bodyURL,
            skillName: skillName
        )
        if supporting.isEmpty { return body }
        var chunks: [String] = [body]
        chunks.reserveCapacity(supporting.count + 1)
        for entry in supporting {
            chunks.append("## Reference: \(entry.label)\n\(entry.content)")
        }
        return chunks.joined(separator: "\n\n")
    }

    /// Walk `skillDir` for `*.md` files (excluding `bodyURL`), enforce the
    /// symlink-escape invariant per file, hold the cumulative size under
    /// `referencesBudgetBytes`, and return the entries sorted by relative path.
    private func collectSupportingMarkdown(
        in skillDir: URL,
        bodyURL: URL,
        skillName: String
    ) throws -> [(label: String, content: String)] {
        let fileManager = FileManager.default
        // `skipsHiddenFiles` already excludes any dot-prefixed entry (`.git`, `.build`,
        // `.vscode`, ...). Only non-hidden directories that still don't belong in a
        // skill bundle need an explicit entry here.
        let skipDirs: Set = ["node_modules"]
        // Both body candidates are alternate bodies, never references: when SKILL.md is
        // the body, a sibling README.md must not be inlined as a `## Reference:` block.
        let skipPaths = Set([
            bodyURL.standardizedFileURL.path,
            skillDir.appendingPathComponent("SKILL.md").standardizedFileURL.path,
            skillDir.appendingPathComponent("README.md").standardizedFileURL.path,
        ])
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        guard let enumerator = fileManager.enumerator(
            at: skillDir,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            throw SkillError.skillDirectoryUnreadable(name: skillName, path: skillDir.path)
        }
        var collected: [(label: String, content: String)] = []
        var totalBytes = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isDirectory == true {
                if skipDirs.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard url.pathExtension.lowercased() == "md" else { continue }
            let standardized = url.standardizedFileURL
            if skipPaths.contains(standardized.path) { continue }
            // Run the escape check before the regular-file guard: a symlink reports
            // isRegularFile == false, so a `.md` symlink pointing outside the skill
            // directory must be rejected here rather than silently skipped.
            try assertNoSymlinkEscape(standardized, within: skillDir, skillName: skillName)
            guard values.isRegularFile == true else { continue }
            let content = try readReference(standardized, skillName: skillName)
            totalBytes += content.utf8.count
            if totalBytes > Self.referencesBudgetBytes {
                throw SkillError.referencesBudgetExceeded(
                    name: skillName,
                    limitBytes: Self.referencesBudgetBytes
                )
            }
            collected.append((relativeMarkdownLabel(of: standardized, within: skillDir), content))
        }
        collected.sort { $0.label < $1.label }
        return collected
    }

    /// Read a supporting reference file, surfacing a `referenceReadFailed` error with
    /// the original underlying message — distinct from the body-missing case so the
    /// recovery suggestion ("ensure UTF-8 / readable") matches the actual failure mode.
    private func readReference(_ url: URL, skillName: String) throws -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw SkillError.referenceReadFailed(
                name: skillName,
                path: url.path,
                underlying: error.localizedDescription
            )
        }
    }

    /// Header label for a `## Reference:` block: path of `url` relative to `base`, with
    /// the `.md` extension stripped. The symlink-escape check is supposed to make the
    /// not-inside-base branch unreachable; a `preconditionFailure` here surfaces a
    /// future regression loudly instead of leaking an absolute system path into the
    /// prompt.
    private func relativeMarkdownLabel(of url: URL, within base: URL) -> String {
        let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
        let fullPath = url.path
        guard fullPath.hasPrefix(basePath) else {
            preconditionFailure(
                "relativeMarkdownLabel called with \(fullPath) outside of base \(basePath); " +
                    "symlink-escape check should have rejected this case"
            )
        }
        let relative = String(fullPath.dropFirst(basePath.count))
        return relative.lowercased().hasSuffix(".md")
            ? String(relative.dropLast(3))
            : relative
    }
}
