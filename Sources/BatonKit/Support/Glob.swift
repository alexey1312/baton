import Foundation

/// A small glob matcher for path-like strings.
///
/// Supports `**` (any characters, including `/`), `**/` (zero or more directory
/// segments), `*` (any characters except `/`), and `?` (one character except
/// `/`). Used for per-review file filtering (`**/*.swift`) and the remote-skill
/// source allowlist (`org/*`).
public struct Glob: Sendable {
    private let regex: NSRegularExpression?
    public let pattern: String

    public init(_ pattern: String) {
        self.pattern = pattern
        regex = try? NSRegularExpression(pattern: "^\(Glob.translate(pattern))$")
    }

    /// Whether `path` matches this glob.
    public func matches(_ path: String) -> Bool {
        guard let regex else { return false }
        let range = NSRange(path.startIndex ..< path.endIndex, in: path)
        return regex.firstMatch(in: path, range: range) != nil
    }

    /// Whether `path` matches any of the `patterns`.
    public static func matchesAny(_ patterns: [String], path: String) -> Bool {
        patterns.contains { Glob($0).matches(path) }
    }

    /// Translate a glob pattern into an anchored regular-expression body.
    static func translate(_ pattern: String) -> String {
        var result = ""
        let chars = Array(pattern)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            switch c {
            case "*":
                if i + 1 < chars.count, chars[i + 1] == "*" {
                    // "**/" matches zero or more directory segments; bare "**" any chars.
                    if i + 2 < chars.count, chars[i + 2] == "/" {
                        result += "(?:.*/)?"
                        i += 3
                    } else {
                        result += ".*"
                        i += 2
                    }
                    continue
                }
                result += "[^/]*"
            case "?":
                result += "[^/]"
            default:
                result += NSRegularExpression.escapedPattern(for: String(c))
            }
            i += 1
        }
        return result
    }
}
