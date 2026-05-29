import BatonKit
import Foundation

/// Git side-effects for `learn`: restoring refused (out-of-allowlist) edits the
/// agent wrongly produced, and committing the accepted edits onto the rolling
/// `learn` branch for delivery.
enum LearnGit {
    /// Revert the agent's changes to `paths` (refused edits). Tracked files are
    /// restored from HEAD; untracked new files are removed. Best-effort.
    static func restore(_ paths: [String], repoRoot: URL) {
        guard !paths.isEmpty else { return }
        let git = GitRunner(repoRoot: repoRoot)
        let untracked = untrackedPaths(git)
        for path in paths {
            if untracked.contains(path) {
                try? FileManager.default.removeItem(at: repoRoot.appendingPathComponent(path))
            } else {
                _ = try? git.run(["checkout", "--", path])
            }
        }
    }

    /// Force-update `branch` to a commit carrying `paths`, then push it. Returns to
    /// the original branch afterward. Throws ``CLIError`` on a git failure.
    static func commitAndPush(branch: String, paths: [String], message: String, repoRoot: URL) throws {
        guard !paths.isEmpty else { return }
        let git = GitRunner(repoRoot: repoRoot)
        let original = (try? git.run(["rev-parse", "--abbrev-ref", "HEAD"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "HEAD"
        do {
            try git.run(["switch", "-C", branch])
            for path in paths {
                try git.run(["add", "--", path])
            }
            // `git diff --cached --quiet` exits non-zero only when something is staged.
            // Nothing staged is a genuine no-op; any *other* commit failure (hook,
            // signing, locked index) must propagate rather than be mistaken for the
            // no-op and reported downstream as a successful delivery on a stale branch.
            let hasStagedChanges = try git.capture(["diff", "--cached", "--quiet"]).status != 0
            if hasStagedChanges {
                try git.run(["commit", "-m", message])
                try git.run(["push", "--force", "origin", branch])
            }
        } catch {
            _ = try? git.run(["switch", original])
            throw CLIError.learnDeliveryFailed(detail: "\(error)")
        }
        _ = try? git.run(["switch", original])
    }

    private static func untrackedPaths(_ git: GitRunner) -> Set<String> {
        // `-z` keeps non-ASCII names unquoted so the removeItem below matches the
        // real file on disk (a C-quoted name would not, leaving a refused file).
        let data = (try? git.capture(["status", "--porcelain", "-z", "--untracked-files=all"]))?.stdout ?? Data()
        var result: Set<String> = []
        for field in data.split(separator: 0x00, omittingEmptySubsequences: true) {
            let entry = String(bytes: field, encoding: .utf8) ?? ""
            guard entry.hasPrefix("??"), entry.count > 3 else { continue }
            result.insert(String(entry.dropFirst(3)))
        }
        return result
    }
}
