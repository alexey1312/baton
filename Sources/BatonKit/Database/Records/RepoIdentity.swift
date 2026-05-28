import Foundation

/// Stable identifier for a repository, used to scope stats by repo.
///
/// `id` is a 16-char FNV-1a hash of the canonical absolute repo path. We do
/// not use the git remote URL because forks, multi-remote setups, and
/// repositories without a remote would produce ambiguous or missing ids.
/// `label` is the last path component, shown verbatim in UI.
public struct RepoIdentity: Sendable, Equatable, Hashable {
    public let id: String
    public let label: String
    public let absolutePath: String

    public init(id: String, label: String, absolutePath: String) {
        self.id = id
        self.label = label
        self.absolutePath = absolutePath
    }

    /// Compute a `RepoIdentity` from a repository root URL.
    public static func resolve(repoRoot: URL) -> RepoIdentity {
        let canonical = repoRoot.resolvingSymlinksInPath().path
        let normalized = canonical.lowercased()
        let id = String(fnv1a64(normalized), radix: 16, uppercase: false)
            .padding(toLength: 16, withPad: "0", startingAt: 0)
        let label = repoRoot.lastPathComponent.isEmpty ? canonical : repoRoot.lastPathComponent
        return RepoIdentity(id: id, label: label, absolutePath: canonical)
    }

    /// FNV-1a 64-bit. Not cryptographic — we only need stable, well-distributed
    /// 16-hex ids for filesystem paths.
    private static func fnv1a64(_ string: String) -> UInt64 {
        let offsetBasis: UInt64 = 0xCBF2_9CE4_8422_2325
        let prime: UInt64 = 0x100_0000_01B3
        var hash = offsetBasis
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }
}
