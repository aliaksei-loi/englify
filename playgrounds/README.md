# Playgrounds

Throwaway code that validates the two riskiest assumptions before any real app code is written. Both scripts run from your terminal as one-off Swift files. They do not ship.

Plan reference: [Phase 1 in `../plans/englify-plan.md`](../plans/englify-plan.md).

## A — Claude CLI subprocess contract (`claude_cli.swift`)

Validates that shelling out to the `claude` CLI is a viable LLM gateway for the widget: auth detection, result parsing, and cache reuse across calls.

```sh
swift playgrounds/claude_cli.swift
```

Four tests run automatically:
1. **`claude` binary present on PATH.**
2. **`claude auth status`** returns `loggedIn: true` with `authMethod: "claude.ai"` (subscription). No API-key auth expected.
3. **Cold subprocess call** with optimized flags (`--disable-slash-commands`, `--tools ""`, `--system-prompt …`, `--no-session-persistence`, `--output-format json`) → valid JSON out → contains `**Improved:**` / `**Changes:**` markers.
4. **Warm subprocess call** (different input, same system prompt) → cache read dominates cache creation, confirming server-side cache reuse within the 1 h window.

### Pass criteria

- Tests 1 and 2 both `✅`.
- Test 3 produces the expected output format (at minimum the `**Improved:**` marker).
- Test 4 shows `cache_read_input_tokens` significantly exceeding `cache_creation_input_tokens` (proves warm-call quota savings).
- Elapsed time is in the ~9–10 s / ~3–5 s API range predicted in SPEC.md. If wildly worse, update SPEC.md Tradeoffs section.

### If this fails

- Binary missing → `claude` isn't installed. Install Claude Code first.
- Auth wrong → run `claude /login` in a terminal and pick the subscription option.
- Output format wrong → the prompt needs tuning; iterate on the system prompt before Phase 2.

## B — Clipboard-swap paste (`paste.swift`)

Validates the replace-in-place mechanism (save clipboard → overwrite → post ⌘V → restore) across the apps you actually use.

```sh
swift playgrounds/paste.swift "hello from englify" "Slack"
```

Requirements:
- The target app must already be running.
- Click into a text field inside the target app before or during the 2-second countdown.
- Your Terminal (or iTerm) process needs Accessibility permission. macOS will prompt on first run — grant it in System Settings → Privacy & Security → Accessibility.

### Apps to test

Run the script once per target. Record the result in `RESULTS.md`.

- `Slack` — the decisive test. Electron. If this breaks, the UX premise is broken.
- `Mail` — Cocoa baseline.
- `Notes` — Cocoa baseline.
- `Visual Studio Code` — Electron.
- `Safari` — target a text field on any page.
- `Terminal` — target the running shell.
- `Messages` — Cocoa.

### Pass criteria

- Paste lands in the target app with the exact text.
- Clipboard is restored to its pre-paste contents (the script prints `Clipboard restored correctly: ✅`).
- No timing glitches (paste appears, then clipboard swap doesn't clobber the visible result).

## Results

After running both, create `playgrounds/RESULTS.md` with your findings. If anything fails — especially Slack paste — capture enough detail to decide whether to rescope Phase 2 or whether the fix is small.
