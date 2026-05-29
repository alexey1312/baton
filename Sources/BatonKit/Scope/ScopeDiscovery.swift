import Foundation

/// The outcome of walking a repository for scopes.
public struct DiscoveryResult: Sendable {
    public var scopes: [ScopeConfig]
    public var warnings: [String]

    public init(scopes: [ScopeConfig], warnings: [String]) {
        self.scopes = scopes
        self.warnings = warnings
    }
}

/// Walks the repository tree and registers every directory containing a
/// `baton.toml` as a scope, safely (no symlinked directories, never escaping the
/// repository root) and skipping common vendored/build directories.
public enum ScopeDiscovery {
    /// Directories never descended into during discovery.
    public static let excludedDirs: Set<String> = [
        ".git", "node_modules", "target", "dist", "build", ".venv",
    ]

    /// Discover all scopes under `repoRoot`.
    public static func discover(repoRoot: URL) throws -> DiscoveryResult {
        var scopes: [ScopeConfig] = []
        var warnings: [String] = []

        try walk(directory: repoRoot.standardizedFileURL, relative: "", warn: { warnings.append($0) }) { dir, relative in
            let configURL = dir.appendingPathComponent("baton.toml")
            guard FileManager.default.fileExists(atPath: configURL.path) else { return }

            let configRelative = relative.isEmpty ? "baton.toml" : "\(relative)/baton.toml"
            let text = try String(contentsOf: configURL, encoding: .utf8)
            let parsed = try ConfigParser.parse(text, path: configRelative)
            warnings.append(contentsOf: parsed.warnings)

            let autoSkills = discoverLocalSkills(in: dir)
            scopes.append(ScopeConfig(
                path: relative,
                configPath: configRelative,
                config: parsed.config,
                autoSkills: autoSkills
            ))
        }

        guard !scopes.isEmpty else {
            throw ConfigError.noConfigFound(repoRoot: repoRoot.path)
        }

        return DiscoveryResult(scopes: scopes, warnings: warnings)
    }

    // MARK: - Tree walk

    private static func walk(
        directory: URL,
        relative: String,
        warn: (String) -> Void,
        visit: (_ dir: URL, _ relative: String) throws -> Void
    ) throws {
        try visit(directory, relative)

        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(keys),
                options: []
            )
        } catch {
            // An unreadable subtree is surfaced as a warning rather than silently
            // treated as empty, which would drop any scopes nested beneath it.
            warn("Skipped unreadable directory '\(relative.isEmpty ? "." : relative)' "
                + "during scope discovery: \(error.localizedDescription)")
            return
        }

        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = entry.lastPathComponent
            if excludedDirs.contains(name) { continue }

            let values = try? entry.resourceValues(forKeys: keys)
            // Do not follow symlinked directories (prevents escaping the repo root).
            if values?.isSymbolicLink == true { continue }
            guard values?.isDirectory == true else { continue }

            // Thread the relative path through recursion so it never depends on
            // absolute-path string math (robust to /var vs /private/var resolution).
            let childRelative = relative.isEmpty ? name : "\(relative)/\(name)"
            try walk(directory: entry, relative: childRelative, warn: warn, visit: visit)
        }
    }

    /// Auto-discover skills under `<scope>/.baton/skills/<name>/` that contain a
    /// `SKILL.md` or `README.md`.
    static func discoverLocalSkills(in scopeDir: URL) -> [SkillConfig] {
        let skillsDir = scopeDir.appendingPathComponent(".baton/skills", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: skillsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else {
            return []
        }

        return entries
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { entry -> SkillConfig? in
                guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                    return nil
                }
                let hasBody = FileManager.default.fileExists(atPath: entry.appendingPathComponent("SKILL.md").path)
                    || FileManager.default.fileExists(atPath: entry.appendingPathComponent("README.md").path)
                guard hasBody else { return nil }
                let name = entry.lastPathComponent
                return SkillConfig(name: name, source: "./.baton/skills/\(name)")
            }
    }
}
