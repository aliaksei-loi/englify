import Foundation

/// Structured payload returned by the `claude` subprocess for an Improve call.
///
/// Decoded from JSON using `keyDecodingStrategy = .convertFromSnakeCase`, so the
/// wire keys are `status`, `native`, `original_marked`, `mistakes`.
///
/// Phase 2 ships two statuses (`looks_good`, `rewritten`). Phase 3 will extend
/// the enum with `refused_russian` and `translated_from_ru`; existing call sites
/// must keep the field set stable to avoid churn.
public struct ImproveResponse: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable {
        case looksGood = "looks_good"
        case rewritten
        // Phase 3 will add: refused_russian, translated_from_ru.
    }

    /// Outcome of the rewrite.
    public let status: Status

    /// The native-sounding rewrite. For `status == .looksGood`, this is the
    /// user's input echoed back unchanged — Copy targets this field in both
    /// cases so the call site does not have to branch on status to pick text.
    public let native: String

    /// The user's input with error spans wrapped in `**double asterisks**`
    /// (markdown bold) so SwiftUI's markdown rendering highlights them. When
    /// `status == .looksGood`, this equals the input with no marks.
    public let originalMarked: String

    /// Short bullet labels (e.g. "missing article", "wrong tense"). Empty when
    /// `status == .looksGood`.
    public let mistakes: [String]

    public init(
        status: Status,
        native: String,
        originalMarked: String,
        mistakes: [String]
    ) {
        self.status = status
        self.native = native
        self.originalMarked = originalMarked
        self.mistakes = mistakes
    }
}
