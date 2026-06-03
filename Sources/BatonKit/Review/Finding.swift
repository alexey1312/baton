/// A single issue reported by an agent review.
///
/// Findings are anchored to a `file` and, when textual, a `line`. Binary or
/// file-level findings omit `line`. `aiInstructions`, when present, populates the
/// collapsible "Instructions for AI agents" block in GitHub renderings.
public struct Finding: Codable, Hashable, Sendable {
    /// Repository-relative path of the file the finding refers to.
    public var file: String
    /// 1-based line number inside the file, or `nil` for file-level findings.
    public var line: Int?
    /// Severity of the finding.
    public var severity: Severity
    /// Short, single-line summary.
    public var title: String
    /// Full explanation of the finding.
    public var body: String
    /// Optional remediation guidance aimed at an AI agent.
    public var aiInstructions: String?
    /// Names of the reviews that independently reported this finding after
    /// cross-task dedup. Empty for a finding reported by a single review;
    /// `count >= 2` means the finding was confirmed by multiple reviews.
    public var confirmedBy: [String]

    public init(
        file: String,
        line: Int? = nil,
        severity: Severity,
        title: String,
        body: String,
        aiInstructions: String? = nil,
        confirmedBy: [String] = []
    ) {
        self.file = file
        self.line = line
        self.severity = severity
        self.title = title
        self.body = body
        self.aiInstructions = aiInstructions
        self.confirmedBy = confirmedBy
    }

    enum CodingKeys: String, CodingKey {
        case file, line, severity, title, body
        case aiInstructions = "instructions"
        case confirmedBy = "confirmed_by"
    }

    /// Custom decode so legacy run records written before `confirmed_by` existed
    /// still load (the key is simply absent → `[]`). `encode(to:)` stays synthesized.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        file = try container.decode(String.self, forKey: .file)
        line = try container.decodeIfPresent(Int.self, forKey: .line)
        severity = try container.decode(Severity.self, forKey: .severity)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        aiInstructions = try container.decodeIfPresent(String.self, forKey: .aiInstructions)
        confirmedBy = try container.decodeIfPresent([String].self, forKey: .confirmedBy) ?? []
    }

    /// Identity used to deduplicate findings merged across diff chunks:
    /// `(file, line, severity, title)`.
    public struct DedupeKey: Hashable, Sendable {
        public let file: String
        public let line: Int?
        public let severity: Severity
        public let title: String
    }

    /// The dedupe identity for this finding.
    public var dedupeKey: DedupeKey {
        DedupeKey(file: file, line: line, severity: severity, title: title)
    }
}
