/// A chunk of one or more file diffs sent to the agent as a single pass.
public struct DiffChunk: Sendable, Equatable {
    public var files: [FileChange]
    /// The concatenated patches of all files in this chunk.
    public var text: String

    public init(files: [FileChange]) {
        self.files = files
        text = files.map(\.patch).joined(separator: "\n")
    }

    public var byteSize: Int {
        text.utf8.count
    }
}

/// Structural chunking: split a scope's diff at file or hunk boundaries when its
/// total exceeds `diff_budget`. Never cuts mid-line. Falls back from `by-file` to
/// `by-hunk` when a single file is too large; sends an oversized hunk whole and
/// marks the file `truncated` as the last resort, emitting a warning.
public enum DiffChunker {
    public struct Result: Sendable {
        public var chunks: [DiffChunk]
        public var warnings: [String]
    }

    public static func chunks(files: [FileChange], budget: Int, strategy: ChunkStrategy) -> Result {
        if files.isEmpty { return Result(chunks: [], warnings: []) }

        let total = files.reduce(0) { $0 + $1.byteSize }
        if total <= budget {
            return Result(chunks: [DiffChunk(files: files)], warnings: [])
        }

        switch strategy {
        case .byFile:
            return chunkByFile(files, budget: budget)
        case .byHunk:
            return chunkAllByHunk(files, budget: budget)
        }
    }

    // MARK: - by-file (with by-hunk fallback for oversized single files)

    private static func chunkByFile(_ files: [FileChange], budget: Int) -> Result {
        var chunks: [DiffChunk] = []
        var warnings: [String] = []
        var current: [FileChange] = []
        var currentSize = 0

        func flush() {
            if !current.isEmpty {
                chunks.append(DiffChunk(files: current))
                current = []
                currentSize = 0
            }
        }

        for file in files {
            if file.byteSize > budget {
                flush()
                let fallback = splitFileByHunk(file, budget: budget)
                chunks.append(contentsOf: fallback.chunks)
                warnings.append(contentsOf: fallback.warnings)
            } else if currentSize + file.byteSize > budget {
                flush()
                current = [file]
                currentSize = file.byteSize
            } else {
                current.append(file)
                currentSize += file.byteSize
            }
        }
        flush()
        return Result(chunks: chunks, warnings: warnings)
    }

    // MARK: - by-hunk (every file split into per-hunk chunks)

    private static func chunkAllByHunk(_ files: [FileChange], budget: Int) -> Result {
        var chunks: [DiffChunk] = []
        var warnings: [String] = []
        for file in files {
            let perFile = splitFileByHunk(file, budget: budget)
            chunks.append(contentsOf: perFile.chunks)
            warnings.append(contentsOf: perFile.warnings)
        }
        return Result(chunks: chunks, warnings: warnings)
    }

    /// Split a single file's diff into per-hunk chunks (one chunk per hunk).
    /// Oversized single hunks are sent whole with `truncated = true` and a warning.
    private static func splitFileByHunk(_ file: FileChange, budget: Int) -> Result {
        if file.hunks.isEmpty {
            var f = file
            var warnings: [String] = []
            if file.byteSize > budget {
                f.truncated = true
                warnings.append("File '\(file.path)' patch exceeds diff_budget; sent whole and marked truncated.")
            }
            return Result(chunks: [DiffChunk(files: [f])], warnings: warnings)
        }

        let header = headerLines(of: file)
        var chunks: [DiffChunk] = []
        var warnings: [String] = []
        for hunk in file.hunks {
            let patch = header + "\n" + hunk.rawText
            var f = file
            f.hunks = [hunk]
            f.patch = patch
            if patch.utf8.count > budget {
                f.truncated = true
                warnings.append("Hunk in '\(file.path)' exceeds diff_budget; sent whole and marked truncated.")
            }
            chunks.append(DiffChunk(files: [f]))
        }
        return Result(chunks: chunks, warnings: warnings)
    }

    /// The patch header (everything before the first `@@` line).
    private static func headerLines(of file: FileChange) -> String {
        var headerLines: [String] = []
        for line in file.patch.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("@@") { break }
            headerLines.append(String(line))
        }
        return headerLines.joined(separator: "\n")
    }
}
