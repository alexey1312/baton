import Foundation

/// The structured proposal an agent returns from a learning pass — a JSON object
/// of shape `{"themes":[…],"edits":[{"path","contents"}]}` (mirrors blick's
/// `LEARN_SYSTEM_PROMPT` output contract). The agent emits text only; the host
/// parses this and writes the allowlisted files itself, so no agentic file edits
/// or tool turns are needed.
public struct LearnProposal: Decodable, Sendable, Equatable {
    /// A reflection theme backing the proposed edits (kept for the preview /
    /// rationale; parsing never fails on its absence).
    public struct Theme: Decodable, Sendable, Equatable {
        public var title: String
        public var rationale: String?
        public var evidence: [String]

        public init(title: String, rationale: String? = nil, evidence: [String] = []) {
            self.title = title
            self.rationale = rationale
            self.evidence = evidence
        }

        private enum CodingKeys: String, CodingKey {
            case title, rationale, evidence
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = (try? container.decode(String.self, forKey: .title)) ?? ""
            rationale = try? container.decode(String.self, forKey: .rationale)
            evidence = (try? container.decode([String].self, forKey: .evidence)) ?? []
        }
    }

    /// One proposed file rewrite: a repo-relative path and the FULL new contents.
    public struct Edit: Decodable, Sendable, Equatable {
        public var path: String
        public var contents: String

        public init(path: String, contents: String) {
            self.path = path
            self.contents = contents
        }
    }

    public var themes: [Theme]
    public var edits: [Edit]

    public init(themes: [Theme] = [], edits: [Edit] = []) {
        self.themes = themes
        self.edits = edits
    }

    private enum CodingKeys: String, CodingKey {
        case themes, edits
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        themes = (try? container.decode([Theme].self, forKey: .themes)) ?? []
        edits = (try? container.decode([Edit].self, forKey: .edits)) ?? []
    }

    /// Map the parsed edits to ``ProposedEdit`` (full contents → `newContents`).
    public var proposedEdits: [ProposedEdit] {
        edits.map { ProposedEdit(path: $0.path, newContents: $0.contents) }
    }

    /// Parse a ``LearnProposal`` from agent text. Tolerates an optional
    /// ```json … ``` markdown fence (some CLIs wrap JSON despite the instruction)
    /// and surrounding prose by extracting the outermost `{ … }` object.
    public static func parse(_ text: String) throws -> LearnProposal {
        let json = extractJSON(from: text)
        guard let data = json.data(using: .utf8) else {
            return LearnProposal()
        }
        return try JSONCodec.decode(LearnProposal.self, from: data)
    }

    /// Strip a fenced code block and/or surrounding prose, returning the JSON body.
    private static func extractJSON(from text: String) -> String {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fenced = fencedBody(body) {
            body = fenced.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Fall back to the outermost object when the agent wraps JSON in prose.
        if !body.hasPrefix("{"), let start = body.firstIndex(of: "{"),
           let end = body.lastIndex(of: "}")
        {
            body = String(body[start ... end])
        }
        return body
    }

    /// Extract the contents of the first ```…``` fence (optionally tagged `json`).
    private static func fencedBody(_ text: String) -> String? {
        guard let open = text.range(of: "```") else { return nil }
        var rest = text[open.upperBound...]
        // Drop an optional language tag up to the first newline.
        if let newline = rest.firstIndex(of: "\n") {
            let tag = rest[rest.startIndex ..< newline].trimmingCharacters(in: .whitespaces)
            if tag.isEmpty || tag.allSatisfy(\.isLetter) {
                rest = rest[rest.index(after: newline)...]
            }
        }
        guard let close = rest.range(of: "```") else { return nil }
        return String(rest[rest.startIndex ..< close.lowerBound])
    }
}
