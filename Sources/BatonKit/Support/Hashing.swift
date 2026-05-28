/// FNV-1a 64-bit hash. Not cryptographic — used only to derive stable,
/// well-distributed ids for filesystem paths and finding keys.
///
/// Centralised here so the `RepoIdentity` and `RunDatabaseStore` callers do
/// not drift apart on the constants or byte iteration.
enum FNV1a {
    private static let offsetBasis: UInt64 = 0xCBF2_9CE4_8422_2325
    private static let prime: UInt64 = 0x100_0000_01B3

    static func hash(_ string: String) -> UInt64 {
        var hash = offsetBasis
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }
}
