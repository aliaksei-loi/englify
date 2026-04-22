# Playgrounds

Throwaway code that validates the two riskiest assumptions before any real app code is written. Both scripts run from your terminal as one-off Swift files. They do not ship.

Plan reference: [Phase 1 in `../plans/englify-plan.md`](../plans/englify-plan.md).

## A — OpenAI SSE streaming (`streaming.swift`)

Validates that `URLSession.bytes(for:)` + SSE parsing produces the streaming contract the real app will depend on.

```sh
OPENAI_API_KEY=sk-... swift playgrounds/streaming.swift
```

Three tests run automatically:
1. **Normal stream to completion** — expect tokens to print live, ending with `✅ DONE`.
2. **Cancel at ~500 ms** — expect the stream to stop mid-output with `✅ CANCELLED`.
3. **Bad key → HTTP 401** — expect `✅ 401 as expected`.

### Pass criteria

- All three tests hit their `✅` branch.
- First token of Test 1 appears within ~1 s (anchors the streaming latency budget in the spec).
- Test 2 cancels cleanly — no leaked tasks, no spew after the cancelled message.

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
