import Foundation

extension SkillResolver {
    func readBody(_ url: URL, skillName: String) throws -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw SkillError.missingSkillFile(name: skillName, searchedPath: url.deletingLastPathComponent().path)
        }
    }

    /// Reject `url` when its symlink-resolved canonical path falls outside `base`,
    /// when the path is dangling (resolved target does not exist), or when any
    /// intermediate component cannot be canonicalised. `resolvingSymlinksInPath()`
    /// can return the input unchanged for a dangling target, so the existence
    /// check is required to close that gap.
    func assertNoSymlinkEscape(_ url: URL, within base: URL, skillName: String) throws {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let resolvedBase = base.resolvingSymlinksInPath().standardizedFileURL
        if !FileManager.default.fileExists(atPath: resolved.path) {
            throw SkillError.symlinkEscape(name: skillName, path: resolved.path)
        }
        var basePath = resolvedBase.path
        if !basePath.hasSuffix("/") {
            basePath += "/"
        }
        guard resolved.path == resolvedBase.path || resolved.path.hasPrefix(basePath) else {
            throw SkillError.symlinkEscape(name: skillName, path: resolved.path)
        }
    }
}
