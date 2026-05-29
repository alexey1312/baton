import Foundation

// Temporary probe to validate the Baton Review workflow end-to-end. Deliberately
// contains a concurrency/style issue so baton produces findings to publish.
final class E2EReviewProbe: @unchecked Sendable {
    var total = 0

    func bump(_ values: [Int]) {
        for v in values {
            total += v
        }
    }

    func first(of values: [Int]) -> Int {
        return values.first!
    }
}
