import Foundation
import Jinja

/// Renders a human-facing report from a Jinja template, mapping any template
/// parse/render failure to a typed ``RenderError``.
///
/// This is the only place swift-jinja is used (MVP design Decision 4: swift-jinja
/// for report templates, never the prompt scaffold). Markdown carries literal HTML
/// (`<details>`/`<sub>`), so no autoescaping is applied — the template renders raw.
enum ReportTemplating {
    static func render(template source: String, context: [String: Value], path: String?) throws -> String {
        do {
            let template = try Template(source, with: .init(lstripBlocks: true, trimBlocks: true))
            return try template.render(context)
        } catch let error as RenderError {
            throw error
        } catch {
            throw RenderError.templateInvalid(path: path, detail: "\(error)")
        }
    }

    /// Load a user-override template from `path` (relative paths resolved against
    /// `configDir`), or return `nil` when no override is configured.
    static func userTemplate(path: String?, configDir: URL) throws -> (source: String, path: String)? {
        guard let path, !path.isEmpty else { return nil }
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : configDir.appendingPathComponent(path)
        do {
            return try (String(contentsOf: url, encoding: .utf8), path)
        } catch {
            throw RenderError.templateInvalid(path: path, detail: "could not read the template file: \(error)")
        }
    }
}
