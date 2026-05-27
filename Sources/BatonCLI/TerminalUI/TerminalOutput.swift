import Foundation

/// Thread-safe sink for terminal output.
///
/// Serializes writes to stdout/stderr so concurrent review tasks cannot interleave
/// partial lines. A simplified stand-in for ExFig's `TerminalOutputManager` (Baton
/// has no animated batch progress view in the MVP).
final class TerminalOutput: @unchecked Sendable {
    static let shared = TerminalOutput()

    private let lock = NSLock()

    private init() {}

    /// Write a line to stdout.
    func out(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        print(message)
    }

    /// Write a line to stderr.
    func err(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
