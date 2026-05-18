import Testing
@testable import EnglifyKit

@Suite("ResponseDecoder")
struct ResponseDecoderTests {
    @Test("decodes a well-formed rewritten response with mistakes")
    func decodesRewritten() throws {
        let json = """
        {
          "status": "rewritten",
          "native": "I went to the store yesterday.",
          "original_marked": "I **goed** to **store** yesterday.",
          "mistakes": ["wrong past tense", "missing article"]
        }
        """

        let result = ResponseDecoder.decode(json)
        let response = try unwrapSuccess(result)
        #expect(response.status == .rewritten)
        #expect(response.native == "I went to the store yesterday.")
        #expect(response.originalMarked == "I **goed** to **store** yesterday.")
        #expect(response.mistakes == ["wrong past tense", "missing article"])
    }

    @Test("decodes a looks_good response with empty mistakes")
    func decodesLooksGood() throws {
        let input = "I went to the store yesterday."
        let json = """
        {
          "status": "looks_good",
          "native": "\(input)",
          "original_marked": "\(input)",
          "mistakes": []
        }
        """

        let result = ResponseDecoder.decode(json)
        let response = try unwrapSuccess(result)
        #expect(response.status == .looksGood)
        #expect(response.native == input)
        #expect(response.originalMarked == input)
        #expect(response.mistakes.isEmpty)
    }

    @Test("tolerates surrounding whitespace and newlines")
    func decodesWithSurroundingWhitespace() throws {
        let json = """


          {
            "status": "rewritten",
            "native": "Hello.",
            "original_marked": "**hello**.",
            "mistakes": ["capitalisation"]
          }


        """

        let result = ResponseDecoder.decode(json)
        let response = try unwrapSuccess(result)
        #expect(response.status == .rewritten)
        #expect(response.native == "Hello.")
    }

    @Test("strips ```json fences when the model adds them anyway")
    func decodesWithJsonFences() throws {
        let json = """
        ```json
        {
          "status": "rewritten",
          "native": "Hello.",
          "original_marked": "**hello**.",
          "mistakes": ["capitalisation"]
        }
        ```
        """

        let result = ResponseDecoder.decode(json)
        let response = try unwrapSuccess(result)
        #expect(response.status == .rewritten)
        #expect(response.native == "Hello.")
        #expect(response.mistakes == ["capitalisation"])
    }

    @Test("strips bare ``` fences without a language tag")
    func decodesWithBareFences() throws {
        let json = """
        ```
        {
          "status": "looks_good",
          "native": "Fine.",
          "original_marked": "Fine.",
          "mistakes": []
        }
        ```
        """

        let result = ResponseDecoder.decode(json)
        let response = try unwrapSuccess(result)
        #expect(response.status == .looksGood)
    }

    @Test("malformed JSON returns a failure carrying the raw text")
    func malformedJsonFails() {
        let raw = "this is not json {{{"
        let result = ResponseDecoder.decode(raw)
        switch result {
        case .success:
            Issue.record("Expected failure for malformed JSON.")
        case .failure(let error):
            #expect(error.rawText == raw)
            #expect(!error.message.isEmpty)
        }
    }

    @Test("missing required field returns a failure (no silent defaults)")
    func missingFieldFails() {
        // `mistakes` is required; this payload omits it.
        let json = """
        {
          "status": "rewritten",
          "native": "Hi.",
          "original_marked": "**hi**."
        }
        """
        let result = ResponseDecoder.decode(json)
        switch result {
        case .success:
            Issue.record("Expected failure when a required field is missing.")
        case .failure(let error):
            #expect(error.rawText == json)
        }
    }

    @Test("decodes a refused_russian response with all text fields empty")
    func decodesRefusedRussian() throws {
        // The model refuses to act on Russian input without the `[ru]` prefix.
        // All three text fields are empty by contract; the UI surfaces the
        // hint instead of attempting to copy.
        let json = """
        {
          "status": "refused_russian",
          "native": "",
          "original_marked": "",
          "mistakes": []
        }
        """

        let result = ResponseDecoder.decode(json)
        let response = try unwrapSuccess(result)
        #expect(response.status == .refusedRussian)
        #expect(response.native.isEmpty)
        #expect(response.originalMarked.isEmpty)
        #expect(response.mistakes.isEmpty)
    }

    @Test("decodes a translated_from_ru response with English native and Russian original")
    func decodesTranslatedFromRu() throws {
        // `[ru]` escape hatch: native is the English translation, original_marked
        // echoes the Russian source verbatim (no marks — translation is not
        // correction), mistakes is empty.
        let json = """
        {
          "status": "translated_from_ru",
          "native": "I want to say that this is important.",
          "original_marked": "я хочу сказать что это важно",
          "mistakes": []
        }
        """

        let result = ResponseDecoder.decode(json)
        let response = try unwrapSuccess(result)
        #expect(response.status == .translatedFromRu)
        #expect(response.native == "I want to say that this is important.")
        #expect(response.originalMarked == "я хочу сказать что это важно")
        #expect(response.mistakes.isEmpty)
    }

    @Test("unknown status value returns a failure")
    func unknownStatusFails() {
        let json = """
        {
          "status": "something_else",
          "native": "Hi.",
          "original_marked": "Hi.",
          "mistakes": []
        }
        """
        let result = ResponseDecoder.decode(json)
        switch result {
        case .success:
            Issue.record("Expected failure for unknown status value.")
        case .failure(let error):
            #expect(error.rawText == json)
        }
    }

    // MARK: - Helpers

    private func unwrapSuccess(_ result: Result<ImproveResponse, ResponseDecoder.DecodeError>) throws -> ImproveResponse {
        switch result {
        case .success(let response):
            return response
        case .failure(let error):
            Issue.record("Decode failed: \(error.message)\nRaw: \(error.rawText)")
            throw error
        }
    }
}
