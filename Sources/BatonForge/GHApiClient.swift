import BatonKit
import Foundation

/// Shared `gh api` invocation with bounded retry on transient failures.
///
/// Centralizes the retry loop, the transient (rate-limit / 5xx) classification, the
/// `http NNN` status extraction, and the combined stderr+stdout error text that the
/// publish / learn-read / learn-deliver forges otherwise each duplicated. Every
/// caller supplies its own `mapError` policy for terminal (non-retryable) failures,
/// so the per-forge differences (Check Run vs write-permission degrade, 422
/// handling) stay explicit while the retry mechanics live in one tested place.
struct GHApiClient {
    let gh: GHRunning
    let maxAttempts: Int

    /// Run `gh` with `args`, retrying on a transient (rate-limit / 5xx) failure up
    /// to `maxAttempts`. On a terminal failure, throws `mapError(result)`.
    func run(
        _ args: [String],
        stdin: String? = nil,
        mapError: (GHResult) -> ForgeError
    ) async throws -> GHResult {
        var lastError = ""
        for attempt in 1 ... max(1, maxAttempts) {
            let result = try await gh.run(args, stdin: stdin)
            if result.isSuccess { return result }
            lastError = Self.errorText(result)
            if Self.isTransient(result), attempt < maxAttempts { continue }
            throw mapError(result)
        }
        throw ForgeError.publishFailed(detail: lastError)
    }

    /// Whether a failure is a retryable transient (rate limit / 429 / 5xx).
    static func isTransient(_ result: GHResult) -> Bool {
        transientError(result) != nil
    }

    /// The typed transient error (`.rateLimited` / `.serverError`), or nil when the
    /// failure is not transient — so a caller's `mapError` can reuse the exact
    /// classification for its final thrown error.
    static func transientError(_ result: GHResult) -> ForgeError? {
        let detail = errorText(result)
        let text = detail.lowercased()
        if text.contains("rate limit") || text.contains("429") { return .rateLimited(detail: detail) }
        if let status = httpStatus(text), (500 ... 599).contains(status) { return .serverError(detail: detail) }
        return nil
    }

    /// `gh`'s combined stderr+stdout, trimmed, with a status fallback.
    static func errorText(_ result: GHResult) -> String {
        let combined = (result.stderr + "\n" + result.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
        return combined.isEmpty ? "gh exited with status \(result.status)" : combined
    }

    /// Extract `NNN` from a `http NNN` status line (text already lowercased).
    static func httpStatus(_ text: String) -> Int? {
        guard let range = text.range(of: #"http (\d{3})"#, options: .regularExpression) else { return nil }
        return Int(text[range].suffix(3))
    }
}
