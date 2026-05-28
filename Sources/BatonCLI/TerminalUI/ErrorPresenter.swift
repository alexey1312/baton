import BatonKit
import Foundation

/// Presents errors on the terminal as `✗ <description>` and `  → <recovery>`,
/// colored via Noora when enabled.
enum ErrorPresenter {
    static func present(_ error: any Error, useColors: Bool) -> String {
        let localized = error as? any LocalizedError
        let description = localized?.errorDescription ?? error.localizedDescription
        var lines = [NooraUI.error(description, useColors: useColors)]
        if let recovery = localized?.recoverySuggestion {
            lines.append("  → \(NooraUI.muted(recovery, useColors: useColors))")
        }
        return lines.joined(separator: "\n")
    }
}
