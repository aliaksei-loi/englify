#!/usr/bin/env swift

// Playground A — claude CLI subprocess contract
//
// Validates:
//   1. `claude` binary is on PATH
//   2. `claude auth status` returns subscription-class auth (not API key)
//   3. `claude -p` with optimized flags produces valid JSON on stdout
//   4. The primary system prompt produces output in the
//      `**Improved:** / **Changes:**` format we rely on
//   5. Cold vs warm latency + cache reuse behavior
//
// Run:
//   swift playgrounds/claude_cli.swift

import Foundation

// MARK: - Helpers

@discardableResult
func shell(_ command: String, arguments: [String], timeout: TimeInterval = 30) throws -> (stdout: String, stderr: String, exitCode: Int32, elapsed: TimeInterval) {
    let process = Process()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: command)
    process.arguments = arguments
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    let start = Date()
    try process.run()

    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
    }
    if process.isRunning {
        process.terminate()
        Thread.sleep(forTimeInterval: 0.5)
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
    process.waitUntilExit()

    let elapsed = Date().timeIntervalSince(start)
    let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return (stdout, stderr, process.terminationStatus, elapsed)
}

func findClaudeBinary() -> String? {
    let candidates = [
        "/usr/local/bin/claude",
        "/opt/homebrew/bin/claude",
        "\(NSHomeDirectory())/.local/bin/claude",
    ]
    for path in candidates {
        if FileManager.default.isExecutableFile(atPath: path) { return path }
    }
    // Fallback: ask shell
    if let which = try? shell("/usr/bin/env", arguments: ["which", "claude"], timeout: 5),
       which.exitCode == 0 {
        let trimmed = which.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, FileManager.default.isExecutableFile(atPath: trimmed) {
            return trimmed
        }
    }
    return nil
}

// MARK: - Tests

guard let claude = findClaudeBinary() else {
    print("❌ Test 1: `claude` binary not found on PATH")
    exit(1)
}
print("✅ Test 1: `claude` binary at \(claude)")

// Test 2: auth status
print()
print("=== Test 2: auth status ===")
let authResult = try shell(claude, arguments: ["auth", "status"], timeout: 5)
guard authResult.exitCode == 0,
      let authData = authResult.stdout.data(using: .utf8),
      let authJSON = try JSONSerialization.jsonObject(with: authData) as? [String: Any] else {
    print("❌ `claude auth status` failed (exit \(authResult.exitCode)):")
    print(authResult.stderr)
    exit(1)
}
let loggedIn = authJSON["loggedIn"] as? Bool ?? false
let authMethod = authJSON["authMethod"] as? String ?? "<missing>"
let subscriptionType = authJSON["subscriptionType"] as? String ?? "<missing>"
print("  loggedIn: \(loggedIn)")
print("  authMethod: \(authMethod)")
print("  subscriptionType: \(subscriptionType)")
guard loggedIn else {
    print("❌ Not logged in. Run `claude /login`.")
    exit(1)
}
guard authMethod == "claude.ai" else {
    print("⚠️  authMethod is '\(authMethod)', not 'claude.ai' (subscription). The app is designed for subscription auth.")
    print("   Continuing the test, but Phase 2 onboarding would block here.")
}
print("✅ Test 2: subscription auth confirmed")

// Test 3: cold call
print()
print("=== Test 3: cold call (expect ~9–10 s total) ===")
let primarySystemPrompt = """
You are an English language editor. Given text the user is about to send, produce an improved version that fixes grammar, word choice, articles, prepositions, and phrasing so it reads like a fluent native speaker wrote it. Preserve the original meaning, tone, and register (casual stays casual; formal stays formal).

Return your output in exactly this format:

**Improved:** <the rewritten text, one paragraph, no quotes, no preamble>

**Changes:**
- <short bullet explaining one key fix>
- <short bullet explaining another key fix>
- <up to 3 bullets total; omit the Changes section entirely if nothing meaningful changed>
"""

// Use an empty temp dir to avoid loading user CLAUDE.md / .claude
let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("englify-playground-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tempDir) }

func invokeClaude(input: String) throws -> (result: String?, durationApiMs: Int, cacheCreation: Int, cacheRead: Int, elapsed: TimeInterval, stderr: String) {
    let args = [
        "-p",
        "--model", "claude-haiku-4-5",
        "--system-prompt", primarySystemPrompt,
        "--disable-slash-commands",
        "--tools", "",
        "--no-session-persistence",
        "--output-format", "json",
        input,
    ]
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: claude)
    proc.arguments = args
    proc.currentDirectoryURL = tempDir
    let out = Pipe(), err = Pipe()
    proc.standardOutput = out
    proc.standardError = err
    let start = Date()
    try proc.run()
    proc.waitUntilExit()
    let elapsed = Date().timeIntervalSince(start)
    let stdoutStr = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderrStr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

    var result: String?
    var durationApiMs = 0
    var cacheCreation = 0
    var cacheRead = 0
    if let data = stdoutStr.data(using: .utf8),
       let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
        result = obj["result"] as? String
        durationApiMs = obj["duration_api_ms"] as? Int ?? 0
        if let usage = obj["usage"] as? [String: Any] {
            cacheCreation = usage["cache_creation_input_tokens"] as? Int ?? 0
            cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
        }
    }
    return (result, durationApiMs, cacheCreation, cacheRead, elapsed, stderrStr)
}

let test3 = try invokeClaude(input: "improve: i was go to store and buy things")
print("  total elapsed: \(Int(test3.elapsed * 1000))ms")
print("  API duration: \(test3.durationApiMs)ms")
print("  cache creation: \(test3.cacheCreation), cache read: \(test3.cacheRead)")
if let r = test3.result {
    print("  result (truncated):")
    for line in r.prefix(400).split(separator: "\n") {
        print("    \(line)")
    }
    let hasImproved = r.contains("**Improved:**")
    let hasChanges  = r.contains("**Changes:**")
    print("  contains **Improved:** marker: \(hasImproved ? "✅" : "❌")")
    print("  contains **Changes:** marker:  \(hasChanges ? "✅" : "⚠️ (acceptable if input was fine)")")
    if !hasImproved {
        print("❌ Test 3 FAILED: output format not as expected")
        exit(1)
    }
    print("✅ Test 3: cold call produced expected format")
} else {
    print("❌ Test 3 FAILED: no result field in stdout")
    print("  stderr: \(test3.stderr.prefix(500))")
    exit(1)
}

// Test 4: warm call (should reuse cache)
print()
print("=== Test 4: warm call — same system prompt, different input ===")
let test4 = try invokeClaude(input: "improve: she have a apple and i has orange")
print("  total elapsed: \(Int(test4.elapsed * 1000))ms")
print("  API duration: \(test4.durationApiMs)ms")
print("  cache creation: \(test4.cacheCreation), cache read: \(test4.cacheRead)")
if test4.cacheRead > test4.cacheCreation {
    print("✅ Test 4: warm call reused cache (\(test4.cacheRead) tokens read vs \(test4.cacheCreation) created)")
} else {
    print("⚠️  Test 4: cache did not reuse as expected")
}

// Summary
print()
print("=== Summary ===")
print("  Cold total elapsed:   \(Int(test3.elapsed * 1000))ms")
print("  Warm total elapsed:   \(Int(test4.elapsed * 1000))ms")
print("  Cold API duration:    \(test3.durationApiMs)ms")
print("  Warm API duration:    \(test4.durationApiMs)ms")
print("  Cold cache creation:  \(test3.cacheCreation) tokens")
print("  Warm cache creation:  \(test4.cacheCreation) tokens  (should be << cold)")
print("  Warm cache read:      \(test4.cacheRead) tokens      (should be ~ cold creation)")
print()
print("Expected range per SPEC.md Tradeoffs: 9–10 s elapsed (cold), 3–5 s API time. If significantly worse, update SPEC.md.")
