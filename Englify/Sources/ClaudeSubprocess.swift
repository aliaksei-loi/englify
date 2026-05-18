import Foundation

/// Spawns the `claude` CLI in headless print mode.
///
/// Phase 1: single non-streaming response, plain-text output, fresh session
/// per call. Stderr is captured but no specific error UX is wired yet.
enum ClaudeSubprocess {
    static let defaultModel = "claude-sonnet-4-6"

    static let systemPrompt = """
    You rewrite the user's English to sound native. Preserve their meaning, confidence, and directness. \
    Fix grammar, articles, tense, agreement, idiom, and word choice. Do not hedge, do not soften, do not add corporate filler. \
    Return only the rewritten text — no preamble, no quotes, no explanation.
    """

    struct RunError: Error, CustomStringConvertible {
        let exitCode: Int32
        let stderr: String

        var description: String {
            "claude exited \(exitCode): \(stderr)"
        }
    }

    /// Run `claude -p` with the supplied user text on stdin. Returns the
    /// trimmed stdout body. Throws `RunError` on non-zero exit.
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
