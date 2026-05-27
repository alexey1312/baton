import Foundation

/// A domain error raised by Baton.
///
/// Every Baton error conforms to `LocalizedError` and carries a human-readable
/// ``errorDescription`` plus an actionable ``recoverySuggestion``. The CLI renders
/// these as `✗ <description>` followed by `  → <recovery>` (see ``BatonErrorFormatter``).
public protocol BatonError: LocalizedError, Sendable {
    var errorDescription: String? { get }
    var recoverySuggestion: String? { get }
}

/// Formats any `LocalizedError` (including ``BatonError``) into plain terminal text.
///
/// This formatter has no UI dependencies; the CLI layer wraps it with Noora colors.
public struct BatonErrorFormatter: Sendable {
    public init() {}

    /// Render a localized error as `✗ <description>` and, when present,
    /// a `  → <recovery>` line.
    public func format(_ error: any LocalizedError) -> String {
        let description = error.errorDescription ?? error.localizedDescription
        if let recovery = error.recoverySuggestion {
            return "✗ \(description)\n  → \(recovery)"
        }
        return "✗ \(description)"
    }

    /// Render any error, preferring `LocalizedError` details when available.
    public func format(_ error: any Error) -> String {
        if let localized = error as? any LocalizedError {
            return format(localized)
        }
        return "✗ \(error.localizedDescription)"
    }
}
