# Plan: Englify

> Source PRD: [aliaksei-loi/englify#1](https://github.com/aliaksei-loi/englify/issues/1)
> Source spec: [SPEC.md](../SPEC.md)

## Architectural decisions

These are locked for the full implementation and apply across every phase below.

- **Platform**: native macOS, deployment target macOS 14 (Sonoma). Swift + SwiftUI. Menubar-only (`LSUIElement = true`), no Dock icon.
- **Process model**: single app target. No helper processes, no backend, no daemons. Runs on login via `SMAppService.loginItem`.
- **LLM provider**: OpenAI `gpt-4o-mini` over direct HTTPS from the app. Endpoint: `POST https://api.openai.com/v1/chat/completions`. Streaming via SSE (`stream: true`). Temperature `0.3` for primary rewrite, `0.7` for variants. No backend proxy.
- **Auth**: user-supplied OpenAI API key, stored in the macOS Keychain. Never leaves the machine except to `api.openai.com`.
- **Runtime dependency**: `KeyboardShortcuts` (sindresorhus) Swift Package — only third-party dependency. All other functionality uses system frameworks (Foundation, AppKit, SwiftUI, ApplicationServices, Security, ServiceManagement).
- **Module decomposition** (from PRD): deep modules `OpenAIStream`, `StreamParser`, `PromptFactory`, `ErrorClassifier`, `KeychainStore`. Deep-ish modules `PasteController`, `SelectionReader`. Shallow UI/glue modules `HotkeyCoordinator`, `MenubarController`, `PopupWindow`, `PopupView`, `OnboardingView`, `PreferencesView`, `LoginItemManager`, `AppCoordinator`.
- **Testing posture**: automated unit/integration tests for the five deep modules and `OpenAIStream`. Manual test checklist (`TESTING.md`) for `PasteController` and `SelectionReader`. No tests for UI/glue modules.
- **Persistence**: none. No rewrite history on disk. Keychain stores only the API key and (via `KeyboardShortcuts`) the user's hotkey preference in `UserDefaults`. In-memory state only while the app runs.
- **UI conventions**: popup is a borderless `NSPanel` with `.nonactivatingPanel` + `.hudWindow` styleMask, centered on the active screen. Default hotkey ⌥⇧E, rebindable. Accept shortcuts Enter / ⌘1 / ⌘2 / ⌘3. Cancel shortcut Escape.
- **Distribution**: ad-hoc signed `.app`, dragged into `/Applications`. No notarization, no App Store (sandboxing would break Accessibility), no Sparkle in v1.
- **Permissions**: Accessibility permission required for selection reading and for posting `CGEvent` paste events. Deferred to first use that needs it (not demanded at first launch). Empty-textarea flow works without it.
- **Input cap**: ~8k tokens, checked client-side before sending via `text.count / 4` heuristic.

---

## Phase 1: De-risking playgrounds (throwaway)

**User stories**: 5 (validation only), 27, 28 (validation only)

### What to build

Two standalone Swift playground files (or short scratch Xcode targets) that validate the two riskiest assumptions before any app code is written. These are throwaway; they do not ship. Output of this phase is a go/no-go decision plus notes captured back in `SPEC.md` if any assumption is proven wrong.

- **Playground A — OpenAI SSE streaming**: authenticated POST to `/v1/chat/completions` with `stream: true`, consuming the response via `URLSession.bytes(for:)`, parsing `data: …` SSE lines, emitting token deltas, terminating cleanly on `data: [DONE]`. Verify task cancellation mid-stream works.
- **Playground B — Clipboard-swap paste into Slack**: save current clipboard + `changeCount`, write new string, activate Slack, post `CGEvent` for ⌘V, restore clipboard after 100 ms. Verify Slack receives the paste and the clipboard ends up restored. Repeat in Mail, Notes, VS Code, Safari text field, Terminal, Messages. Note any failures — they shape Phase 5.

### Acceptance criteria

- [ ] Playground A streams tokens from a live OpenAI call and terminates cleanly
- [ ] Playground A cancels an in-flight stream within 200 ms of calling `cancel()`
- [ ] Playground B pastes successfully into Slack (Electron) and restores the original clipboard
- [ ] Playground B results across the target app list are documented; known-broken apps (if any) are listed in `SPEC.md`
- [ ] Go/no-go decision recorded: if Slack paste is broken, project is rescoped before Phase 2 starts

---

## Phase 2: First tracer — type, rewrite, copy

**User stories**: 2, 3, 4, 15, 16, 29, 30

### What to build

A menubar-only macOS app that can rewrite English text end-to-end, without any selection capture or auto-paste. This is the thinnest possible complete slice through every layer.

- Menubar icon appears on launch; clicking shows a menu with "Rewrite (⌥⇧E)", "Preferences...", "Quit".
- First-launch onboarding window asks the user for their OpenAI API key. A "Test" button fires a single live call to verify the key; on success the key is written to Keychain and the window closes. On failure, the user sees the specific error.
- Preferences window exposes: hotkey rebinder (via `KeyboardShortcuts` SwiftUI component), API key revision with re-test.
- Pressing the hotkey opens the popup (`NSPanel`, centered on active screen) with an empty textarea focused. User types or pastes text, presses Return, sees the improved text appear in the popup. No streaming yet — the whole response is displayed at once. A Copy button (or ⌘C) copies the improved text to the clipboard.
- Input longer than ~8k tokens is blocked with an inline "Text too long" message before the request fires.

### Acceptance criteria

- [ ] App runs from `/Applications` or Xcode, appears in the menubar, is not in the Dock
- [ ] First launch blocks on API-key entry; the "Test" button makes a real OpenAI call and surfaces success/failure
- [ ] API key is written to and read from Keychain; re-launching the app reuses the stored key without re-prompting
- [ ] Hotkey ⌥⇧E opens the popup; the popup appears centered on the active screen; pressing Escape closes it
- [ ] User can rebind the hotkey in Preferences and the new binding takes effect immediately
- [ ] A typed rewrite returns improved text within a reasonable time and the result is copyable via ⌘C or the Copy button
- [ ] Oversized input (heuristic >8k tokens) is blocked pre-send with a visible message
- [ ] Quit from the menubar fully exits the process

---

## Phase 3: Streaming + Changes bullets

**User stories**: 7, 8, 13, 26

### What to build

Upgrade the primary rewrite call to true SSE streaming and render the output live.

- `OpenAIStream` switches from blocking to async-stream token delivery.
- `StreamParser` is introduced: it consumes the token stream and splits it into two sub-streams (`improved`, `changes`) based on the `**Improved:**` / `**Changes:**` markers in the prompt output format. Handles tokens that straddle marker boundaries.
- The popup's result area renders the `improved` sub-stream token by token with a blinking caret at the insertion point. The caret disappears when the stream ends.
- Below the improved text, a small muted "Changes" label appears when the `changes` sub-stream starts; bullets render one by one as they stream in.
- Escape cancels the underlying `URLSessionDataTask` and closes the popup. An in-flight cancel reaches the network layer within ~200 ms.

### Acceptance criteria

- [ ] Primary rewrite streams tokens to the UI as they arrive — first token visible within ~1 s of pressing Enter
- [ ] Blinking caret tracks the streaming insertion point and disappears at stream end
- [ ] `StreamParser` correctly splits Improved / Changes even when markers fall across token boundaries
- [ ] If the model omits the Changes section, the Changes label does not appear (no empty region)
- [ ] Pressing Escape during streaming cancels the request and closes the popup without error toast
- [ ] `StreamParser` has unit tests covering well-formed, Changes-omitted, marker-straddling, and malformed inputs
- [ ] `OpenAIStream` has an integration test using injected `URLProtocol` with canned SSE bytes

---

## Phase 4: Tone variants

**User stories**: 9, 10, 11, 12, 14

### What to build

Add on-demand tone variants to the popup.

- Three chip buttons appear below the improved-text area: Formal, Casual, Shorter.
- Chips are disabled while the primary stream is in flight. Once the primary stream completes, chips become enabled.
- Clicking a chip (or pressing ⌘1 / ⌘2 / ⌘3) cancels any in-flight variant request, fires a fresh streaming call with the corresponding variant prompt, and replaces the main result area with the new stream. Variant calls return only the rewritten text — no Changes section is rendered for variants.
- Pressing Enter accepts the currently displayed text (primary or active variant) by copying it to the clipboard and closing the popup. Auto-paste is still Phase 5.
- `PromptFactory` gains variant templates for `.formal`, `.casual`, `.shorter` styles.

### Acceptance criteria

- [ ] Three chips visible below the result; disabled during primary stream, enabled after
- [ ] ⌘1 / ⌘2 / ⌘3 trigger the matching chip
- [ ] Clicking a chip replaces the main result area with a fresh streamed variant within ~1 s
- [ ] Rapidly clicking a second chip cancels the first variant's stream before starting the second
- [ ] Changes section is hidden during and after a variant is displayed
- [ ] Enter accepts whichever text is currently displayed (primary or active variant) to the clipboard and closes the popup
- [ ] `PromptFactory` has unit tests covering all four styles

---

## Phase 5: Selection reading + auto-paste

**User stories**: 1, 5, 17, 18, 27, 28

### What to build

Wire up the magic flow: select text, hit hotkey, accept, paste replaces selection in source app.

- `SelectionReader` reads the selected text from the focused `AXUIElement` at hotkey-press time. Also captures the frontmost app's PID for later focus restoration.
- First time selection reading is attempted and Accessibility permission is not granted: a permission explainer appears in the popup with a "Grant" button that deep-links to System Settings → Privacy → Accessibility. The existing empty-textarea fallback flow still works without the permission.
- At runtime, the app detects revoked Accessibility permission (post-update or post-annual-reprompt on Sequoia+) and re-prompts cleanly on next selection-capture attempt.
- When selection is present at hotkey time, the popup opens with the selected text pre-populated and the primary rewrite fires immediately.
- `PasteController` implements the accept flow: save current clipboard contents + `changeCount`, write accepted text to clipboard, re-activate the saved PID (`NSRunningApplication.activate`), post `CGEvent` for ⌘V, wait 100 ms, restore original clipboard.
- Enter / ⌘1 / ⌘2 / ⌘3 in the popup now call into `PasteController` instead of just copying.

### Acceptance criteria

- [ ] Selecting text in any app and pressing ⌥⇧E pre-populates the popup with that text and starts the primary stream immediately
- [ ] Accepting a rewrite pastes it back into the source app, replacing the original selection
- [ ] The user's original clipboard contents are restored within 200 ms of paste completion
- [ ] Focus returns to the source app for the paste (not the popup, not another app)
- [ ] First-time Accessibility prompt appears inline in the popup with a working "Grant" link to System Settings
- [ ] Empty-textarea flow still works when Accessibility is denied
- [ ] Revoked Accessibility permission is detected at runtime and re-prompted on next attempt
- [ ] Manual test matrix (`TESTING.md` draft started this phase): paste works in Slack, Mail, Notes, VS Code, Safari text field, Terminal, Messages — or known failures are documented

---

## Phase 6: Error states + menubar polish

**User stories**: 19, 20, 21, 22, 23

### What to build

Full error-handling coverage and menubar icon feedback.

- `ErrorClassifier` maps all expected failure modes to typed cases with user-facing messages and suggested actions:
  - Offline / `URLError.notConnectedToInternet` → "You're offline"; auto-retry when reachability is restored.
  - `401` → "Invalid API key"; inline button opens Preferences.
  - `429` → "Rate limited — retrying…"; exponential backoff (e.g., 1s / 2s / 4s, max 3 retries) with visible countdown.
  - `5xx` → "OpenAI service issue"; manual retry button.
  - Stream stall > 15 s → "Request timed out"; manual retry button.
  - Input too long (already blocked in Phase 2) → error surfaces here cosmetically consistent with the others.
- Menubar icon states: static default (SF Symbol, template-rendered) / subtle dot-pulse while any request is in flight / red tint when the last attempt ended in a persistent error (invalid key).
- Retry affordances in the popup: a single "Retry" button inline with the error message, where applicable.

### Acceptance criteria

- [ ] All six error cases above surface with the specified copy and action
- [ ] 429 triggers automatic backoff retries without user intervention; after final retry, falls through to manual retry
- [ ] 401 error has a working "Open Settings" button that lands the user on the API-key field
- [ ] Offline error auto-recovers and re-fires the request when network comes back (within one minute of reconnect)
- [ ] Menubar icon pulses during active requests and tints red on persistent error; returns to default on next success
- [ ] `ErrorClassifier` has unit tests covering every mapped case

---

## Phase 7: Login Item + distribution

**User stories**: 24

### What to build

Packaging and ship-readiness.

- `LoginItemManager` wraps `SMAppService.loginItem(identifier:)` with enable/disable/status.
- Preferences gains a "Launch at login" toggle wired to `LoginItemManager`. Default off; user opts in.
- Release build configuration is set up in Xcode: optimizations on, `LSUIElement` true, bundle ID finalized.
- The repo gains a `TESTING.md` documenting the manual test checklist from Phase 5 plus the end-to-end sanity flow (hotkey → popup → paste → clipboard restored) for each tested app.
- A build script (`make build` / shell script) produces an ad-hoc-signed `.app` bundle ready to drag into `/Applications`. README documents the Gatekeeper right-click-Open workaround on first launch.

### Acceptance criteria

- [ ] Toggling "Launch at login" in Preferences adds/removes the app from macOS Login Items reliably
- [ ] After login, the menubar icon appears automatically and the hotkey works
- [ ] `make build` (or equivalent) produces a `.app` that launches cleanly from `/Applications` on a fresh Mac
- [ ] `TESTING.md` covers the manual test checklist with per-app pass/fail rows
- [ ] README has copy-paste instructions for installing the build on a new machine
