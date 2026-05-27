import Testing
@testable import BatonForge

@Suite("Forge protocol")
struct ForgeTests {
    /// A stand-in forge used to exercise the protocol surface until `GitHubForge`
    /// lands in the github-publish phase.
    struct StubForge: Forge {
        func preflight() async throws {}
    }

    @Test("Stub forge preflight succeeds")
    func preflight() async throws {
        try await StubForge().preflight()
    }
}
