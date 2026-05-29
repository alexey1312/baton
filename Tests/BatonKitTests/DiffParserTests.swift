@testable import BatonKit
import Foundation
import Testing

struct DiffParserTests {
    @Test("name-status -z parses modified, added, deleted, renamed with unambiguous paths")
    func nameStatus() {
        let raw = "M\u{0}src/a.swift\u{0}"
            + "A\u{0}docs/new file.md\u{0}"
            + "D\u{0}old.md\u{0}"
            + "R100\u{0}libs/x.swift\u{0}apps/x.swift\u{0}"
        let data = Data(raw.utf8)
        let entries = DiffParser.parseNameStatus(data)
        #expect(entries.count == 4)
        #expect(entries[0].kind == .modified && entries[0].path == "src/a.swift")
        #expect(entries[1].kind == .added && entries[1].path == "docs/new file.md")
        #expect(entries[2].kind == .deleted && entries[2].path == "old.md")
        #expect(entries[3].kind == .renamed)
        #expect(entries[3].oldPath == "libs/x.swift")
        #expect(entries[3].path == "apps/x.swift")
    }

    @Test("splitIntoBlocks separates per-file patches at diff --git boundaries")
    func split() {
        let patch = """
        diff --git a/a b/a
        --- a/a
        +++ b/a
        @@ -1 +1 @@
        -x
        +y
        diff --git a/b b/b
        new file mode 100644
        --- /dev/null
        +++ b/b
        @@ -0,0 +1 @@
        +hi
        """
        let blocks = DiffParser.splitIntoBlocks(patch)
        #expect(blocks.count == 2)
        #expect(blocks[0].hasPrefix("diff --git a/a b/a"))
        #expect(blocks[1].hasPrefix("diff --git a/b b/b"))
    }

    @Test("parseHunks extracts every hunk with its new-side start line")
    func hunks() {
        let block = """
        diff --git a/x b/x
        --- a/x
        +++ b/x
        @@ -1,3 +1,4 @@ context
         a
        -b
        +c
        +d
        @@ -10,2 +11,2 @@
         e
        -f
        +g
        """
        let hunks = DiffParser.parseHunks(block)
        #expect(hunks.count == 2)
        #expect(hunks[0].newStart == 1)
        #expect(hunks[1].newStart == 11)
    }

    @Test("binary file is detected and produces no hunks")
    func binary() {
        let data = Data("A\u{0}img.png\u{0}".utf8)
        let patch = """
        diff --git a/img.png b/img.png
        new file mode 100644
        Binary files /dev/null and b/img.png differ
        """
        let files = DiffParser.files(nameStatus: data, patch: patch)
        #expect(files.count == 1)
        #expect(files[0].isBinary == true)
        #expect(files[0].hunks.isEmpty)
        #expect(files[0].changeKind == .added)
    }

    @Test("a text diff whose content mentions 'Binary files … differ' is not misclassified binary")
    func binaryFalsePositive() {
        let data = Data("M\u{0}docs/git.md\u{0}".utf8)
        // The phrase appears on a `+` content line, not as git's unprefixed marker.
        let patch = """
        diff --git a/docs/git.md b/docs/git.md
        --- a/docs/git.md
        +++ b/docs/git.md
        @@ -1,2 +1,3 @@
         intro
        +Binary files /dev/null and b/x differ
        +explained
        """
        let files = DiffParser.files(nameStatus: data, patch: patch)
        #expect(files.count == 1)
        #expect(files[0].isBinary == false)
        #expect(!files[0].hunks.isEmpty)
    }
}
