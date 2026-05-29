import Foundation

// Temporary fixture to generate one merged-PR review finding so `baton learn` has
// signal (a force-unwrap baton flags). Removed right after the learn demo.
enum LearnSignalProbe {
    static func firstValue(_ values: [Int]) -> Int {
        return values.first!
    }
}
