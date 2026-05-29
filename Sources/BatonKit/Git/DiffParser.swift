import Foundation

/// Parses `git diff` output into structured ``FileChange`` values.
///
/// File paths come from the authoritative `-z --name-status` listing (NUL-separated
/// and unquoted, so spaces/unicode are unambiguous); per-file patch text is split at
/// `diff --git` boundaries and paired by order with that listing.
public enum DiffParser {
    /// A `(kind, path, oldPath)` entry from `git diff -z --name-status`.
    struct NameStatusEntry: Equatable {
        var kind: ChangeKind
        var path: String
        var oldPath: String?
    }

    /// Parse the NUL-separated `--name-status -z` output.
    static func parseNameStatus(_ data: Data) -> [NameStatusEntry] {
        let tokens = data.split(separator: 0x00, omittingEmptySubsequences: false)
            .map { String(bytes: $0, encoding: .utf8) ?? "" }
            .filter { !$0.isEmpty }

        var entries: [NameStatusEntry] = []
        var i = 0
        while i < tokens.count {
            let status = tokens[i]
            i += 1
            let code = status.first.map(String.init) ?? ""
            if code == "R" || code == "C" {
                guard i + 1 < tokens.count else { break }
                let old = tokens[i]
                let new = tokens[i + 1]
                i += 2
                entries.append(NameStatusEntry(kind: .renamed, path: new, oldPath: old))
            } else {
                guard i < tokens.count else { break }
                let path = tokens[i]
                i += 1
                let kind: ChangeKind = switch code {
                case "A": .added
                case "D": .deleted
                default: .modified
                }
                entries.append(NameStatusEntry(kind: kind, path: path))
            }
        }
        return entries
    }

    /// Split a full patch into per-file blocks at `diff --git` lines.
    static func splitIntoBlocks(_ patch: String) -> [String] {
        guard !patch.isEmpty else { return [] }
        var blocks: [String] = []
        var current: [Substring] = []
        for line in patch.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("diff --git ") {
                if !current.isEmpty { blocks.append(current.joined(separator: "\n")) }
                current = [line]
            } else if !current.isEmpty {
                current.append(line)
            }
        }
        if !current.isEmpty { blocks.append(current.joined(separator: "\n")) }
        return blocks
    }

    /// Parse the hunks within a single file's patch block.
    static func parseHunks(_ block: String) -> [Hunk] {
        var hunks: [Hunk] = []
        var header: String?
        var newStart = 0
        var lines: [String] = []

        func flush() {
            if let header {
                hunks.append(Hunk(header: header, newStart: newStart, lines: lines))
            }
            header = nil
            lines = []
        }

        for rawLine in block.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("@@") {
                flush()
                header = line
                newStart = parseNewStart(line)
            } else if header != nil {
                lines.append(line)
            }
        }
        flush()
        return hunks
    }

    /// Extract `c` from a `@@ -a,b +c,d @@` header.
    private static func parseNewStart(_ header: String) -> Int {
        guard let plusRange = header.range(of: "+") else { return 0 }
        let after = header[plusRange.upperBound...]
        let number = after.prefix { $0.isNumber }
        return Int(number) ?? 0
    }

    /// Whether a file block is a binary diff. Detection is anchored to git's own
    /// metadata lines — which appear unprefixed — so a *content* line that happens
    /// to contain the literal phrase (it would carry a `+`/`-`/space prefix) does
    /// not false-positive a text diff into binary.
    static func isBinaryBlock(_ block: String) -> Bool {
        for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("Binary files "), line.hasSuffix(" differ") { return true }
            if line == "GIT binary patch" { return true }
        }
        return false
    }

    /// Build `FileChange` values from a name-status listing and the full patch text.
    public static func files(nameStatus data: Data, patch: String) -> [FileChange] {
        let entries = parseNameStatus(data)
        let blocks = splitIntoBlocks(patch)
        return entries.enumerated().map { index, entry in
            let block = index < blocks.count ? blocks[index] : ""
            let isBinary = isBinaryBlock(block)
            return FileChange(
                path: entry.path,
                oldPath: entry.oldPath,
                changeKind: entry.kind,
                isBinary: isBinary,
                hunks: isBinary ? [] : parseHunks(block),
                patch: block
            )
        }
    }
}
