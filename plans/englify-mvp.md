# Plan: Englify MVP

> Source: `CONTEXT.md` + `docs/adr/0001-faithfulness-over-polish.md` + `docs/adr/0002-claude-cli-subprocess.md`

## Architectural decisions

Durable decisions that apply across all phases:

- **Platform**: macOS-only native app. SwiftUI + AppKit shims where needed (global hotkey, window-on-top). No iOS, no cross-platform.
- **Project layout**: pattern reused from `aliaksei-loi/bnrp` — `project.yml` (XcodeGen) + Swift app target + optional SPM kit for the model/transport layer. `.xcodeproj` is gitignored, regenerated via `xcodegen generate`.
- **LLM transport**: `claude` CLI spawned as `Process()` subprocess with `-p` (headless print). Uses the user's existing Claude subscription — no API key, no MCP config needed (Englify has no tools to expose). See ADR-0002.
- **System prompt contract**: faithfulness-first — fix broken English, do not launder tone, do not add hedging the user did not write. See ADR-0001.
- **Output shape**: structured JSON returned by the model, decoded via Swift `Codable`. Single non-streaming response per `improve` call. Fresh `--session-id` per call (no cross-call memory).
- **Key data models**:
  - `ImproveRequest { rawText: String }` — raw textarea content, including any `[casual]`/`[formal]`/`[ru]` prefix; the model is responsible for consuming the directive.
  - `ImproveResponse { status: looks_good | rewritten | translated_from_ru, native: String, originalMarked: String, mistakes: [String] }`
- **Window behavior**: global hotkey opens a borderless floating panel (`NSPanel`, `.floating` level, non-activating where possible). Window auto-dismisses after copy or Esc. No history, no persistence.
- **Storage**: none in MVP. No SQLite, no SwiftData, no `UserDefaults` beyond hotkey binding (added in Phase 4).
- **Auth**: piggybacks on `claude` CLI's existing login. App detects "not authenticated" via subprocess exit and surfaces the fix step.

---

## Phase 1: End-to-end tracer

**User stories**: open window with hotkey, type a draft, get a native rewrite, copy to clipboard, paste in destination app.

### What to build

A floating window summoned by ⌘⇧E that contains a textarea, an Improve action triggered by ⌘↩, and a Copy action. On Improve, the app spawns `claude -p` with a minimal faithfulness-flavored system prompt and the user's text; the model returns the rewritten English as plain text. Copy puts the result on the clipboard and dismisses the window. Esc dismisses without copying.

This phase delivers a **usable writing tool** end-to-end. No structured output, no register handling, no error UX yet — just the core "select → improve → paste" loop a person could start using in Slack today.

### Acceptance criteria

- [ ] ⌘⇧E (registered globally) opens the window above the currently focused app
- [ ] Window contains a multi-line textarea and a visible Improve button
- [ ] ⌘↩ in the textarea triggers Improve; the button does the same
- [ ] Improve spawns `claude -p --model <chosen>` with a system prompt that says "rewrite to sound native, preserve meaning/confidence/directness, do not add hedging"
- [ ] The model's plain-text response is shown below the textarea
- [ ] A Copy button puts the response on the clipboard and dismisses the window
- [ ] Esc dismisses the window at any time
- [ ] Re-opening the window starts with an empty textarea

---

## Phase 2: Structured output

**User stories**: see at a glance what was wrong with the original; skip the rewrite entirely when the input was already native.

### What to build

The system prompt is upgraded to require a JSON response with `status`, `native`, `originalMarked`, and `mistakes`. The Swift side decodes via `Codable` and renders three regions in the window: the native version (primary, largest, target of Copy), the user's original with inline mistake marks, and a compact bullet list of mistake categories. When `status = looks_good`, the native region is replaced by a "No changes needed" badge and Copy targets the original text unchanged.

Parsing failures (malformed JSON) fall back to showing the raw response with a small "parse error" notice — Copy still works on the raw text.

### Acceptance criteria

- [ ] System prompt instructs the model to return JSON only, no surrounding prose
- [ ] Response is decoded into the `ImproveResponse` model
- [ ] UI renders: native (large, primary), original-with-marks (secondary), mistakes summary (compact bullets)
- [ ] Copy button always targets the appropriate text (native when rewritten, original when looks_good)
- [ ] `looks_good` status shows a "No changes needed" badge and suppresses the native section
- [ ] If JSON decoding fails, the raw response is shown with a "parse error" indicator and Copy still works

---

## Phase 3: Register & translation directives

**User stories**: writing tool matches the tone of the input; escape hatch for high-stakes Russian-input cases.

### What to build

The system prompt is extended to (a) infer register from the input and produce output at the same register, and (b) honor bracket-prefix directives. The Swift side does not parse the prefix — the model consumes it and applies it. Supported directives: `[casual]`, `[formal]`, `[ru]`. When the input is Russian and no `[ru]` prefix is present, the model returns a refusal payload (a new `status` value) and the UI shows the hint "Add `[ru]` to translate" instead of a rewrite. When `[ru]` is present, the result is rendered with a "Translated from Russian" tag above the native section.

### Acceptance criteria

- [ ] System prompt explicitly tells the model to match register (casual stays casual, formal stays formal)
- [ ] `[casual] hey...` → output is casual-register English; the bracket is not echoed
- [ ] `[formal] just wanted to...` → output is formal-register English
- [ ] Russian input without `[ru]` → refusal UI with "Add `[ru]` to translate" hint, no rewrite shown
- [ ] `[ru] я хочу...` → English output with "Translated from Russian" tag visible above the native section
- [ ] `ImproveResponse` model supports a `refused_russian` status value

---

## Phase 4: Failure modes & configurability

**User stories**: when something breaks, the user knows what to do; the hotkey can be changed when it conflicts.

### What to build

Each failure path gets a specific, actionable message instead of a generic error. Settings panel (separate window, opened from a menu-bar item or keyboard shortcut) exposes hotkey rebinding. A soft warning appears when the textarea crosses 5000 characters (does not block submission).

Failure modes to handle:
- `claude` CLI not found on `PATH` → message with "Install Claude Code: claude.ai/code" and a copy-link button
- CLI present but not authenticated (detected via subprocess exit / stderr) → "Run `claude` in Terminal once to sign in" with an Open Terminal button
- Network unreachable → "You're offline. Check your connection and try again."
- Subprocess timeout >30s → "Taking too long. Retry?" with Cancel/Retry actions
- JSON decode failure → already handled in Phase 2 (raw text fallback); no change here

### Acceptance criteria

- [ ] Each of the four failure modes shows its specific message with its specific action button
- [ ] Settings window is reachable (menu-bar item or ⌘, while window is focused)
- [ ] Hotkey rebinding in Settings works: new combo replaces ⌘⇧E live without app restart
- [ ] Hotkey binding persists across app launches (stored in `UserDefaults`)
- [ ] Textarea content ≥5000 chars shows a non-blocking warning ("Long input — response may be slow")
- [ ] Submitting >5000 chars still works
