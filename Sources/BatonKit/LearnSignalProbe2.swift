import Foundation

// Temporary fixture #2: a second force-unwrap so learn sees a 2-thread theme
// (same category as the first probe). Reverted after the learn --apply demo.
enum LearnSignalProbe2 {
    static func lastValue(_ values: [Int]) -> Int {
        return values.last!
    }
}
