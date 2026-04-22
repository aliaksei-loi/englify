# Englify — Spec

macOS menubar app. Hotkey → popup → LLM rewrites selected text (or typed text) → pick variant → replaces selection.

> **Backend pivot (2026-04-22):** originally designed against OpenAI API direct. Pivoted to shelling out to the `claude` CLI using the user's existing Claude Code subscription (Team plan) to avoid any paid API credits. This is a compromised architecture — see the Tradeoffs section below. The original OpenAI design is preserved in git history (commit `0787985`).

## Stack

- Native Swift / SwiftUI, macOS 14+ deployment target
- Single Xcode target, menubar-only (`LSUIElement = true`)
- Dependencies: `KeyboardShortcuts` (sindresorhus) for global hotkey
- **LLM backend: `claude` CLI subprocess**, authenticated via the user's existing Claude Code login (subscription — no API key). Model: `claude-haiku-4-5`.
- No backend server, no database, no persistence of rewrites

## Tradeoffs (backend = Claude CLI)

Measured on the user's machine (2026-04-22):

| Metric | Value |
|---|---|
| CLI cold-start overhead | ~6 s (Node.js process startup) |
| Inference time (Haiku) | ~3.3 s |
| Total latency per hotkey press (spawn-per-call) | ~9–10 s |
| Streaming tokens to stdout | **Does not work** — CLI buffers full response |
| First-call cache creation | ~53k tokens |
| Warm-call cache read (within 1 h) | ~52k tokens (quota-cheap) |

Consequences that this spec accepts:

- **No streaming UX.** The blinking caret / live-token idea from the earlier OpenAI-based design is gone. Popup shows a spinner for the full duration, then the entire result appears at once.
- **Latency budget: 15 s.** Each hotkey press or chip click can take up to that. Operations below 5 s are considered fast.
- **Quota cost is borne by the user's Claude subscription.** First call per hour pays ~53k cache-creation tokens. Subsequent calls read cache (cheap). Heavy use may hit Team-plan rate limits and temporarily block the widget.
- **Hard runtime dependency: Claude Code must be installed and the user logged in with a subscription** (not an API key). If either fails, the app surfaces a clear error rather than trying to work around it.

## Decisions (Q1–Q17)

| # | Topic | Choice |
|---|---|---|
| 1 | Form factor | Native macOS menubar app |
| 2 | Tech | Swift + SwiftUI |
| 3 | UX flow | Select → hotkey → popup with primary + variants → pick → replace selection |
| 4 | LLM | **Claude CLI subprocess, model `claude-haiku-4-5`, subscription auth** |
| 6 | Variants | Primary rewrite + tone chips (Formal / Casual / Shorter) |
| 7 | Variant generation | On-demand — each chip click spawns a new `claude` invocation |
| 8 | Chips | Formal, Casual, Shorter (drop Shorter if unused after 1 week) |
| 9 | No-selection fallback | Popup with empty textarea |
| 10 | Replace mechanism | Clipboard swap + simulated ⌘V + focus restoration |
| 11 | History | None. Fully ephemeral. |
| 12 | Popup placement | Center of active screen. Borderless `NSPanel`, `.nonactivatingPanel` + `.hudWindow` |
| 13 | Output shape | Primary: `Improved` + `Changes` bullets (rendered all-at-once when the subprocess finishes). Variants: improved text only |
| 14 | Onboarding | First launch: check `claude` is on PATH and `claude auth status` reports `loggedIn: true` with a subscription. Accessibility deferred to first replace-in-place use. |
| 15 | Distribution | Ad-hoc signed `.app`, drag to /Applications, Login Item via `SMAppService` |
| 16 | Hotkey | `KeyboardShortcuts`, default ⌥⇧E, rebindable in Preferences |
| 17 | Polish | See below |

## Subprocess invocation contract

Every rewrite is a fresh `claude` process (spawn-per-call). No persistent subprocess in v1 — streaming doesn't work from the CLI, so the only value of a persistent process would be shaving ~6 s per call, which is engineering we defer until after the app is shipped.

```
claude -p \
  --model claude-haiku-4-5 \
  --system-prompt "<see Prompt templates below>" \
  --disable-slash-commands \
  --tools "" \
  --no-session-persistence \
  --output-format json \
  "<user input text>"
```

- Working directory: a temp directory with no `CLAUDE.md` / `.claude/` (avoids auto-loading user context).
- stdin: unused. Input is passed as the final positional argument.
- stdout: a single JSON object with `result` (string) and `usage` keys. Parsed in full when the process exits.
- stderr: captured for error diagnostics.
- Process timeout: 20 s. On timeout, kill the subprocess, surface a user-facing error.
- Cancellation: on popup close / Escape, send SIGTERM to the running subprocess, then SIGKILL after 500 ms if still alive.

## Prompt templates

**Primary (system prompt):**

```
You are an English language editor. Given text the user is about to send, produce an improved version that fixes grammar, word choice, articles, prepositions, and phrasing so it reads like a fluent native speaker wrote it. Preserve the original meaning, tone, and register (casual stays casual; formal stays formal).

Return your output in exactly this format:

**Improved:** <the rewritten text, one paragraph, no quotes, no preamble>

**Changes:**
- <short bullet explaining one key fix>
- <short bullet explaining another key fix>
- <up to 3 bullets total; omit the Changes section entirely if nothing meaningful changed>
```

**Variant (system prompt):**

```
Rewrite the following text to be more {{tone}}. Keep the meaning. Return only the rewritten text, no preamble, no quotes, no explanation.
```

Where `{{tone}}` is `formal`, `casual`, or `concise`.

The user's input text is passed as the final positional argument to `claude -p`. Not embedded in the system prompt.

## Interaction contract

1. Hotkey pressed → capture frontmost app PID + focused `AXUIElement` → read selected text via AX.
2. Open `NSPanel` centered on active screen.
3. If selected text present → spawn `claude` with the primary system prompt + selected text. Show a spinner with elapsed time. Typical duration 3–10 s.
4. Else → focus textarea, wait for input, user presses Enter → then spawn as above.
5. When subprocess exits successfully → parse `result` field → split on `**Improved:**` / `**Changes:**` markers → render both sections at once. Enable variant chips.
6. Click chip (or ⌘1 / ⌘2 / ⌘3) → cancel any in-flight variant → spawn new `claude` with the variant system prompt → show spinner → replace main text on completion.
7. User presses Enter or clicks the currently-shown result:
   - Save current clipboard + `changeCount`
   - Put accepted text on clipboard
   - Re-activate saved PID
   - Post `CGEvent` ⌘V
   - 100 ms later, restore original clipboard
   - Close panel.
8. Escape → cancel in-flight subprocess, close panel.

## Error handling

- `claude` binary not found on PATH → onboarding step fails with "Install Claude Code from claude.ai/install" + deep link.
- `claude auth status` returns `loggedIn: false` or `authMethod` not in `["claude.ai"]` → onboarding fails with "Log into Claude Code with your subscription" (since the app is explicitly designed to avoid API keys).
- Subprocess exits non-zero → parse stderr for `rate_limit` / `usage_limit` markers; surface as "Rate limited by Claude — try again in a few minutes." Otherwise "Claude returned an error: <stderr snippet>" + a "Retry" button.
- Subprocess times out (>20 s) → kill, surface "Claude took too long — retry?"
- Network-level errors from the CLI → surface as offline/service-issue accordingly.
- Input >8k tokens (client-side heuristic `text.count / 4`) → block pre-send.

## Risks to validate early (before investing >1 day)

1. **Clipboard-swap paste in Slack (Electron).** Validated via `playgrounds/paste.swift` — see `playgrounds/RESULTS.md`. If this fails, the whole UX premise collapses regardless of backend.
2. **`claude` subprocess contract.** Validated via `playgrounds/claude_cli.swift` — confirms auth detection, result parsing, typical latency.
3. **Focus restoration timing.** 100 ms delay between paste and clipboard restore is a guess; validate on slow and fast Macs.
4. **Accessibility permission UX.** Deferred onboarding; macOS Sequoia+ reprompts yearly.

## Build order (suggested)

1. **Day 1:** playgrounds — `claude_cli.swift` validates subprocess + auth; `paste.swift` validates clipboard-swap paste in Slack. Go/no-go.
2. **Day 2:** Xcode app skeleton, menubar icon, Preferences window, Claude-Code-installed + auth check, Login Item plumbing.
3. **Day 3:** Popup panel, textarea-fallback flow, spawn `claude` subprocess on Enter, spinner UI, full-response parsing + Changes rendering, copy-to-clipboard.
4. **Day 4:** Accessibility permission prompt, selected-text reading, auto-paste with focus restoration.
5. **Day 5:** Tone chips, variant subprocesses, keyboard shortcuts.
6. **Day 6:** Error states, menubar icon states, Login Item toggle, drag-to-/Applications, TESTING.md.
