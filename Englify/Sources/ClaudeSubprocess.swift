import Foundation
import EnglifyKit

/// Spawns the `claude` CLI in headless print mode.
///
/// Phase 4 adds:
/// - `cliMissing` detection via `which claude` before spawning the real run.
/// - 30-second wall-clock timeout (`process.terminate()` on expiry).
/// - Stderr capture surfaced through `FailureClassifier` so the UI can show
///   per-mode actionable cards (CLI not found / not authenticated / offline /
///   timeout / unknown).
///
/// Returns `Result<String, FailureMode>` — success is the trimmed stdout body
/// (still expected to be JSON per `SystemPrompt.v2_structured`). Decoding of
/// that JSON happens in `EnglifyKit`'s `ResponseDecoder`.
enum ClaudeSubprocess {
    static let defaultModel = "claude-sonnet-4-6"
    static let systemPrompt = SystemPrompt.v2_structured
    static let timeoutSeconds: TimeInterval = 30

    /// Run `claude -p` with the supplied user text on stdin. Returns
    /// `.success(stdout)` on exit code 0, otherwise `.failure(FailureMode)`
    /// with the classified reason.
    static func run(input: String, model: String = defaultModel) async -> Result<String, FailureMode> {
        await Task.detached(priority: .userInitiated) {
            runBlocking(input: input, model: model)
        }.value
    }

    private static func runBlocking(input: String, model: String) -> Result<String, FailureMode> {
        // Step 1: detect missing CLI up front. `which` exits non-zero when
        // the binary isn't on PATH; treat any non-zero as missing.
        if !cliExists() {
            return .failure(.cliNotFound)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "claude", "-p",
            "--session-id", UUID().uuidString.lowercased(),
            "--model", model,
            "--output-format", "text",
            "--system-prompt", systemPrompt,
        ]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return .failure(.unknown("failed to launch claude: \(error.localizedDescription)"))
        }

        // Wall-clock timeout: detached task terminates the process after 30s.
        // Shared flag captures whether the kill came from the timer (so the
        // classifier sees `timedOut: true`).
        let timedOutFlag = TimedOutFlag()
        let timeoutTask = Task.detached { [process, timedOutFlag] in
            try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            if process.isRunning {
                timedOutFlag.set()
                process.terminate()
            }
        }

        if let data = input.data(using: .utf8) {
            try? stdinPipe.fileHandleForWriting.write(contentsOf: data)
        }
        try? stdinPipe.fileHandleForWriting.close()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeoutTask.cancel()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let mode = FailureClassifier.classify(
                exitCode: process.terminationStatus,
                stderr: stderr,
                cliMissing: false,
                timedOut: timedOutFlag.get()
            )
            return .failure(mode)
        }

        return .success(stdout.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// `which claude` — returns true only on exit code 0.
    private static func cliExists() -> Bool {
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        which.arguments = ["which", "claude"]
        which.standardOutput = Pipe()
        which.standardError = Pipe()
        do {
            try which.run()
        } catch {
            return false
        }
        which.waitUntilExit()
        return which.terminationStatus == 0
    }
}

/// Tiny thread-safe Bool wrapper so the timeout task and the main blocking
/// thread can agree on whether termination was forced. `NSLock` is enough —
/// no contention beyond two threads.
private final class TimedOutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() {
        lock.lock(); defer { lock.unlock() }
        value = true
    }
    func get() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}
