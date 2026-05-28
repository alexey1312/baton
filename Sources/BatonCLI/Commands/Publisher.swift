import BatonForge
import BatonKit
import Foundation

/// Bridges the `publish` command to `BatonForge.GitHubForge`: preflight, resolve the
/// publish context, post, and present the report.
enum Publisher {
    static func publish(run: LoadedRun, overrides: PublishOverrides, outputMode: OutputMode) async throws {
        let forge = GitHubForge()
        try await forge.preflight()

        let context = try PublishContext.resolve(overrides: overrides, env: GitHubEnv.detect())
        let report = try await forge.publish(run: run, context: context)

        let colors = outputMode.useColors
        for warning in report.warnings {
            TerminalOutput.shared.err(NooraUI.warning(warning, useColors: colors))
        }
        let target = context.prNumber.map { "PR #\($0)" } ?? "Check Runs @ \(context.headSHA.prefix(8))"
        let summary = "Published to \(context.repo) (\(target)): "
            + "\(report.inlineCommentsPosted) inline comment(s), "
            + "\(report.checkRunsCreated) check run(s)"
            + (report.checkRunsSkipped > 0 ? ", \(report.checkRunsSkipped) skipped" : "")
            + (report.inlineCommentsDeduped > 0 ? ", \(report.inlineCommentsDeduped) deduped" : "")
            + "."
        TerminalOutput.shared.out(NooraUI.success(summary, useColors: colors))
    }
}
