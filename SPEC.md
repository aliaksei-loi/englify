# Englify — Spec

macOS menubar app. Hotkey → popup → LLM rewrites selected text (or typed text) → pick variant → replaces selection.

## Stack

- Native Swift / SwiftUI, macOS 14+ deployment target
- Single Xcode target, menubar-only (`LSUIElement = true`)
- Dependencies: `KeyboardShortcuts` (sindresorhus) for global hotkey
- OpenAI API direct (`gpt-4o-mini`), key in Keychain
- No backend, no database, no persistence of rewrites

## Decisions (Q1–Q17)

| # | Topic | Choice |
|---|---|---|
| 1 | Form factor | Native macOS menubar app |
| 2 | Tech | Swift + SwiftUI |
| 3 | UX flow | Select → hotkey → popup with primary + variants → pick → replace selection |
| 4 | LLM | OpenAI `gpt-4o-mini`, BYO API key |
| 6 | Variants | Primary rewrite + tone chips (Grammarly-style) |
| 7 | Variant generation | On-demand — primary streams immediately; chips fire fresh calls on click |
| 8 | Chips | Formal, Casual, Shorter (drop Shorter if unused after 1 week) |
| 9 | No-selection fallback | Popup with empty textarea |
| 10 | Replace mechanism | Clipboard swap + simulated ⌘V + focus restoration |
| 11 | History | None. Fully ephemeral. |
| 12 | Popup placement | Center of active screen. Borderless `NSPanel`, `.nonactivatingPanel` + `.hudWindow` |
| 13 | Output shape | Primary: `Improved` + `Changes` bullets (streamed, parsed on markers). Variants: improved text only |
| 14 | Onboarding | API key at first launch (with test-call), Accessibility deferred to first replace-in-place use |
| 15 | Distribution | Ad-hoc signed `.app`, drag to /Applications, Login Item via `SMAppService` |
| 16 | Hotkey | `KeyboardShortcuts`, default ⌥⇧E, rebindable in Preferences |
| 17 | Polish | See below |

## Polish (Q17)

**Errors (inline in popup):**

- No network → "You're offline" + auto-retry on reconnect
- 401 → "Invalid API key" + Open Settings
- 429 → "Rate limited, retrying…" + exponential backoff
- 5xx → "OpenAI service issue" + retry
- Stream stall >15s → cancel, show "Timed out" + retry
- Input >8k tokens → block with "Text too long (~8k tokens max)" (local count: `text.count / 4` heuristic)
- Esc during stream → cancel `URLSessionDataTask`, close panel

**Menubar:**

- Icon: SF Symbol `pencil.tip`, template-rendered
- States: static / pulse during in-flight request / red tint on persistent error
- Menu: `Rewrite (⌥⇧E)` · `Preferences...` · `Quit` — nothing else

**Streaming UI:**

- Tokens appear live with blinking caret
- `Changes` bullets render below as they stream
- Tone chips disabled during primary stream, enabled after
- No spinners — the stream is the spinner

## Prompt templates

**Primary (reuse `/englify`):**

```
Improve the English of the following text. Keep the original meaning, tone, and intent. Fix grammar, word choice, articles, prepositions, and phrasing so it reads naturally like a fluent native speaker wrote it. Preserve the original register.

Output format:
**Improved:** the rewritten text only — no quotes, no preamble.
**Changes:** 1–3 short bullets explaining the key fixes (skip if already fine).

Text to improve:
{{input}}
```

**Variants (one per tone chip):**

```
Rewrite the following text to be more {{tone}}. Keep the meaning. Return only the rewritten text, no preamble.

Text:
{{input}}
```

Where `{{tone}}` is `formal`, `casual`, or `concise` (for the Shorter chip).

## Interaction contract

1. Hotkey pressed → capture frontmost app PID + focused `AXUIElement` → read selected text via AX
2. Open `NSPanel` centered on active screen
3. If selected text present → fire primary OpenAI stream immediately, show streaming output
4. Else → focus textarea, wait for input, user presses Enter → fire stream
5. Chips enable after primary completes; click chip → fire variant stream, swap main text
6. User presses Enter or ⌘1/⌘2/⌘3:
   - Save current clipboard + `changeCount`
   - Put accepted text on clipboard
   - Re-activate saved PID
   - Post `CGEvent` ⌘V
   - 100ms later, restore original clipboard
   - Close panel
7. Esc → cancel in-flight, close panel

## Risks to validate early (before investing >1 day)

1. **Clipboard-swap paste in Slack (Electron).** Test on day 1 with a hello-world paster before building any UI. If it fails, you need plan B before sinking time.
2. **Focus restoration timing.** The 100ms delay before clipboard restore is a guess. Validate on slow and fast machines.
3. **Accessibility permission UX.** macOS Sequoia+ reprompts yearly for AX — plan for re-grant flow, don't assume once-forever.
4. **OpenAI streaming in Swift.** Use `URLSession.bytes(for:)` for SSE. Write a throwaway playground that streams chat completions and parses `data:` lines before wiring it to UI.

## Build order (suggested)

1. **Day 1:** Playground — OpenAI streaming via `URLSession.bytes`. Separate playground — clipboard-swap paster into Slack. De-risk both before any app scaffolding.
2. **Day 2:** Xcode app skeleton, menubar icon, Preferences window with API key + hotkey rebinder, Keychain storage, test-key button.
3. **Day 3:** Popup panel, textarea-fallback flow (no selection reading yet), primary-only streaming, Changes parsing, Enter to copy-to-clipboard (no auto-paste yet).
4. **Day 4:** Accessibility permission prompt, selected-text reading, auto-paste with focus restoration.
5. **Day 5:** Tone chips, variant streaming, keyboard shortcuts.
6. **Day 6:** Error states, polish, Login Item, drag to /Applications.
