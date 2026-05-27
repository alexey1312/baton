import Foundation
import Logging

/// A `LogHandler` that routes log output through ``TerminalOutput`` with
/// verbosity- and color-aware formatting.
struct BatonLogHandler: LogHandler {
    let label: String
    var logLevel: Logger.Level
    var metadata: Logger.Metadata = [:]
    private let outputMode: OutputMode

    init(label: String, logLevel: Logger.Level, outputMode: OutputMode) {
        self.label = label
        self.logLevel = logLevel
        self.outputMode = outputMode
    }

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(event: LogEvent) {
        // Quiet mode shows only warnings and errors.
        if outputMode == .quiet, event.level < .warning { return }

        let formatted: String
        if outputMode == .verbose {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let fileName = URL(fileURLWithPath: event.file).lastPathComponent
            formatted = "[\(event.level)] \(timestamp) \(fileName):\(event.line) \(event.message)"
        } else {
            formatted = formatMessage(level: event.level, message: "\(event.message)")
        }

        // Warnings and errors go to stderr; informational output to stdout.
        if event.level >= .warning {
            TerminalOutput.shared.err(formatted)
        } else {
            TerminalOutput.shared.out(formatted)
        }
    }

    private func formatMessage(level: Logger.Level, message: String) -> String {
        switch level {
        case .warning:
            NooraUI.warning(message, useColors: outputMode.useColors)
        case .error, .critical:
            NooraUI.error(message, useColors: outputMode.useColors)
        default:
            message
        }
    }
}

/// Bootstraps the logging system with Baton's terminal-aware handler.
enum BatonLogging {
    static func bootstrap(outputMode: OutputMode) {
        LoggingSystem.bootstrap { label in
            let level: Logger.Level = outputMode.showDebug ? .debug : .info
            return BatonLogHandler(label: label, logLevel: level, outputMode: outputMode)
        }
    }
}
