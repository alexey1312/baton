import BatonKit

/// Errors raised while rendering a saved run.
enum RenderError: BatonError {
    /// A GitHub-anchored format was selected without a head SHA.
    case headSHARequired(format: String)

    var errorDescription: String? {
        switch self {
        case let .headSHARequired(format):
            "The '\(format)' format requires a head commit SHA"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .headSHARequired:
            "Pass --head-sha <sha> (or run inside GitHub Actions where it is provided)."
        }
    }
}
