#!/usr/bin/env swift

// Playground A — OpenAI SSE streaming via URLSession.bytes
//
// Validates:
//   1. POST /v1/chat/completions with stream:true
//   2. SSE parsing emits tokens as they arrive
//   3. [DONE] terminates cleanly
//   4. Task cancellation stops emission mid-stream
//
// Run:
//   OPENAI_API_KEY=sk-... swift playgrounds/streaming.swift

import Foundation

guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] else {
    FileHandle.standardError.write(Data("OPENAI_API_KEY not set\n".utf8))
    exit(1)
}

struct ChatRequest: Encodable {
    let model: String
    let stream: Bool
    let temperature: Double
    let messages: [Message]
    struct Message: Encodable { let role: String; let content: String }
}

struct Delta: Decodable {
    let choices: [Choice]
    struct Choice: Decodable {
        let delta: DeltaContent
        struct DeltaContent: Decodable { let content: String? }
    }
}

enum StreamOutcome {
    case done(tokens: Int, ms: Int)
    case cancelled(tokens: Int, ms: Int)
    case httpError(Int)
}

func stream(prompt: String, cancelAfterMs: Int? = nil) async throws -> StreamOutcome {
    var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
    req.httpMethod = "POST"
    req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONEncoder().encode(ChatRequest(
        model: "gpt-4o-mini",
        stream: true,
        temperature: 0.3,
        messages: [.init(role: "user", content: prompt)]
    ))

    let start = Date()
    let (bytes, response) = try await URLSession.shared.bytes(for: req)

    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        return .httpError((response as? HTTPURLResponse)?.statusCode ?? -1)
    }

    let decoder = JSONDecoder()
    var tokenCount = 0

    for try await line in bytes.lines {
        if let cancelMs = cancelAfterMs,
           Date().timeIntervalSince(start) * 1000 > Double(cancelMs) {
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            return .cancelled(tokens: tokenCount, ms: ms)
        }

        guard line.hasPrefix("data: ") else { continue }
        let payload = String(line.dropFirst(6))
        if payload == "[DONE]" {
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            return .done(tokens: tokenCount, ms: ms)
        }
        if let data = payload.data(using: .utf8),
           let delta = try? decoder.decode(Delta.self, from: data),
           let token = delta.choices.first?.delta.content {
            print(token, terminator: "")
            fflush(stdout)
            tokenCount += 1
        }
    }

    let ms = Int(Date().timeIntervalSince(start) * 1000)
    return .done(tokens: tokenCount, ms: ms)
}

print("=== Test 1: normal stream to completion ===")
switch try await stream(prompt: "Improve this English and return only the improved sentence, no preamble: 'i has a book that was writing by good author'") {
case .done(let t, let ms):
    print("\n✅ DONE — \(t) tokens in \(ms)ms")
case .cancelled(let t, let ms):
    print("\n⚠️  Unexpectedly cancelled — \(t) tokens in \(ms)ms")
case .httpError(let code):
    print("\n❌ HTTP \(code)")
}

print("\n=== Test 2: cancel mid-stream at ~500ms ===")
switch try await stream(
    prompt: "Write a 400-word explanation of how photosynthesis works, in careful detail.",
    cancelAfterMs: 500
) {
case .done(let t, let ms):
    print("\n⚠️  Completed before cancel — \(t) tokens in \(ms)ms (try a longer prompt)")
case .cancelled(let t, let ms):
    print("\n✅ CANCELLED — \(t) tokens in \(ms)ms")
case .httpError(let code):
    print("\n❌ HTTP \(code)")
}

print("\n=== Test 3: bad key surfaces as HTTP 401 ===")
// Temporarily override the key for this test
setenv("OPENAI_API_KEY", "sk-invalid-key-for-testing", 1)
// Re-reading env won't help — the global `apiKey` was captured at startup.
// Instead, just make a raw request here:
do {
    var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
    req.httpMethod = "POST"
    req.setValue("Bearer sk-invalid-key-for-testing", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONEncoder().encode(ChatRequest(
        model: "gpt-4o-mini",
        stream: true,
        temperature: 0.3,
        messages: [.init(role: "user", content: "hi")]
    ))
    let (_, response) = try await URLSession.shared.bytes(for: req)
    if let http = response as? HTTPURLResponse {
        print("HTTP \(http.statusCode) — \(http.statusCode == 401 ? "✅ 401 as expected" : "⚠️ unexpected")")
    }
} catch {
    print("Error: \(error)")
}
