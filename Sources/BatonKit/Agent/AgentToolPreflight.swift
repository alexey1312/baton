import Foundation

/// Verifies that an agent's resolved binary is available before any task runs.
public enum AgentToolPreflight {
    /// Whether `binary` is runnable: an explicit path that is executable, or a bare
    /// name found on `PATH`.
    public static func isAvailable(
        _ binary: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        if binary.contains("/") {
            return FileManager.default.isExecutableFile(atPath: binary)
        }
        let path = environment["PATH"] ?? ""
        for directory in path.split(separator: ":") {
            let candidate = "\(directory)/\(binary)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return true
            }
        }
        return false
    }

    /// Resolve the executable for an agent: `[agent].binary` when set, otherwise the
    /// adapter's `defaultBinary`. A `custom` agent without a binary is rejected.
    public static func resolveBinary(kind: AgentKind, configBinary: String?) throws -> String {
        if let binary = configBinary, !binary.isEmpty { return binary }
        if kind == .custom { throw AgentError.customBinaryRequired }
        return AgentRegistry.runner(for: kind).defaultBinary
    }

    /// Throw `AgentError.binaryNotFound` when the resolved binary is unavailable.
    public static func verify(
        binary: String,
        agent: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        guard isAvailable(binary, environment: environment) else {
            throw AgentError.binaryNotFound(agent: agent, binary: binary)
        }
    }
}
