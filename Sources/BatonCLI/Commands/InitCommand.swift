import ArgumentParser
import BatonKit
import Foundation

/// `baton init` — write a starter `baton.toml`.
struct InitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Write a starter baton.toml."
    )

    @OptionGroup var global: GlobalOptions

    @Option(help: "Agent kind for the [agent] block (\(AgentKind.listForHelp)).")
    var agent: AgentKind = .claude

    @Option(help: "Model for the [agent] block.")
    var model: String?

    @Option(help: "Target directory or file for the baton.toml.")
    var path: String?

    @Flag(help: "Overwrite an existing baton.toml.")
    var force = false

    func run() async throws {
        try await present(global.outputMode) {
            let target = resolveTarget()
            if FileManager.default.fileExists(atPath: target.path), !force {
                throw InitError.fileExists(path: target.path)
            }
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try starterConfig().write(to: target, atomically: true, encoding: .utf8)
            TerminalOutput.shared.out(NooraUI.success("Wrote \(target.path)", useColors: global.outputMode.useColors))
        }
    }

    private func resolveTarget() -> URL {
        guard let path else {
            return URL(
                fileURLWithPath: "baton.toml",
                relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            )
        }
        let url = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if path.hasSuffix(".toml") { return url }
        if exists, isDir.boolValue { return url.appendingPathComponent("baton.toml") }
        // Treat a non-existent path without a .toml suffix as a directory.
        return url.appendingPathComponent("baton.toml")
    }

    private func starterConfig() -> String {
        var lines = [
            "# Baton configuration. See https://github.com/alexey1312/swift-baton",
            "",
            "[agent]",
            "kind = \"\(agent.rawValue)\"",
        ]
        if let model { lines.append("model = \"\(model)\"") }
        lines.append(contentsOf: [
            "",
            "[defaults]",
            "fail_on = \"high\"",
            "",
            "[[reviews]]",
            "name = \"general\"",
            "prompt = \"Review the changes for correctness, security, and clarity.\"",
            "",
        ])
        return lines.joined(separator: "\n")
    }
}

private enum InitError: BatonError {
    case fileExists(path: String)

    var errorDescription: String? {
        switch self {
        case let .fileExists(path): "baton.toml already exists at \(path)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .fileExists: "Pass --force to overwrite it."
        }
    }
}
