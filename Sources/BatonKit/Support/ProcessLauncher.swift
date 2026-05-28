import Foundation

/// Configures a `Process` to run an executable cross-platform.
///
/// On POSIX the executable is launched via `/usr/bin/env`, which performs the `PATH`
/// search (unchanged behavior). On Windows there is no `/usr/bin/env`, so the
/// executable is resolved against `PATH` + `PATHEXT` and launched directly.
public enum ProcessLauncher {
    /// Set `process.executableURL` and `process.arguments` to run `executable` with
    /// `arguments`, resolving the executable per platform.
    public static func configure(_ process: Process, executable: String, arguments: [String]) {
        #if os(Windows)
        let resolved = resolveOnPath(executable) ?? executable
        process.executableURL = URL(fileURLWithPath: resolved)
        process.arguments = arguments
        #else
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        #endif
    }

    #if os(Windows)
    /// Resolve a bare command name against `PATH`, trying each `PATHEXT` extension.
    /// Returns `nil` when not found (the caller falls back to the bare name so the
    /// resulting launch error is surfaced as a typed "not found").
    static func resolveOnPath(
        _ name: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        if name.contains("\\") || name.contains("/") || name.contains(":") {
            return name // already a path
        }
        let path = environment["Path"] ?? environment["PATH"] ?? ""
        let extensions = (environment["PATHEXT"] ?? ".COM;.EXE;.BAT;.CMD")
            .split(separator: ";").map(String.init)
        for directory in path.split(separator: ";") {
            let base = "\(directory)\\\(name)"
            if FileManager.default.isExecutableFile(atPath: base) { return base }
            for ext in extensions {
                let candidate = base + ext
                if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
            }
        }
        return nil
    }
    #endif
}
