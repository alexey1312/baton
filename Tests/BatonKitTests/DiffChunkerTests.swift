@testable import BatonKit
import Testing

struct DiffChunkerTests {
    private func smallFile(_ path: String) -> FileChange {
        FileChange(
            path: path,
            changeKind: .modified,
            hunks: [Hunk(header: "@@ -1 +1 @@", newStart: 1, lines: [" a", "-b", "+c"])],
            patch: "diff --git a/\(path) b/\(path)\n--- a/\(path)\n+++ b/\(path)\n@@ -1 +1 @@\n a\n-b\n+c"
        )
    }

    private func bigFile(_ path: String, hunks: Int, lineSize: Int) -> FileChange {
        let header = "@@ -1,\(lineSize) +1,\(lineSize) @@"
        var hunkList: [Hunk] = []
        var patch = "diff --git a/\(path) b/\(path)\n--- a/\(path)\n+++ b/\(path)\n"
        for _ in 0 ..< hunks {
            let lines = (0 ..< lineSize).map { "+\(String(repeating: "x", count: $0 + 1))" }
            hunkList.append(Hunk(header: header, newStart: 1, lines: lines))
            patch += header + "\n" + lines.joined(separator: "\n") + "\n"
        }
        return FileChange(path: path, changeKind: .modified, hunks: hunkList, patch: patch)
    }

    @Test("within budget runs as a single chunk")
    func withinBudget() {
        let files = [smallFile("a.swift"), smallFile("b.swift")]
        let result = DiffChunker.chunks(files: files, budget: 10000, strategy: .byFile)
        #expect(result.chunks.count == 1)
        #expect(result.chunks[0].files.count == 2)
        #expect(result.warnings.isEmpty)
    }

    @Test("by-file split when total exceeds budget but each file fits")
    func byFileSplit() {
        let file = bigFile("big.swift", hunks: 1, lineSize: 5) // small file
        let files = Array(repeating: file, count: 5)
        let total = files.reduce(0) { $0 + $1.byteSize }
        let budget = total / 2
        let result = DiffChunker.chunks(files: files, budget: budget, strategy: .byFile)
        #expect(result.chunks.count >= 2)
        for chunk in result.chunks where chunk.files.count > 1 {
            #expect(chunk.byteSize <= budget)
        }
    }

    @Test("by-file falls back to by-hunk when one file alone exceeds the budget")
    func oversizedFileFallback() {
        let big = bigFile("big.swift", hunks: 4, lineSize: 50)
        let result = DiffChunker.chunks(files: [big], budget: big.byteSize / 3, strategy: .byFile)
        // Per-hunk fallback produces one chunk per hunk.
        #expect(result.chunks.count == big.hunks.count)
    }

    @Test("oversized single hunk is sent whole and marked truncated with a warning")
    func oversizedHunkTruncated() {
        let big = bigFile("huge.swift", hunks: 1, lineSize: 500)
        let result = DiffChunker.chunks(files: [big], budget: 50, strategy: .byHunk)
        #expect(result.chunks.count == 1)
        #expect(result.chunks[0].files[0].truncated == true)
        #expect(result.warnings.contains { $0.contains("huge.swift") && $0.contains("truncated") })
    }

    @Test("by-hunk strategy splits every file into per-hunk chunks")
    func byHunkStrategy() {
        let file = bigFile("a.swift", hunks: 3, lineSize: 3)
        let result = DiffChunker.chunks(files: [file], budget: file.byteSize / 2, strategy: .byHunk)
        #expect(result.chunks.count == 3)
    }
}
