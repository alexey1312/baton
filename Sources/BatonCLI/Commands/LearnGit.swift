import BatonKit
import Foundation

/// Git side-effects for `learn`: writing the accepted (allowlisted) edits to disk
/// and committing them onto the rolling `learn` branch for delivery. The agent no
/// longer edits files agentically (it returns structured JSON); Baton writes the
/// allowlisted full-contents edits itself, so only the apply/delivery path touches
/// the working tree — preview never does.
enum LearnGit {
    /// Write each allowed edit's full contents to `repoRoot/path`, creating parent
    /// directories. A `nil`-contents edit (deletion) removes the file. Throws
    /// ``CLIError`` on a write failure so a botched apply does not commit a stale
    /// tree as if it succeeded.
    static func writeEdits(_ edits: [ProposedEdit], repoRoot: URL) throws {
        for edit in edits {
            let url = repoRoot.appendingPathComponent(edit.path)
            do {
                guard let contents = edit.newContents else {
                    try? FileManager.default.removeItem(at: url)
                    continue
                }
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try Data(contents.utf8).write(to: url)
            } catch {
                throw CLIError.learnDeliveryFailed(detail: "could not write \(edit.path): \(error)")
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
}
