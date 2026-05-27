import Noora

/// Adapter for the Noora design system.
///
/// Provides a shared `Noora` instance and convenience helpers for semantic,
/// optionally-colored terminal text. Color is decided by the caller (driven by
/// the resolved ``OutputMode``).
enum NooraUI {
    /// Shared Noora instance with the default theme.
    static let shared = Noora()

    /// Format semantic `TerminalText` into an ANSI string.
    static func format(_ text: TerminalText) -> String {
        shared.format(text)
    }

    /// Format a single component (e.g. `.primary("text")`).
    static func format(_ component: TerminalText.Component) -> String {
        shared.format("\(component)")
    }

    static func success(_ message: String, useColors: Bool) -> String {
        guard useColors else { return "✓ \(message)" }
        return format("\(.success("✓")) \(message)")
    }

    static func error(_ message: String, useColors: Bool) -> String {
        guard useColors else { return "✗ \(message)" }
        return format("\(.danger("✗")) \(.danger(message))")
    }

    static func warning(_ message: String, useColors: Bool) -> String {
        guard useColors else { return "⚠ \(message)" }
        return format("\(.accent("⚠")) \(.accent(message))")
    }

    static func info(_ message: String, useColors: Bool) -> String {
        guard useColors else { return message }
        return format("\(.primary(message))")
    }

    static func muted(_ message: String, useColors: Bool) -> String {
        guard useColors else { return message }
        return format("\(.muted(message))")
    }
}
