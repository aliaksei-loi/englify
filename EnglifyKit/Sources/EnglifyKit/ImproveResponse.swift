import Foundation

/// Structured payload returned by the `claude` subprocess for an Improve call.
///
/// Decoded from JSON using `keyDecodingStrategy = .convertFromSnakeCase`, so the
/// wire keys are `status`, `native`, `original_marked`, `mistakes`.
///
/// Phase 3 adds two statuses on top of the Phase 2 set:
/// - `refusedRussian` — the input was detected as Russian and no `[ru]` prefix
///   was supplied. `native`, `originalMarked`, and `mistakes` are all empty;
///   callers must NOT attempt to copy in this state. The UI surfaces a hint
///   telling the user to add `[ru]` to translate.
/// - `translatedFromRu` — `[ru]` was supplied. Fields carry the same shape as
///   `rewritten` (English translation in `native`, Russian source echoed in
///   `originalMarked` with no marks, `mistakes` empty). UI tags the native
///   section as "Translated from Russian".
public struct ImproveResponse: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable {
        case looksGood = "looks_good"
        case rewritten
        case refusedRussian = "refused_russian"
        case translatedFromRu = "translated_from_ru"
    }

    /// Outcome of the rewrite.
    public let status: Status

    /// The native-sounding rewrite. For `status == .looksGood`, this is the
    /// user's input echoed back unchanged. For `status == .translatedFromRu`,
    /// this is the English translation. For `status == .refusedRussian`, this
    /// is the empty string and callers must not copy it.
    public let native: String

    /// The user's input with error spans wrapped in `**double asterisks**`
    /// (markdown bold) so SwiftUI's markdown rendering highlights them. When
    /// `status == .looksGood`, this equals the input with no marks. When
    /// `status == .translatedFromRu`, this echoes the Russian input unchanged
    /// (translation is not correction — nothing to mark). When
    /// `status == .refusedRussian`, this is the empty string.
    public let originalMarked: String

    /// Short bullet labels (e.g. "missing article", "wrong tense"). Empty when
    /// `status` is `.looksGood`, `.translatedFromRu`, or `.refusedRussian`.
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
