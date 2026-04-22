# Englify

macOS menubar app. Select text anywhere → hotkey → LLM-improved version replaces the selection. Tone variants (Formal / Casual / Shorter) on demand.

Built for non-native English speakers who write in tech contexts.

## Status

Early development. See [SPEC.md](SPEC.md) for the full design.

## Stack

- Native Swift / SwiftUI, macOS 14+
- OpenAI `gpt-4o-mini` (BYO API key)
- `KeyboardShortcuts` for the global hotkey
- No backend, no persistence

## How it works

1. Select text in any app
2. Press ⌥⇧E
3. Popup shows the improved text streaming in, plus what changed
4. Press Enter to accept, or ⌘1 / ⌘2 / ⌘3 for Formal / Casual / Shorter variants
5. Clipboard-swap + simulated ⌘V pastes it back into the source app

See [SPEC.md](SPEC.md) for decisions, prompts, interaction contract, and risks.
