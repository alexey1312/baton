import Foundation

/// A skill resolved into trusted markdown for prompt assembly.
///
/// ``body`` is the raw `SKILL.md` (preferred) or `README.md` content read from the
/// resolved skill directory. This text is *untrusted*: it may originate from a
/// third-party repository. Callers MUST embed ``body`` inside a clearly delimited
/// untrusted block in the assembled prompt (see PromptBuilder, phase 6) so it is
/// treated as reference data and can never occupy an instruction position that
/// overrides the review rules.
public struct ResolvedSkill: Sendable {
    /// The skill's declared name (from `[[skills]]`).
    public var name: String
    /// The raw `SKILL.md`/`README.md` content. Untrusted; embed in a delimited block.
    public var body: String
    /// A human-readable description of where the body came from (for logs/provenance).
    public var sourceDescription: String

    public init(name: String, body: String, sourceDescription: String) {
        self.name = name
        self.body = body
        self.sourceDescription = sourceDescription
    }
}
