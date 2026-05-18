# Faithfulness over polish in the rewrite

The "native" output must preserve the user's intended meaning, confidence,
directness, and emotional register — even when that produces text that
sounds blunter or less "corporate" than a default LLM rewrite would.

The model's job is to fix what breaks English (grammar, articles, tense,
collocations, idiom). Its job is **not** to soften critique, add hedging
(*might, perhaps, I wonder if*), make suggestions more deferential, or
otherwise nudge the user toward a politer corporate-AI tone. If the user
wrote "this is a bad idea," the output stays "this is a bad idea" —
grammatically correct, not laundered into "I have some concerns about
this approach."

This is recorded because every other writing assistant in the market
defaults to the opposite (polish, soften, sound professional). Without
an explicit decision, the next iteration of the prompt — or the next
person touching the code — will drift toward that default, because
that's what LLMs do unprompted. The cost of that drift is the product's
core value: the user pastes the output without re-reading. That trust
only holds if the output is *their voice*, not an AI-averaged voice.

The accepted trade-off: occasionally the output will sound more direct
than a native speaker would naturally write in a corporate setting.
That is preferable to the alternative.
