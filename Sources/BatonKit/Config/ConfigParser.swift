import Foundation
import TOML

/// A successfully parsed `baton.toml` together with any non-fatal warnings.
public struct ParsedConfig: Sendable {
    public let config: BatonConfig
    public let warnings: [String]

    public init(config: BatonConfig, warnings: [String] = []) {
        self.config = config
        self.warnings = warnings
    }
}

/// Parses and validates a single `baton.toml`.
///
/// Decoding is lenient about unknown keys (forward compatibility) but emits a
/// warning naming each ignored key, and hard-fails on structural/type errors and
/// invalid enum values such as an unknown `[agent].kind`.
public enum ConfigParser {
    private static let knownTopLevel: Set<String> = [
        "agent", "defaults", "skills", "reviews", "disabled_reviews", "security", "learn",
    ]
    private static let knownAgent: Set<String> = ["kind", "model", "binary", "args", "context"]
    private static let knownDefaults: Set<String> = [
        "base", "fail_on", "max_concurrency", "diff_budget", "chunk_strategy", "timeout",
    ]
    private static let knownSkill: Set<String> = ["name", "source", "ref", "subpath"]
    private static let knownReview: Set<String> = [
        "name", "skills", "glob", "fail_on", "context", "prompt", "prompt_file", "agent",
    ]
    private static let knownSecurity: Set<String> = [
        "require_pinned_skills", "allowed_skill_sources", "references_budget_kb",
    ]
    private static let knownLearn: Set<String> = [
        "branch", "base", "reviewers", "team_reviewers", "labels", "draft",
        "lookback_days", "min_signal", "enabled", "count_author_reactions",
    ]

    /// Parse `baton.toml` text from the file at `path`.
    public static func parse(_ text: String, path: String) throws -> ParsedConfig {
        // Surface a precise error for an invalid agent kind, with the offending value.
        if let kind = try? rawAgentKind(text), AgentKind(rawValue: kind) == nil {
            throw ConfigError.invalidAgentKind(path: path, value: kind)
        }

        // Use explicit CodingKeys (snake_case) rather than the decoder's
        // .convertFromSnakeCase strategy, which converts the requested camelCase
        // key (a no-op) and then fails to find the snake_case TOML key.
        let decoder = TOMLDecoder()

        let config: BatonConfig
        do {
            config = try decoder.decode(BatonConfig.self, from: text)
        } catch {
            throw ConfigError.malformedTOML(path: path, underlying: cleanMessage(error))
        }

        try validateDuplicates(config, path: path)

        return ParsedConfig(config: config, warnings: unknownKeyWarnings(text, path: path))
    }

    // MARK: - Helpers

    /// Decode just `[agent].kind` as a raw string (never fails on an invalid value).
    private static func rawAgentKind(_ text: String) throws -> String? {
        struct Probe: Decodable {
            struct Agent: Decodable { var kind: String? }
            var agent: Agent?
        }
        return try TOMLDecoder().decode(Probe.self, from: text).agent?.kind
    }

    private static func validateDuplicates(_ config: BatonConfig, path: String) throws {
        if let dup = firstDuplicate((config.reviews ?? []).map(\.name)) {
            throw ConfigError.duplicateReviewName(path: path, name: dup)
        }
        if let dup = firstDuplicate((config.skills ?? []).map(\.name)) {
            throw ConfigError.duplicateSkillName(path: path, name: dup)
        }
    }

    private static func firstDuplicate(_ names: [String]) -> String? {
        var seen: Set<String> = []
        for name in names where !seen.insert(name).inserted {
            return name
        }
        return nil
    }

    private static func unknownKeyWarnings(_ text: String, path: String) -> [String] {
        guard let tree = try? TOMLDecoder().decode(TOMLKeyTree.self, from: text),
              case let .table(top) = tree
        else {
            return []
        }

        var warnings: [String] = []
        for (key, value) in top.sorted(by: { $0.key < $1.key }) {
            if !knownTopLevel.contains(key) {
                warnings.append("\(path): ignoring unknown key '\(key)'")
                continue
            }
            switch (key, value) {
            case let ("agent", .table(fields)):
                warnings += unknown(fields, known: knownAgent, prefix: "agent", path: path)
            case let ("defaults", .table(fields)):
                warnings += unknown(fields, known: knownDefaults, prefix: "defaults", path: path)
            case let ("security", .table(fields)):
                warnings += unknown(fields, known: knownSecurity, prefix: "security", path: path)
            case let ("learn", .table(fields)):
                warnings += unknown(fields, known: knownLearn, prefix: "learn", path: path)
            case let ("skills", .array(entries)):
                warnings += unknownInArray(entries, known: knownSkill, prefix: "skills", path: path)
            case let ("reviews", .array(entries)):
                warnings += unknownInArray(entries, known: knownReview, prefix: "reviews", path: path)
            default:
                break
            }
        }
        return warnings
    }

    private static func unknown(
        _ fields: [String: TOMLKeyTree],
        known: Set<String>,
        prefix: String,
        path: String
    ) -> [String] {
        fields.keys.filter { !known.contains($0) }.sorted()
            .map { "\(path): ignoring unknown key '\(prefix).\($0)'" }
    }

    private static func unknownInArray(
        _ entries: [TOMLKeyTree],
        known: Set<String>,
        prefix: String,
        path: String
    ) -> [String] {
        var warnings: [String] = []
        for entry in entries {
            if case let .table(fields) = entry {
                warnings += unknown(fields, known: known, prefix: prefix, path: path)
            }
        }
        return warnings
    }

    private static func cleanMessage(_ error: any Error) -> String {
        if let decoding = error as? DecodingError {
            switch decoding {
            case let .keyNotFound(key, _):
                return "missing required key '\(key.stringValue)'"
            case let .typeMismatch(_, ctx), let .valueNotFound(_, ctx):
                let pathDesc = ctx.codingPath.map(\.stringValue).joined(separator: ".")
                return pathDesc.isEmpty ? ctx.debugDescription : "at '\(pathDesc)': \(ctx.debugDescription)"
            case let .dataCorrupted(ctx):
                return ctx.debugDescription
            @unknown default:
                return "\(error)"
            }
        }
        return "\(error)"
    }
}
