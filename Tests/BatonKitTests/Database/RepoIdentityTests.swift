@testable import BatonKit
import Foundation
import Testing

struct RepoIdentityTests {
    @Test("resolve produces a 16-hex id and the trailing path component as label")
    func resolveBasics() {
        let identity = RepoIdentity.resolve(repoRoot: URL(fileURLWithPath: "/Users/me/Code/example"))
        let allHex = identity.id.allSatisfy(\.isHexDigit)
        #expect(identity.id.count == 16)
        #expect(allHex)
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

    /// FNV-1a hash of `/tmp/probe_1000` (lowercased) is 14 hex digits.
    /// Verifies that ids are left-zero-padded to 16 — the natural representation
    /// for a 64-bit number — not right-padded with zeros (which would silently
    /// shift the hash's nibbles and break any caller that expects the id to be
    /// the hex representation of the underlying uint64).
    @Test("id is left-zero-padded for short hashes (canonical hex of UInt64)")
    func leftPadShortHash() {
        let identity = RepoIdentity.resolve(repoRoot: URL(fileURLWithPath: "/tmp/probe_1000"))
        #expect(identity.id == "00c2a7c31eb94672")
    }
}
