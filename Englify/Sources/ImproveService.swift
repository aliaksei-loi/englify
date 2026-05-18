import Foundation
import Observation

/// Owns the input text and the result of the most recent improve call.
///
/// Phase 1 is plain text in, plain text out. No structured decoding yet.
@MainActor
@Observable
final class ImproveService {
    enum Status: Equatable {
        case idle
        case running
        case ready(String)
        case failed(String)
    }

    var input: String = ""
    private(set) var status: Status = .idle

    var resultText: String? {
        if case .ready(let text) = status { return text }
        return nil
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
                let output = try await ClaudeSubprocess.run(input: text)
                await MainActor.run {
                    guard let self else { return }
                    self.status = .ready(output)
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
