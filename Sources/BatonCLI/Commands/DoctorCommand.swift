import ArgumentParser
import BatonKit
import Foundation

/// `baton doctor` — check required external tools and report their status.
struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check required external tools and report their status."
    )

    @OptionGroup var global: GlobalOptions

    @Option(help: "Repository root to inspect for configured agents.")
    var repo: String?

    func run() async throws {
        let colors = global.outputMode.useColors
        var checks: [ToolStatus] = []

        // git is always required.
        checks.append(presence("git", required: true))

        // gh — presence and, if present, authentication.
        var gh = presence("gh", required: true)
        if gh.present {
            gh.authenticated = ghAuthenticated()
            if gh.authenticated == false {
                gh.recovery = "Authenticate with `gh auth login` or set GH_TOKEN."
            }
        }
        checks.append(gh)

        // Agents — the configured ones if discoverable, else all built-ins.
        for kind in configuredAgentKinds() {
            let binary = (try? AgentToolPreflight.resolveBinary(kind: kind, configBinary: nil)) ?? kind.rawValue
            checks.append(presence(binary, label: "agent: \(kind.rawValue)", required: false))
        }

        for check in checks {
            TerminalOutput.shared.out(check.line(useColors: colors))
        }

        let failed = checks.contains { $0.required && (!$0.present || $0.authenticated == false) }
        if failed { throw ExitCode.failure }
    }

    // MARK: - Checks

    private struct ToolStatus {
        var label: String
        var present: Bool
        var required: Bool
        var authenticated: Bool?
        var recovery: String?

        func line(useColors: Bool) -> String {
            if !present {
                let msg = "\(label): missing" + (recovery.map { " — \($0)" } ?? "")
                return NooraUI.error(msg, useColors: useColors)
            }
            if authenticated == false {
                return NooraUI.warning(
                    "\(label): present but unauthenticated" + (recovery.map { " — \($0)" } ?? ""),
                    useColors: useColors
                )
            }
            let suffix = authenticated == true ? " (authenticated)" : ""
            return NooraUI.success("\(label): present\(suffix)", useColors: useColors)
        }
    }

    private func presence(_ binary: String, label: String? = nil, required: Bool) -> ToolStatus {
        ToolStatus(
            label: label ?? binary,
            present: AgentToolPreflight.isAvailable(binary),
            required: required,
            recovery: "Install \(binary) and ensure it is on your PATH."
        )
    }

    private func ghAuthenticated() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh", "auth", "status"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func configuredAgentKinds() -> [AgentKind] {
        guard let root = try? CLISupport.resolveRepoRoot(repo),
              let discovery = try? ScopeDiscovery.discover(repoRoot: root)
        else {
            return AgentKind.builtIn
        }
        let kinds = discovery.scopes.compactMap { $0.config.agent?.kind }
        return kinds.isEmpty ? AgentKind.builtIn : Array(Set(kinds)).sorted { $0.rawValue < $1.rawValue }
    }
}
