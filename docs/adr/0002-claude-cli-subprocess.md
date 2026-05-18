# Claude CLI subprocess as the LLM transport

The app invokes Claude by spawning the `claude` CLI in headless print mode
(`claude -p --output-format stream-json --session-id ... --model ...`)
as a `Process()` from SwiftUI. The user's existing Claude subscription
(Pro/Max), already authenticated via the CLI, supplies the model access.
No API key, no per-token billing, no separate auth flow inside the app.

This pattern is taken directly from the user's earlier macOS project
`bnrp` (Bible reader) where it is already proven: SwiftUI app spawns
`claude -p`, streams line-delimited JSON events, decodes off the main
actor, mutates an `@Observable` state. The same shape transfers here
verbatim — minus the MCP config, since Englify needs no tools.

Considered and rejected:
- **Anthropic API directly.** Costs money per call (~$50/mo at moderate
  use), requires API key storage in the app, and would not use the
  Claude subscription the user is already paying for. The whole point
  of this project — per the user — is to live inside that subscription.
- **Local model (Ollama / llama.cpp).** Quality on register-sensitive
  rewriting is materially worse, which would silently violate the
  faithfulness contract in ADR-0001 (small models drift toward polish).
  Also burns RAM and battery on a laptop.

Consequences:
- The app cannot run without the `claude` CLI installed and signed in.
  This is acceptable — it is a personal tool for one user who already
  has both.
- Subscription usage caps apply (Claude Pro / Max limits). For a
  personal writing tool used a few dozen times a day, this is well
  under the cap.
- Each `improve` call pays subprocess spawn latency (~100–300 ms on top
  of model latency). Acceptable for the use case.
- No MCP server is needed. The system prompt + user text is the entire
  input; the model returns structured text. Keep the surface minimal.
