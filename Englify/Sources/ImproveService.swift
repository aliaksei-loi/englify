import Foundation
import Observation
import EnglifyKit

/// Owns the input text and the result of the most recent improve call.
///
/// Phase 2 decodes the model's JSON payload into an `ImproveResponse`. When
/// decoding fails the raw stdout is surfaced through `.readyRaw` so the UI can
/// show it with a parse-error notice instead of crashing.
@MainActor
@Observable
final class ImproveService {
    enum Status: Equatable {
        case idle
        case running
        case ready(ImproveResponse)
        case readyRaw(rawText: String, decodeError: String)
        case failed(String)
    }

    var input: String = ""
    private(set) var status: Status = .idle

    /// Text that the Copy button should put on the clipboard for the current
    /// status. `nil` when there is nothing to copy.
    var copyText: String? {
        switch status {
        case .ready(let response):
            switch response.status {
            case .rewritten, .looksGood, .translatedFromRu:
                // `native` is what we copy in all three cases — the prompt
                // guarantees `looks_good` echoes the input as `native`, and
                // `translated_from_ru` puts the English translation there.
                return response.native
            case .refusedRussian:
                // Nothing to copy — the UI shows a hint card instead.
                return nil
            }
        case .readyRaw(let rawText, _):
            return rawText
        case .idle, .running, .failed:
            return nil
        }
    }

    var isRunning: Bool {
        if case .running = status { return true }
        return false
    }

    func reset() {
        input = ""
        status = .idle
    }

    func improve() {
        let text = input
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !isRunning else { return }
        status = .running

        Task { [weak self] in
            do {
                let raw = try await ClaudeSubprocess.run(input: text)
                let decoded = ResponseDecoder.decode(raw)
                await MainActor.run {
                    guard let self else { return }
                    switch decoded {
                    case .success(let response):
                        self.status = .ready(response)
                    case .failure(let error):
                        self.status = .readyRaw(rawText: error.rawText, decodeError: error.message)
                    }
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.status = .failed("Error")
                }
            }
        }
    }
}
