@testable import BatonKit
import Testing

struct GlobTests {
    @Test("** / * / ? semantics")
    func semantics() {
        #expect(Glob("**/*.swift").matches("App/View.swift"))
        #expect(Glob("**/*.swift").matches("a/b/c.swift"))
        #expect(Glob("**/*.swift").matches("View.swift"))
        #expect(!Glob("**/*.swift").matches("docs/README.md"))
        #expect(Glob("*.swift").matches("View.swift"))
        #expect(!Glob("*.swift").matches("App/View.swift"))
        #expect(Glob("org/*").matches("org/skills"))
        #expect(!Glob("org/*").matches("attacker/evil"))
        #expect(Glob("trusted/skills").matches("trusted/skills"))
    }

    @Test("matchesAny over multiple patterns")
    func any() {
        #expect(Glob.matchesAny(["org/*", "trusted/skills"], path: "trusted/skills"))
        #expect(!Glob.matchesAny(["org/*"], path: "other/repo"))
    }
}
