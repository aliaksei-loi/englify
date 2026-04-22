# Plan: Englify

> Source PRD: [aliaksei-loi/englify#1](https://github.com/aliaksei-loi/englify/issues/1)
> Source spec: [SPEC.md](../SPEC.md)
> Backend pivot: 2026-04-22 — switched from OpenAI API to `claude` CLI subprocess (Claude subscription). See SPEC.md Tradeoffs section for measured latency impact.

## Architectural decisions

These are locked for the full implementation and apply across every phase below.

- **Platform**: native macOS, deployment target macOS 14 (Sonoma). Swift + SwiftUI. Menubar-only (`LSUIElement = true`), no Dock icon.
- **Process model**: single app target. No helper processes, no backend. Runs on login via `SMAppService.loginItem`.
- **LLM backend**: shell out to the `claude` CLI (from Claude Code). Fresh subprocess per rewrite (spawn-per-call). Model `claude-haiku-4-5`. Authenticated via the user's existing Claude Code subscription — no API key handling anywhere in the app.
- **Latency budget**: 15 s per rewrite. No streaming UI — results appear all at once when the subprocess exits (Claude CLI buffers its full response). Popup shows a spinner + elapsed-time counter during the wait.
- **Subprocess contract** (see SPEC.md for full details): `claude -p --model claude-haiku-4-5 --system-prompt <…> --disable-slash-commands --tools "" --no-session-persistence --output-format json <userInput>`. Working directory is a temp dir empty of `CLAUDE.md`. Timeout 20 s; on timeout, SIGTERM then SIGKILL after 500 ms.
- **Runtime dependency**: `claude` binary must be on PATH and `claude auth status` must report `loggedIn: true` with a subscription-class `authMethod` (`claude.ai`). The app checks both at first launch and on every cold open; if either fails, it surfaces a clear error and does not attempt workarounds.
- **Runtime dep (Swift)**: `KeyboardShortcuts` (sindresorhus). Only third-party dependency. All other functionality uses system frameworks.
- **Module decomposition**: deep modules `ClaudeSubprocess`, `ResponseParser`, `PromptFactory`, `ErrorClassifier`, `ClaudeAuthChecker`. Deep-ish modules `PasteController`, `SelectionReader`. Shallow UI/glue modules `HotkeyCoordinator`, `MenubarController`, `PopupWindow`, `PopupView`, `OnboardingView`, `PreferencesView`, `LoginItemManager`, `AppCoordinator`. (Renamed from prior OpenAI-oriented shape: `OpenAIStream` → `ClaudeSubprocess`; `StreamParser` → `ResponseParser`; `KeychainStore` replaced by `ClaudeAuthChecker` since there is no secret to store.)
- **Testing posture**: automated unit/integration tests for the five deep modules. Manual test checklist (`TESTING.md`) for `PasteController` and `SelectionReader`. Integration test for `ClaudeSubprocess` uses a fake `claude` binary (tiny shell script on PATH during tests) that emits canned JSON.
- **Persistence**: none. No rewrite history on disk. The only on-disk state is the user's hotkey preference (via `KeyboardShortcuts` in `UserDefaults`) and Login-Item registration.
- **UI conventions**: popup is a borderless `NSPanel` with `.nonactivatingPanel` + `.hudWindow` styleMask, centered on the active screen. Default hotkey ⌥⇧E, rebindable. Accept shortcuts Enter / ⌘1 / ⌘2 / ⌘3. Cancel shortcut Escape.
- **Distribution**: ad-hoc signed `.app`, dragged into `/Applications`. No notarization, no App Store (sandboxing would break Accessibility), no Sparkle in v1.
- **Permissions**: Accessibility permission required for selection reading and for posting `CGEvent` paste events. Deferred to first use that needs it (not demanded at first launch). Empty-textarea flow works without it.
- **Input cap**: ~8k tokens, checked client-side before spawning the subprocess via `text.count / 4` heuristic.

---

## Phase 1: De-risking playgrounds (throwaway)

**User stories**: 5 (validation only), 27, 28 (validation only)

### What to build

Two standalone Swift playground files validate the two riskiest assumptions before any app code is written. They do not ship. Output of this phase is a go/no-go decision plus notes captured back in `SPEC.md` if any assumption is proven wrong.

- **Playground A — `claude` subprocess contract** (`playgrounds/claude_cli.swift`): invoke `claude auth status`, parse JSON, assert `loggedIn` + subscription auth. Then invoke `claude -p` with the optimized flags from SPEC.md, measure cold-call latency and warm-call latency (cache reuse), parse the JSON `result` field, verify the prompt produces the `**Improved:** / **Changes:**` output format we rely on.
- **Playground B — clipboard-swap paste** (`playgrounds/paste.swift`, already written): save clipboard, overwrite, activate target app, post `CGEvent` ⌘V, restore. Run against Slack (decisive), Mail, Notes, VS Code, Safari text field, Terminal, Messages.

### Acceptance criteria

- [ ] Playground A confirms `claude auth status` returns subscription-class auth (not API key)
- [ ] Playground A runs `claude -p` end-to-end and parses `result` JSON field
- [ ] Playground A produces `**Improved:** / **Changes:**`-formatted output for a test sentence
- [ ] Playground A records cold-call latency (~9–10 s expected) and warm-call latency (cache reuse, expected similar API time but smaller `cache_creation_input_tokens`)
- [ ] Playground B pastes successfully into Slack (Electron) and restores the original clipboard
- [ ] Playground B results across the target app list are documented in `playgrounds/RESULTS.md`
- [ ] Go/no-go decision recorded: if Slack paste is broken, project is rescoped before Phase 2 starts

---

## Phase 2: First tracer — type, rewrite, copy

**User stories**: 2, 3 (rewritten — see below), 4 (not applicable), 15, 16, 29, 30

### What to build

A menubar-only macOS app that can rewrite English text end-to-end via the `claude` subprocess. No selection capture and no auto-paste in this phase — just the core rewrite path.

- Menubar icon appears on launch; clicking shows a menu with "Rewrite (⌥⇧E)", "Preferences...", "Quit".
- **First-launch onboarding is about Claude Code, not an API key.** A window checks: (a) is `claude` on PATH? (b) does `claude auth status` return `loggedIn: true` with `authMethod: "claude.ai"`? Both pass → save nothing (no secret to store), close the window, proceed. Any fail → show specific remediation (install link to claude.ai/install, or "run `claude /login` in a terminal").
- **Story 3 replacement**: "As a first-time user, I want the app to verify my Claude Code installation and subscription login before launching, so I know the app will work before I try my first rewrite."
- **Story 4 (Keychain key)** is not applicable to this backend — dropped from the implemented set.
- Preferences window exposes: hotkey rebinder (via `KeyboardShortcuts` SwiftUI component), a read-only display of detected Claude auth status (with a "Re-check" button).
- Pressing the hotkey opens the popup (`NSPanel`, centered on active screen) with an empty textarea focused. User types or pastes text, presses Return. A spinner with elapsed-time counter appears while the `claude` subprocess runs. When the subprocess exits successfully, the full improved text is rendered. A Copy button (or ⌘C) puts it on the clipboard.
- Input longer than ~8k tokens is blocked with an inline "Text too long" message before the subprocess is spawned.

### Acceptance criteria

- [ ] App runs from `/Applications` or Xcode, appears in the menubar, is not in the Dock
- [ ] First launch blocks on Claude Code detection; if `claude` is missing or not subscription-authed, the user sees specific remediation
- [ ] If auth is good, the app proceeds without asking for an API key anywhere
- [ ] Hotkey ⌥⇧E opens the popup; the popup appears centered on the active screen; Escape closes it
- [ ] The user can rebind the hotkey in Preferences and the new binding takes effect immediately
- [ ] Typing a test sentence + Return spawns a `claude` subprocess, shows a spinner during the wait, and renders the improved text when complete (typical 3–10 s)
- [ ] A spinner shows elapsed seconds so the user can see progress even when waiting >5 s
- [ ] Copy button / ⌘C puts the improved text on the clipboard
- [ ] Oversized input (heuristic >8k tokens) is blocked pre-spawn with a visible message
- [ ] Quit from the menubar fully exits the process (and kills any in-flight subprocess)

---

## Phase 3: Changes section + parsed output

**User stories**: 8, 13, 26

### What to build

Parse the full subprocess output into the `**Improved:**` / `**Changes:**` sections and render them separately. Streaming (story 7) is **not** implemented — the Claude CLI does not stream output usefully, so every rewrite renders all-at-once when the subprocess exits. Story 7 is dropped from the implemented set.

- `ResponseParser` splits the `result` string (from the subprocess JSON) into `improved` text and a list of `changes` bullets. Handles: well-formed output, Changes-omitted output, unexpected formats (fall back to "treat whole thing as improved text, no changes section").
- Popup renders the improved text prominently; below it, a small muted "Changes" label and the bullets (when present). No streaming UI — both sections appear together.
- Escape during the in-flight subprocess sends SIGTERM to the `claude` process and closes the popup within ~500 ms.

### Acceptance criteria

- [ ] `ResponseParser` has unit tests covering well-formed Improved+Changes, Improved-only (no Changes section), and malformed outputs (fallback path)
- [ ] Popup shows the Changes section below the Improved text when the model includes it
- [ ] When the model omits Changes, no empty section renders (no stray label)
- [ ] Escape during an in-flight subprocess cancels it (process no longer visible in `ps`) and closes the popup
- [ ] `ClaudeSubprocess` has an integration test using a fake `claude` binary on PATH that emits canned JSON (deterministic latency + output)

---

## Phase 4: Tone variants

**User stories**: 9, 10, 11, 12 (rewritten — see below), 14

### What to build

Add on-demand tone variants to the popup.

- Three chip buttons appear below the result area: Formal, Casual, Shorter.
- Chips are disabled while the primary subprocess is in flight. Once the primary result renders, chips become enabled.
- Clicking a chip (or pressing ⌘1 / ⌘2 / ⌘3) cancels any in-flight variant subprocess (SIGTERM), spawns a fresh `claude` invocation with the matching variant system prompt, shows the spinner, and replaces the main result area with the variant output on completion. Variant calls return only the rewritten text — no Changes section is rendered for variants.
- **Story 12 (on-demand variants) is honored but the framing shifts**: not because pre-generation wastes tokens (it might actually be faster with Claude since we'd get all variants in one inference), but because each variant is a separate user-driven click with its own spinner wait. Each click = one subprocess spawn.
- Pressing Enter accepts the currently displayed text (primary or active variant) by copying it to the clipboard and closing the popup. Auto-paste is still Phase 5.
- `PromptFactory` gains variant system prompts for `formal`, `casual`, `shorter` styles.

### Acceptance criteria

- [ ] Three chips visible below the result; disabled during primary subprocess, enabled after
- [ ] ⌘1 / ⌘2 / ⌘3 trigger the matching chip
- [ ] Clicking a chip replaces the main result area with a fresh variant output after the subprocess completes (typical 3–10 s); spinner visible during the wait
- [ ] Rapidly clicking a second chip SIGTERMs the first variant's subprocess before spawning the second
- [ ] Changes section is hidden during and after a variant is displayed
- [ ] Enter accepts whichever text is currently displayed (primary or active variant) to the clipboard and closes the popup
- [ ] `PromptFactory` has unit tests covering all four styles (primary, formal, casual, shorter)

---

## Phase 5: Selection reading + auto-paste

**User stories**: 1, 5, 17, 18, 27, 28

### What to build

Wire up the magic flow: select text, hit hotkey, accept, paste replaces selection in source app.

- `SelectionReader` reads the selected text from the focused `AXUIElement` at hotkey-press time. Also captures the frontmost app's PID for later focus restoration.
- First time selection reading is attempted and Accessibility permission is not granted: a permission explainer appears in the popup with a "Grant" button that deep-links to System Settings → Privacy → Accessibility. The existing empty-textarea fallback flow still works without the permission.
- At runtime, the app detects revoked Accessibility permission (post-update or post-annual-reprompt on Sequoia+) and re-prompts cleanly on next selection-capture attempt.
- When a selection is present at hotkey time, the popup opens with the selected text pre-populated and the primary subprocess fires immediately.
- `PasteController` implements the accept flow: save current clipboard contents + `changeCount`, write accepted text to clipboard, re-activate the saved PID (`NSRunningApplication.activate`), post `CGEvent` for ⌘V, wait 100 ms, restore original clipboard.
- Enter / ⌘1 / ⌘2 / ⌘3 in the popup now call into `PasteController` instead of just copying.

### Acceptance criteria

- [ ] Selecting text in any app and pressing ⌥⇧E pre-populates the popup with that text and starts the primary subprocess immediately
- [ ] Accepting a rewrite pastes it back into the source app, replacing the original selection
- [ ] The user's original clipboard contents are restored within 200 ms of paste completion
- [ ] Focus returns to the source app for the paste (not the popup, not another app)
- [ ] First-time Accessibility prompt appears inline in the popup with a working "Grant" link to System Settings
- [ ] Empty-textarea flow still works when Accessibility is denied
- [ ] Revoked Accessibility permission is detected at runtime and re-prompted on next attempt
- [ ] Manual test matrix (`TESTING.md` drafted this phase): paste works in Slack, Mail, Notes, VS Code, Safari text field, Terminal, Messages — or known failures are documented

---

## Phase 6: Error states + menubar polish

**User stories**: 19, 20, 21, 22 (rewritten), 23 (rewritten)

### What to build

Full error-handling coverage and menubar icon feedback.

- `ErrorClassifier` maps all expected failure modes to typed cases with user-facing messages and suggested actions:
  - **Claude not installed** (`claude` not on PATH at runtime, changed since first launch) → "Claude Code not found" + link to install page.
  - **Claude not authenticated** (`claude auth status` reports `loggedIn: false` or non-subscription auth) → "Log into Claude Code" + open Preferences with re-check button.
  - **Subprocess non-zero exit with rate-limit markers in stderr** → "Rate limited by Claude — wait a few minutes and retry" + manual retry button.
  - **Subprocess non-zero exit, generic** → "Claude error: <first line of stderr>" + retry button.
  - **Timeout (>20 s)** → SIGTERM/SIGKILL the subprocess, show "Claude took too long" + retry button.
  - **Offline** (detected from Claude CLI stderr network-error output) → "You're offline" + retry button; auto-retry when reachability restored.
  - **Input too long** (already blocked in Phase 2) → surfaces cosmetically consistent with the others.
- **Story 22 rewrite**: was "Invalid API key with a button that opens Settings." Becomes "Claude Code not authenticated" with a button that opens a terminal running `claude /login` (or shows instructions to do so).
- **Story 23 rewrite**: was "auto-retry 429 with exponential backoff." Becomes "auto-retry on detected Claude rate-limit with a single retry after 60 s." (Claude subscription rate limits have longer reset windows; aggressive backoff doesn't help.)
- Menubar icon states: static default / subtle dot-pulse while any subprocess is in flight / red tint when last attempt ended in a persistent error (auth broken, rate limited).
- Retry affordances in the popup: a single "Retry" button inline with the error message, where applicable.

### Acceptance criteria

- [ ] All six error cases above surface with the specified copy and action
- [ ] Rate-limit error triggers one auto-retry after 60 s; if still limited, surfaces as manual retry
- [ ] Auth error has a working button that prompts the user to run `claude /login`
- [ ] Offline error auto-recovers and re-fires the subprocess when network returns (within one minute of reconnect)
- [ ] Menubar icon pulses during active subprocesses and tints red on persistent error; returns to default on next success
- [ ] `ErrorClassifier` has unit tests covering every mapped case
- [ ] Subprocess timeout correctly kills the process and does not leak Node.js instances

---

## Phase 7: Login Item + distribution

**User stories**: 24

### What to build

Packaging and ship-readiness.

- `LoginItemManager` wraps `SMAppService.loginItem(identifier:)` with enable/disable/status.
- Preferences gains a "Launch at login" toggle wired to `LoginItemManager`. Default off; user opts in.
- Release build configuration is set up in Xcode: optimizations on, `LSUIElement` true, bundle ID finalized.
- The repo gains a `TESTING.md` documenting the manual test checklist from Phase 5 plus the end-to-end sanity flow (hotkey → popup → spinner → result → accept → paste → clipboard restored) for each tested app.
- A build script (`make build` / shell script) produces an ad-hoc-signed `.app` bundle ready to drag into `/Applications`. README documents the Gatekeeper right-click-Open workaround on first launch and the Claude Code prerequisite.

### Acceptance criteria

- [ ] Toggling "Launch at login" in Preferences adds/removes the app from macOS Login Items reliably
- [ ] After login, the menubar icon appears automatically and the hotkey works
- [ ] `make build` (or equivalent) produces a `.app` that launches cleanly from `/Applications` on a fresh Mac (assuming Claude Code is installed + logged in)
- [ ] `TESTING.md` covers the manual test checklist with per-app pass/fail rows
- [ ] README has copy-paste instructions for installing the build on a new machine, including the Claude Code dependency
