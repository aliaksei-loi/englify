import Foundation

/// Classified failure of an Improve call. The UI maps each case to a specific
/// actionable card; `.unknown` carries the raw stderr so users can at least see
/// what went wrong.
public enum FailureMode: Sendable, Equatable, Error {
    case cliNotFound
    case notAuthenticated
    case offline
    case timeout
    case unknown(String)
}

/// Maps subprocess-level signals (exit code, stderr, cliMissing flag, timedOut
/// flag) onto a `FailureMode`. Precedence: cliMissing > timedOut > stderr
/// markers > unknown.
public enum FailureClassifier {
    public static func classify(exitCode: Int32, stderr: String, cliMissing: Bool, timedOut: Bool) -> FailureMode {
        if cliMissing { return .cliNotFound }
        if timedOut { return .timeout }
        let lower = stderr.lowercased()
        let authMarkers = ["not authenticated", "please log in", "please run `claude`", "please run claude", "login required"]
        if authMarkers.contains(where: { lower.contains($0) }) { return .notAuthenticated }
        let netMarkers = ["network", "could not resolve", "offline", "dns", "timed out", "no internet"]
        if netMarkers.contains(where: { lower.contains($0) }) { return .offline }
        return .unknown(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
