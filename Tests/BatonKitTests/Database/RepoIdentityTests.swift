@testable import BatonKit
import Foundation
import Testing

struct RepoIdentityTests {
    @Test("resolve produces a 16-hex id and the trailing path component as label")
    func resolveBasics() {
        let identity = RepoIdentity.resolve(repoRoot: URL(fileURLWithPath: "/Users/me/Code/example"))
        #expect(identity.id.count == 16)
        #expect(identity.id.allSatisfy { $0.isHexDigit })
        #expect(identity.label == "example")
    }

    @Test("the same canonical path produces the same id")
    func stableHashing() {
        let a = RepoIdentity.resolve(repoRoot: URL(fileURLWithPath: "/Users/me/Code/example"))
        let b = RepoIdentity.resolve(repoRoot: URL(fileURLWithPath: "/Users/me/Code/example"))
        #expect(a.id == b.id)
    }

    @Test("different paths produce different ids")
    func distinctPathsDistinctIds() {
        let a = RepoIdentity.resolve(repoRoot: URL(fileURLWithPath: "/Users/me/Code/a"))
        let b = RepoIdentity.resolve(repoRoot: URL(fileURLWithPath: "/Users/me/Code/b"))
        #expect(a.id != b.id)
    }

    @Test("case-only differences collapse on macOS-style case-insensitive paths")
    func caseInsensitive() {
        let a = RepoIdentity.resolve(repoRoot: URL(fileURLWithPath: "/Users/Me/Code/Example"))
        let b = RepoIdentity.resolve(repoRoot: URL(fileURLWithPath: "/users/me/code/example"))
        #expect(a.id == b.id)
    }
}
