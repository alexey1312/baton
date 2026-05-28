import Foundation

extension SkillResolver {
    /// Return the body file URL (`SKILL.md` preferred, then `README.md`) in `dir`,
    /// or `nil` when neither exists.
    func bodyFileURL(in dir: URL, fileManager: FileManager) -> URL? {
        for candidate in ["SKILL.md", "README.md"] {
            let url = dir.appendingPathComponent(candidate)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    /// Whether `url` is a directory on disk.
    func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Append every supporting `*.md` found under `skillDir` (other than the chosen
    /// body file) to `body`, alphabetically by relative path, under a
    /// `## Reference: <relative-path-without-extension>` header.
    ///
    /// Baton's agent runs headless — no Read tool, no on-the-fly file access — so any
    /// supporting file not inlined here is invisible to the model. The walk is
    /// recursive across the three live skill conventions (Codex `references/`,
    /// Claude-style root-level `reference.md` or `examples/sample.md`) and skips
    /// `.git/`, `.build/`, `node_modules/` as a paranoia guard against a
    /// misconfigured skill source pointing at a project root.
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
        var combined = body
        for entry in supporting {
            combined += "\n\n## Reference: \(entry.label)\n\(entry.content)"
        }
        return combined
    }

    /// Walk `skillDir` for `*.md` files (excluding `bodyURL`), enforce the
    /// symlink-escape invariant per file, and return them sorted by relative path.
    private func collectSupportingMarkdown(
        in skillDir: URL,
        bodyURL: URL,
        skillName: String
    ) throws -> [(label: String, content: String)] {
        let fileManager = FileManager.default
        let skipDirs = [".git", ".build", "node_modules"]
        let bodyPath = bodyURL.standardizedFileURL.path
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        guard let enumerator = fileManager.enumerator(
            at: skillDir,
            includingPropertiesForKeys: keys,
            options: []
        ) else {
            return []
        }
        var collected: [(label: String, content: String)] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isDirectory == true {
                if skipDirs.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true,
                  url.pathExtension.lowercased() == "md"
            else { continue }
            let standardized = url.standardizedFileURL
            if standardized.path == bodyPath { continue }
            try assertNoSymlinkEscape(standardized, within: skillDir, skillName: skillName)
            let content = try readBody(standardized, skillName: skillName)
            collected.append((relativeMarkdownLabel(of: standardized, within: skillDir), content))
        }
        collected.sort { $0.label < $1.label }
        return collected
    }

    /// Compute the `## Reference:` header label: the file path relative to `base`,
    /// with the `.md` extension stripped. Falls back to the absolute path when
    /// `url` isn't inside `base` (defensive — the symlink-escape check should have
    /// already rejected that case).
    private func relativeMarkdownLabel(of url: URL, within base: URL) -> String {
        let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
        let fullPath = url.path
        let relative = fullPath.hasPrefix(basePath)
            ? String(fullPath.dropFirst(basePath.count))
            : fullPath
        return relative.lowercased().hasSuffix(".md")
            ? String(relative.dropLast(3))
            : relative
    }
}
