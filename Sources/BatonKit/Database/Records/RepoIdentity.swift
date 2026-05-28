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
        let id = leftPadHex(FNV1a.hash(normalized), width: 16)
        let label = repoRoot.lastPathComponent.isEmpty ? canonical : repoRoot.lastPathComponent
        return RepoIdentity(id: id, label: label, absolutePath: canonical)
    }

    /// Left-pad a UInt64 hex representation to `width` digits with zeros.
    /// Returns the natural fixed-width hex form so the id can round-trip back
    /// through `UInt64(_:radix:)` if a caller ever needs to.
    static func leftPadHex(_ value: UInt64, width: Int) -> String {
        let hex = String(value, radix: 16, uppercase: false)
        guard hex.count < width else { return hex }
        return String(repeating: "0", count: width - hex.count) + hex
    }
}
