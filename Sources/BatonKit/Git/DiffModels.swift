/// The kind of change to a file in a diff.
public enum ChangeKind: String, Sendable, Equatable {
    case added
    case modified
    case deleted
    case renamed
}

/// A single hunk of a textual file diff.
public struct Hunk: Sendable, Equatable {
    /// The `@@ -a,b +c,d @@` header line.
    public var header: String
    /// 1-based starting line of the hunk on the new side.
    public var newStart: Int
    /// Patch lines (each prefixed by ` `, `+`, or `-`), excluding the header.
    public var lines: [String]

    public init(header: String, newStart: Int, lines: [String]) {
        self.header = header
        self.newStart = newStart
        self.lines = lines
    }

    /// The hunk header followed by its lines.
    public var rawText: String {
        ([header] + lines).joined(separator: "\n")
    }
}

/// A single changed file within a collected diff.
public struct FileChange: Sendable, Equatable {
    /// The new (`b/`) path, or the file's path for deletes.
    public var path: String
    /// The old (`a/`) path, set only for renames.
    public var oldPath: String?
    public var changeKind: ChangeKind
    public var isBinary: Bool
    public var hunks: [Hunk]
    /// The full per-file patch block (the `diff --git …` section).
    public var patch: String
    /// Set when the file's diff was sent oversized (chunking gave up splitting it).
    public var truncated: Bool

    public init(
        path: String,
        oldPath: String? = nil,
        changeKind: ChangeKind,
        isBinary: Bool = false,
        hunks: [Hunk] = [],
        patch: String,
        truncated: Bool = false
    ) {
        self.path = path
        self.oldPath = oldPath
        self.changeKind = changeKind
        self.isBinary = isBinary
        self.hunks = hunks
        self.patch = patch
        self.truncated = truncated
    }

    /// Byte size of this file's patch text, used for chunking budgets.
    public var byteSize: Int {
        patch.utf8.count
    }
}

/// A collected repository diff against a resolved base.
public struct RepoDiff: Sendable {
    public var base: String
    public var files: [FileChange]

    public init(base: String, files: [FileChange]) {
        self.base = base
        self.files = files
    }

    public var isEmpty: Bool {
        files.isEmpty
    }
}
