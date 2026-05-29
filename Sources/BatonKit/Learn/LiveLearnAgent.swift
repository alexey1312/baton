import Foundation

/// The production learning agent: resolves the scope's skills, snapshots the
/// editable review-setup files, runs the scope's effective agent CLI once, and
/// parses the structured JSON proposal the agent returns.
///
/// The agent does NOT edit files agentically (no tools, no extra turns): it
/// reflects on the signal plus the file snapshot and emits a single JSON object
/// of `{themes, edits}` where each edit carries the FULL new file contents. The
/// host (Baton) writes the allowlisted edits itself, so `--max-turns 1` is
/// correct — the agent only emits text. Mirrors blick's `agent_pass`.
public struct LiveLearnAgent: LearnAgentRunning {
    private let skills: any SkillResolving
    private let executor: ProcessExecutor

    public init(skills: any SkillResolving, executor: ProcessExecutor = ProcessExecutor()) {
        self.skills = skills
        self.executor = executor
    }

    public func proposeEdits(_ request: LearnAgentRequest) async throws -> LearnAgentOutcome {
        let bodies = resolveSkillBodies(request)
        let editable = Self.editableFiles(request)
        let prompt = LearnPromptBuilder.build(request, skillBodies: bodies.bodies, editableFiles: editable)
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
        // A non-zero exit (auth/billing/model/CLI error) must surface as a failure
        // like the review path (AgentInvoker) does, not be reported as "no edits".
        guard result.status == 0 else {
            throw AgentError.nonZeroExit(
                agent: request.agent.kind.rawValue, status: result.status, stderrTail: result.stderrTail()
            )
        }

        let proposal = (try? LearnProposal.parse(Self.unwrapEnvelope(result.stdoutText))) ?? LearnProposal()
        return LearnAgentOutcome(
            edits: proposal.proposedEdits,
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

    // MARK: - Editable-file enumeration

    /// The review-setup files the scope may edit, with their current contents: the
    /// scope's `baton.toml`, any agent-doc file present at the scope root, and every
    /// file under the scope's local skill directories. Mirrors ``EditAllowlist``'s
    /// notion of what is allowed so the snapshot matches what Baton will accept.
    static func editableFiles(_ request: LearnAgentRequest) -> [(path: String, contents: String)] {
        let allowlist = EditAllowlist(scopePath: request.scopePath, localSkillDirs: request.localSkillDirs)
        var paths: Set<String> = []

        paths.insert(scopeRelative(request.scopePath, "baton.toml"))
        for doc in agentDocNames {
            paths.insert(scopeRelative(request.scopePath, doc))
        }
        for dir in request.localSkillDirs {
            paths.formUnion(filesUnder(dir, repoRoot: request.repoRoot))
        }

        return paths.sorted()
            .filter(allowlist.isAllowed)
            .compactMap { path in
                guard let contents = readContents(request.repoRoot, path) else { return nil }
                return (path, contents)
            }
    }

    private static let agentDocNames = ["CLAUDE.md", "AGENTS.md", "GEMINI.md", "OPENCODE.md", "AGENT.md"]

    private static func scopeRelative(_ scopePath: String, _ name: String) -> String {
        scopePath.isEmpty ? name : "\(scopePath)/\(name)"
    }

    /// Every file under `dir` (repo-relative), recursively, as repo-relative paths.
    private static func filesUnder(_ dir: String, repoRoot: URL) -> Set<String> {
        let base = repoRoot.appendingPathComponent(dir, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: base, includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return []
        }
        var result: Set<String> = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            result.insert(relative(url, to: repoRoot))
        }
        return result
    }

    private static func relative(_ url: URL, to repoRoot: URL) -> String {
        let rootPath = repoRoot.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private static func readContents(_ repoRoot: URL, _ path: String) -> String? {
        let url = repoRoot.appendingPathComponent(path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(bytes: data, encoding: .utf8)
    }

    // MARK: - Envelope unwrap

    /// Unwrap the agent's JSON envelope to the inner model text. Claude's
    /// `--output-format json` wraps the reply in `{"result":"…"}`; we unwrap that
    /// here before parsing the inner proposal. Non-enveloped output (other CLIs)
    /// passes through unchanged.
    static func unwrapEnvelope(_ stdout: String) -> String {
        guard let data = stdout.data(using: .utf8),
              let envelope = try? JSONCodec.decode(Envelope.self, from: data),
              let inner = envelope.result
        else {
            return stdout
        }
        return inner
    }

    private struct Envelope: Decodable {
        var result: String?
    }
}
