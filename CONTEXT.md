# Englify — Domain Glossary

A macOS app that rewrites the user's English to sound native, fast.
Primary goal: **the user's text looks native**. Secondary, passive bonus:
the user can glance at what was wrong with the original.

This is a **writing tool**, not a learning tool. No forced friction, no
gates, no "you must read the explanation before copying." If the user
wants to learn, that happens through unforced exposure to the diff —
not through enforced UX.

---

## Improve

The single user-facing action. Produces three things, shown together,
no toggles:

1. **Native version** — the primary output. This is what gets copied.
   Default focus, biggest visual weight, Copy button defaults to this.
   The rewrite is **faithful**: preserves the user's meaning, confidence,
   and directness. Fixes broken English, does not launder tone. See
   `docs/adr/0001-faithfulness-over-polish.md`.
2. **Original with inline mistake marks** — the user's input, with
   errors visually called out. Passive glance surface.
3. **Mistakes summary** — short bullets: "missing article", "wrong
   tense". Compact, low visual weight. No long lecture mode.

When the input is already native-quality, the model returns a `looks_good`
signal instead of a rewrite. The UI shows the user's text as-is with a
"No changes needed" badge. Trade-off accepted: occasional false positives
(model misses a small wobble). Preferable to forcing the user to diff two
paragraphs by eye for every "improve".

The "corrected-but-still-yours" middle tier is dropped. The user does
not want a half-step; they want the native version.

## Input

Typed directly into the app's window. No clipboard auto-capture, no
Accessibility-based reading of selected text from other apps. May
return later if friction demands.

## Output

Single primary action: copy native version to clipboard. The user
then pastes wherever they were writing (Slack, Gmail, etc).
No history, no persistence in MVP.

## Register / Tone

The "native" output must match the register of the input — Slack-casual
input should not become LinkedIn-formal output, and vice versa.

- **Auto-detect** is the default: the model infers register from the
  input itself.
- **Inline override** via bracket prefix: `[casual] ...`, `[formal] ...`,
  etc. The bracket directive is consumed (not echoed in the output).

No dropdowns, no preset picker UI. One textarea, optional prefix.

## LLM transport

The model is invoked by spawning the `claude` CLI in headless mode as a
subprocess. The user's existing Claude subscription supplies access; no
API key, no per-token billing. Pattern is reused from the user's `bnrp`
project. See `docs/adr/0002-claude-cli-subprocess.md`.

## Translation (escape hatch)

Russian input is **refused by default** with the hint to add `[ru]`. With
the prefix (`[ru] я хочу сказать что...`), the model translates to
English and marks the output as `Translated from Russian` in the UI.

The friction is deliberate. Translation is an exception path for urgent
or high-stakes messages where the user cannot afford to fumble English.
A silent auto-detect would let translation drift into the default mode
and silently erode the user's actual writing practice — which is the
whole reason the app exists.
