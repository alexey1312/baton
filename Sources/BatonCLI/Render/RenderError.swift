import BatonKit

/// Errors raised while rendering a saved run.
enum RenderError: BatonError {
    /// A GitHub-anchored format was selected without a head SHA.
    case headSHARequired(format: String)
    /// A report template (bundled default or user override) failed to parse or render.
    case templateInvalid(path: String?, detail: String)
    /// `--template` was passed with a format that is not user-templatable.
    case templateNotSupported(format: String)

    var errorDescription: String? {
        switch self {
        case let .headSHARequired(format):
            "The '\(format)' format requires a head commit SHA"
        case let .templateInvalid(path, detail):
            "The report template\(path.map { " '\($0)'" } ?? "") is invalid: \(detail)"
        case let .templateNotSupported(format):
            "The '\(format)' format is not user-templatable"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .headSHARequired:
            "Pass --head-sha <sha> (or run inside GitHub Actions where it is provided)."
        case .templateInvalid:
            "Fix the Jinja syntax in your [render] template, or remove it to use the built-in default."
        case .templateNotSupported:
            "Drop --template; GitHub formats keep their required marker, reaction affordance, and AI block. " +
                "Templates apply to the 'markdown' format only."
        }
    }
}
