import Testing
@testable import EnglifyKit

/// Cheap regression guard for the system prompt.
///
/// The prompt is the single source of truth that drives model behavior; if
/// these substrings disappear, register matching, the bracket directives, or
/// the Russian-refusal path silently regress. These tests run Swift-side with
/// no live model call, so they catch accidental prompt edits in CI.
@Suite("SystemPrompt")
struct SystemPromptTests {
    @Test("v3 prompt names every bracket directive")
    func v3MentionsAllBracketDirectives() {
        let prompt = SystemPrompt.v3_register
        #expect(prompt.contains("[casual]"))
        #expect(prompt.contains("[formal]"))
        #expect(prompt.contains("[ru]"))
    }

    @Test("v3 prompt declares both new status values")
    func v3DeclaresNewStatuses() {
        let prompt = SystemPrompt.v3_register
        #expect(prompt.contains("refused_russian"))
        #expect(prompt.contains("translated_from_ru"))
    }

    @Test("v3 prompt keeps the Phase 2 status values intact")
    func v3KeepsExistingStatuses() {
        let prompt = SystemPrompt.v3_register
        #expect(prompt.contains("rewritten"))
        #expect(prompt.contains("looks_good"))
    }

    @Test("v3 prompt instructs the model to consume the bracket directive")
    func v3SaysConsumeBracket() {
        let prompt = SystemPrompt.v3_register
        // The model must not echo `[casual]` / `[formal]` / `[ru]` in any
        // output field — the prompt uses the word "CONSUME" to make that
        // visually unmissable.
        #expect(prompt.contains("CONSUME"))
    }

    @Test("v3 prompt names Cyrillic detection as the refusal trigger")
    func v3MentionsCyrillicDetection() {
        let prompt = SystemPrompt.v3_register
        #expect(prompt.contains("Cyrillic"))
    }

    @Test("v3 prompt explicitly forbids a corporate-polish middle ground")
    func v3ForbidsCorporateMiddleGround() {
        let prompt = SystemPrompt.v3_register
        // ADR-0001 carry-forward: register matching must not slide into
        // generic corporate-AI tone.
        #expect(prompt.localizedCaseInsensitiveContains("corporate"))
    }

    @Test("v3 prompt keeps the ADR-0001 faithfulness clause")
    func v3KeepsFaithfulnessRules() {
        let prompt = SystemPrompt.v3_register
        #expect(prompt.contains("Faithfulness rules"))
        // The hedging-words list is the load-bearing concrete example.
        #expect(prompt.contains("hedging"))
    }

    @Test("v2_structured alias forwards to the v3 prompt")
    func v2AliasMatchesV3() {
        // Existing call sites (e.g. `ClaudeSubprocess.systemPrompt`) read
        // `v2_structured`; the alias must keep them on the newest prompt.
        #expect(SystemPrompt.v2_structured == SystemPrompt.v3_register)
    }
}
