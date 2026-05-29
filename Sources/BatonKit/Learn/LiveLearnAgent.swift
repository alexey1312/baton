import Foundation

/// The production learning agent: resolves the scope's skills, assembles the
/// prompt, runs the scope's effective agent CLI in the repository working tree,
/// and reports the files it changed (discovered via `git`, never self-reported).
///
/// Change discovery diffs the working-tree dirty set before and after the run so
/// sequential per-scope passes attribute only their own edits.
public struct LiveLearnAgent: LearnAgentRunning {
    private let skills: any SkillResolving
    private let executor: ProcessExecutor

    public init(skills: any SkillResolving, executor: ProcessExecutor = ProcessExecutor()) {
        self.skills = skills
        self.executor = executor
    }

    public func proposeEdits(_ request: LearnAgentRequest) async throws -> LearnAgentOutcome {
        let git = GitRunner(repoRoot: request.repoRoot)
        let before = try Self.dirtyPaths(git)

        let bodies = resolveSkillBodies(request)
        let prompt = LearnPromptBuilder.build(request, skillBodies: bodies.bodies)
        let runner = AgentRegistry.runner(for: request.agent.kind)
        let invocation = InvocationBuilder.make(
            runner: runner,
            agent: request.agent,
            defaults: request.defaults,
            model: request.model,
            prompt: prompt,
            workdir: request.repoRoot
        )
        let result = try await executor.run(invocation, agentName: request.agent.kind.rawValue)
        // A non-zero exit (auth/billing/model/CLI error) that wrote nothing would
        // otherwise be reported as "no setup edits to deliver"; surface it as a
        // failure like the review path (AgentInvoker) does.
        guard result.status == 0 else {
            throw AgentError.nonZeroExit(
                agent: request.agent.kind.rawValue, status: result.status, stderrTail: result.stderrTail()
            )
        }

        let after = try Self.dirtyPaths(git)
        let changed = after.subtracting(before)
        let edits = changed.sorted().map { path in
            ProposedEdit(path: path, newContents: Self.readContents(request.repoRoot, path))
        }
        return LearnAgentOutcome(
            edits: edits,
            rawOutput: result.stdoutText,
            warnings: bodies.warnings,
            usage: nil
        )
    }

    // MARK: - Skills

    private func resolveSkillBodies(_ request: LearnAgentRequest) -> (bodies: [String], warnings: [String]) {
        var bodies: [String] = []
        var warnings: [String] = []
        for skill in request.skills {
            do {
                let resolved = try skills.resolve(
                    skill, declaringConfigDir: request.configDir, security: request.security
                )
                bodies.append("### \(resolved.name)\n\n\(resolved.body)")
            } catch {
                warnings.append("skill '\(skill.name)' could not be resolved: \(error)")
            }
        }
        return (bodies, warnings)
    }

    // MARK: - Git change discovery

    /// The set of repo-relative paths git reports as dirty (modified, added,
    /// deleted, renamed, or untracked). Uses `-z` so paths are NUL-separated and
    /// never C-quoted, keeping non-ASCII/special names intact for the allowlist
    /// and the revert (a quoted name would not match the real file on disk).
    private static func dirtyPaths(_ git: GitRunner) throws -> Set<String> {
        let output = try git.capture(["status", "--porcelain", "-z", "--untracked-files=all"])
        guard output.status == 0 else { return [] }
        return parsePorcelainZ(output.stdout)
    }

    /// Parse `git status --porcelain -z` into the set of affected paths. Records are
    /// NUL-separated `XY <path>`; a rename/copy record (`R`/`C`) is followed by a
    /// bare second path field, and both paths are included so the revert and
    /// allowlist see each side regardless of which is the source.
    static func parsePorcelainZ(_ data: Data) -> Set<String> {
        let fields = data.split(separator: 0x00, omittingEmptySubsequences: false)
            .map { String(bytes: $0, encoding: .utf8) ?? "" }
        var paths: Set<String> = []
        var i = 0
        while i < fields.count {
            let field = fields[i]
            i += 1
            guard field.count > 3 else { continue } // "XY " + at least one path char
            let status = field.prefix(2)
            paths.insert(String(field.dropFirst(3)))
            if status.contains("R") || status.contains("C"), i < fields.count, !fields[i].isEmpty {
                paths.insert(fields[i])
                i += 1
            }
        }
        return paths
    }

    private static func readContents(_ repoRoot: URL, _ path: String) -> String? {
        let url = repoRoot.appendingPathComponent(path)
        guard let data = try? Data(contentsOf: url) else { return nil } // deleted
        return String(bytes: data, encoding: .utf8)
    }
}
