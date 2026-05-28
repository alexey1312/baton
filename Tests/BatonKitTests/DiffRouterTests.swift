@testable import BatonKit
import Testing

struct DiffRouterTests {
    private func scope(_ path: String) -> ScopeConfig {
        ScopeConfig(path: path, configPath: "\(path)/baton.toml", config: BatonConfig())
    }

    private func file(_ path: String, _ kind: ChangeKind = .modified) -> FileChange {
        FileChange(path: path, changeKind: kind, patch: "diff --git a/\(path) b/\(path)")
    }

    @Test("owner is the deepest-ancestor scope; otherwise nil")
    func ownerDeepest() {
        let root = ScopeConfig(path: "", configPath: "baton.toml", config: BatonConfig())
        let ios = scope("ios")
        let owner = DiffRouter.owner(of: "ios/App/View.swift", scopes: [root, ios])
        #expect(owner?.path == "ios")
        let outside = DiffRouter.owner(of: "tools/script.sh", scopes: [ios])
        #expect(outside == nil)
    }

    @Test("rename is owned by the new (b-side) path's scope")
    func renameAcrossBoundary() {
        let libs = scope("libs/a")
        let apps = scope("apps/ios")
        let renamed = FileChange(
            path: "apps/ios/x.swift",
            oldPath: "libs/a/x.swift",
            changeKind: .renamed,
            patch: ""
        )
        #expect(DiffRouter.owner(of: renamed.path, scopes: [libs, apps])?.path == "apps/ios")
    }

    @Test("group partitions diff by scope and drops files outside any scope")
    func grouping() {
        let ios = scope("ios")
        let web = scope("web")
        let diff = RepoDiff(base: "HEAD", files: [
            file("ios/App.swift"),
            file("ios/View.swift"),
            file("web/api.ts"),
            file("README.md"), // outside any scope
        ])
        let groups = DiffRouter.group(diff, scopes: [ios, web])
        #expect(groups["ios"]?.count == 2)
        #expect(groups["web"]?.count == 1)
        #expect(groups["README.md"] == nil)
    }

    @Test("review glob filters scope files to matching paths only")
    func globFilter() {
        let files = [file("App/View.swift"), file("docs/README.md")]
        let matched = DiffRouter.filter(files, glob: ["**/*.swift"])
        #expect(matched.map(\.path) == ["App/View.swift"])

        let unfiltered = DiffRouter.filter(files, glob: nil)
        #expect(unfiltered.count == files.count)

        let none = DiffRouter.filter(files, glob: ["**/*.kt"])
        #expect(none.isEmpty)
    }
}
