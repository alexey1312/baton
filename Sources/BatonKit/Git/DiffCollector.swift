import Foundation

/// Collects the repository diff against a resolved base, including untracked files.
public struct DiffCollector: Sendable {
    public let git: GitRunner

    public init(git: GitRunner) {
        self.git = git
    }

    /// Collect the diff. The base ref MUST already be valid (see
    /// ``BaseResolver/validate(_:git:)``); this also validates internally so callers
    /// get the same typed error.
    public func collect(base: String, includeUntracked: Bool = true) throws -> RepoDiff {
        try BaseResolver.validate(base, git: git)

        let nameStatus = try git.capture(["diff", "--find-renames", "-z", "--name-status", base])
        let patch = try git.run(["diff", "--find-renames", base])
        var files = DiffParser.files(nameStatus: nameStatus.stdout, patch: patch)

        if includeUntracked {
            files.append(contentsOf: collectUntracked())
        }
        return RepoDiff(base: base, files: files)
    }

    /// Collect untracked files and synthesize an `added` patch for each so the rest
    /// of the pipeline (routing, chunking, prompt assembly) handles them uniformly.
    private func collectUntracked() -> [FileChange] {
        guard let output = try? git.capture(["ls-files", "--others", "--exclude-standard", "-z"]) else {
            return []
        }
        let paths = output.stdout
            .split(separator: 0x00, omittingEmptySubsequences: false)
            .map { String(bytes: $0, encoding: .utf8) ?? "" }
            .filter { !$0.isEmpty }

        return paths.compactMap { path in
            let fileURL = git.repoRoot.appendingPathComponent(path)
            guard let data = try? Data(contentsOf: fileURL) else { return nil }
            return synthesizeAddedPatch(path: path, data: data)
        }
    }

    private func synthesizeAddedPatch(path: String, data: Data) -> FileChange {
        // Crude binary detection: any NUL byte.
        if data.contains(0x00) {
            let patch = """
            diff --git a/\(path) b/\(path)
            new file mode 100644
            Binary files /dev/null and b/\(path) differ
            """
            return FileChange(path: path, changeKind: .added, isBinary: true, hunks: [], patch: patch)
        }
        let content = String(bytes: data, encoding: .utf8) ?? ""
        // An empty new file has no hunk — git emits only the header.
        guard !content.isEmpty else {
            let patch = """
            diff --git a/\(path) b/\(path)
            new file mode 100644
            """
            return FileChange(path: path, changeKind: .added, hunks: [], patch: patch)
        }
        // A trailing newline yields a spurious empty final element from `split`; git
        // counts only real lines. Without a trailing newline git appends the
        // `\ No newline at end of file` marker after the last added line.
        let endsWithNewline = content.hasSuffix("\n")
        var lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if endsWithNewline { lines.removeLast() }
        var plus = lines.map { "+\($0)" }
        let header = "@@ -0,0 +1,\(lines.count) @@"
        if !endsWithNewline { plus.append("\\ No newline at end of file") }
        let patch = """
        diff --git a/\(path) b/\(path)
        new file mode 100644
        --- /dev/null
        +++ b/\(path)
        \(header)
        \(plus.joined(separator: "\n"))
        """
        return FileChange(
            path: path,
            changeKind: .added,
            hunks: [Hunk(header: header, newStart: 1, lines: plus)],
            patch: patch
        )
    }
}
