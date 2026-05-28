import Foundation

/// Findings parsed from an agent's textual output, plus any non-fatal warnings
/// produced while clamping or dropping malformed fields.
public struct ParsedFindings: Sendable {
    public var findings: [Finding]
    public var warnings: [String]
}

/// Robustly extracts `[Finding]` from an agent's textual output.
///
/// Tries, in order: plain JSON, a fenced ```` ```json ```` block, then
/// brace-/bracket-balanced extraction that ignores delimiters inside string
/// literals. Malformed individual findings are dropped or clamped (never crashes
/// the run) with a warning.
public enum FindingsParser {
    /// A loosely-typed finding as emitted by the agent.
    private struct RawFinding: Decodable {
        var file: String?
        var line: Int?
        var severity: String?
        var title: String?
        var body: String?
        var instructions: String?
    }

    private struct RawPayload: Decodable {
        var findings: [RawFinding]?
    }

    /// Parse `text` into findings. Throws when no JSON structure can be extracted at
    /// all (as opposed to a well-formed but empty findings list).
    public static func parse(_ text: String) throws -> ParsedFindings {
        guard let raws = extractRaws(from: text) else {
            throw ExtractionFailure()
        }
        var findings: [Finding] = []
        var warnings: [String] = []

        for raw in raws {
            guard let file = raw.file, !file.isEmpty else {
                warnings.append("Dropped a finding with no `file`.")
                continue
            }
            let severity: Severity
            if let value = raw.severity, let parsed = Severity(rawValue: value.lowercased()) {
                severity = parsed
            } else {
                severity = .medium
                warnings.append("Finding for '\(file)' had invalid/missing severity; clamped to medium.")
            }
            findings.append(Finding(
                file: file,
                line: raw.line,
                severity: severity,
                title: raw.title ?? "(untitled)",
                body: raw.body ?? "",
                aiInstructions: raw.instructions
            ))
        }
        return ParsedFindings(findings: findings, warnings: warnings)
    }

    /// Thrown when no JSON could be located in the output.
    public struct ExtractionFailure: Error {}

    // MARK: - Extraction strategies

    private static func extractRaws(from text: String) -> [RawFinding]? {
        // 1. Plain JSON (array or {findings:[…]}).
        if let raws = decode(text) { return raws }
        // 2. Fenced ```json … ``` block.
        if let fenced = fencedBlock(in: text), let raws = decode(fenced) { return raws }
        // 3. Brace-balanced object, then bracket-balanced array.
        if let object = balanced(in: text, open: "{", close: "}"), let raws = decode(object) { return raws }
        if let array = balanced(in: text, open: "[", close: "]"), let raws = decode(array) { return raws }
        return nil
    }

    private static func decode(_ json: String) -> [RawFinding]? {
        let data = Data(json.utf8)
        if let array = try? JSONDecoder().decode([RawFinding].self, from: data) { return array }
        if let payload = try? JSONDecoder().decode(RawPayload.self, from: data), let findings = payload.findings {
            return findings
        }
        return nil
    }

    /// Extract the contents of the first ```` ```json ```` (or bare ```` ``` ````) fence.
    private static func fencedBlock(in text: String) -> String? {
        guard let fenceStart = text.range(of: "```") else { return nil }
        let afterFence = text[fenceStart.upperBound...]
        // Skip an optional language tag up to the newline.
        guard let newline = afterFence.firstIndex(of: "\n") else { return nil }
        let body = afterFence[afterFence.index(after: newline)...]
        guard let closing = body.range(of: "```") else { return nil }
        return String(body[..<closing.lowerBound])
    }

    /// Return the first balanced `open…close` span, ignoring delimiters inside
    /// double-quoted string literals (honoring backslash escapes).
    private static func balanced(in text: String, open: Character, close: Character) -> String? {
        guard let start = text.firstIndex(of: open) else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let char = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == "\"" {
                    inString = false
                }
            } else if char == "\"" {
                inString = true
            } else if char == open {
                depth += 1
            } else if char == close {
                depth -= 1
                if depth == 0 {
                    return String(text[start ... index])
                }
            }
            index = text.index(after: index)
        }
        return nil
    }
}
