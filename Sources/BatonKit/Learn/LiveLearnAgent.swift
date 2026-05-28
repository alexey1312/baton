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
    /// deleted, or untracked).
    private static func dirtyPaths(_ git: GitRunner) throws -> Set<String> {
        let output = try git.capture(["status", "--porcelain", "--untracked-files=all"])
        guard output.status == 0 else { return [] }
        var paths: Set<String> = []
        for line in output.text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.count > 3 else { continue }
            let rest = String(line.dropFirst(3))
            // Renames are reported as `old -> new`; attribute to the new path.
            let path = rest.components(separatedBy: " -> ").last ?? rest
            paths.insert(path.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
        }
        return paths
    }

    private static func readContents(_ repoRoot: URL, _ path: String) -> String? {
        let url = repoRoot.appendingPathComponent(path)
        guard let data = try? Data(contentsOf: url) else { return nil } // deleted
        return String(bytes: data, encoding: .utf8)
    }
}
