import Foundation
import EnglifyKit

/// Spawns the `claude` CLI in headless print mode.
///
/// Phase 2: prompt asks for JSON; transport stays plain-text stdout — the JSON
/// is just the content of that text. Decoding happens in `EnglifyKit`'s
/// `ResponseDecoder`. Fresh `--session-id` per call (no cross-call memory).
/// Stderr is captured but no specific error UX is wired yet.
enum ClaudeSubprocess {
    static let defaultModel = "claude-sonnet-4-6"

    static let systemPrompt = SystemPrompt.v2_structured

    struct RunError: Error, CustomStringConvertible {
        let exitCode: Int32
        let stderr: String

        var description: String {
            "claude exited \(exitCode): \(stderr)"
        }
    }

    /// Run `claude -p` with the supplied user text on stdin. Returns the
    /// trimmed stdout body (expected to be a JSON object — see
    /// `SystemPrompt.v2_structured`). Throws `RunError` on non-zero exit.
    static func run(input: String, model: String = defaultModel) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try runBlocking(input: input, model: model)
        }.value
    }

    private static func runBlocking(input: String, model: String) throws -> String {
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

        try process.run()

        // Write the user text and close stdin so claude can finish.
        if let data = input.data(using: .utf8) {
            try stdinPipe.fileHandleForWriting.write(contentsOf: data)
        }
        try stdinPipe.fileHandleForWriting.close()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw RunError(exitCode: process.terminationStatus, stderr: stderr)
        }

        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
