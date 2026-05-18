import Foundation

/// Decodes a raw `claude -p` stdout payload into an `ImproveResponse`.
///
/// The system prompt forbids surrounding prose and markdown code fences, but
/// real models drift; this decoder defensively strips leading/trailing
/// whitespace and an optional ```json … ``` fence before handing the bytes to
/// `JSONDecoder`. Anything past that point is treated as malformed and bubbled
/// up as a `DecodeError` carrying the original raw text for fallback display.
public enum ResponseDecoder {
    public struct DecodeError: Error, Equatable, Sendable {
        public let message: String
        public let rawText: String

        public init(message: String, rawText: String) {
            self.message = message
            self.rawText = rawText
        }
    }

    public static func decode(_ raw: String) -> Result<ImproveResponse, DecodeError> {
        let cleaned = stripFencesAndWhitespace(raw)
        guard let data = cleaned.data(using: .utf8) else {
            return .failure(DecodeError(message: "Could not encode response as UTF-8.", rawText: raw))
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            let response = try decoder.decode(ImproveResponse.self, from: data)
            return .success(response)
        } catch {
            return .failure(DecodeError(message: String(describing: error), rawText: raw))
        }
    }

    /// Strips leading/trailing whitespace and an optional ```json``` (or plain
    /// ``` ``` ```) fence wrapping the JSON body. Returns the input unchanged
    /// when no fence is present.
    static func stripFencesAndWhitespace(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("```") else { return text }

        // Drop the opening fence line (``` or ```json or ```JSON etc.).
        if let newlineIndex = text.firstIndex(where: { $0 == "\n" }) {
            text = String(text[text.index(after: newlineIndex)...])
        } else {
            // No newline after the fence — nothing to recover.
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Drop a trailing closing fence if present.
        if let range = text.range(of: "```", options: .backwards) {
            text = String(text[..<range.lowerBound])
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
