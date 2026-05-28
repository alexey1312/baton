import Foundation

/// Creates the fresh temporary working directory each agent runs in, so the agent
/// can never write to the real repository working tree.
///
/// For `context = .repo`, a *copy* of the repository (excluding `.git`, `.build`,
/// `.baton`, and common vendored dirs) is placed alongside, never the live tree.
/// Network egress is intentionally NOT blocked — the external CLI must reach its
/// model provider (see the agent-execution spec).
public enum Isolation {
    private static let excludedFromCopy: Set<String> = [
        ".git", ".build", ".baton", "node_modules", ".venv", "target", "dist", "build",
    ]

    /// Make a fresh working directory for one agent invocation.
    public static func makeWorkspace(
        context: ReviewContext,
        repoRoot: URL,
        parentDirectory: URL = FileManager.default.temporaryDirectory
    ) throws -> URL {
        let workspace = parentDirectory
            .appendingPathComponent("baton-agent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        if context == .repo {
            let destination = workspace.appendingPathComponent("repo", isDirectory: true)
            try copyRepository(from: repoRoot, to: destination)
        }
        return workspace
    }

    /// Best-effort cleanup of a workspace.
    public static func cleanup(_ workspace: URL) {
        try? FileManager.default.removeItem(at: workspace)
    }

    private static func copyRepository(from source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil,
            options: []
        )) ?? []
        for entry in entries where !excludedFromCopy.contains(entry.lastPathComponent) {
            try? FileManager.default.copyItem(
                at: entry,
                to: destination.appendingPathComponent(entry.lastPathComponent)
            )
        }
    }
}
