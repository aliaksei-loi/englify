import Foundation
import Observation
import EnglifyKit

/// Owns the input text and the result of the most recent improve call.
///
/// Phase 4 swaps `.failed(String)` for `.failed(FailureMode)` so the view can
/// switch on a typed failure and render per-mode actionable cards.
@MainActor
@Observable
final class ImproveService {
    enum Status: Equatable {
        case idle
        case running
        case ready(ImproveResponse)
        case readyRaw(rawText: String, decodeError: String)
        case failed(FailureMode)
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
            let result = await ClaudeSubprocess.run(input: text)
            await MainActor.run {
                guard let self else { return }
                switch result {
                case .success(let raw):
                    let decoded = ResponseDecoder.decode(raw)
                    switch decoded {
                    case .success(let response):
                        self.status = .ready(response)
                    case .failure(let error):
                        self.status = .readyRaw(rawText: error.rawText, decodeError: error.message)
                    }
                case .failure(let mode):
                    self.status = .failed(mode)
                }
            }
        }
    }
}
