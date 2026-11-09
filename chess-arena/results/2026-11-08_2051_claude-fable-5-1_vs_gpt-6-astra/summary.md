# AI Chess Arena · Claude (claude-fable-5-1) vs OpenAI (gpt-6-astra) · effort=high

Verifier: python-chess 1.11.2 for legality, Stockfish 19 depth 18 for evaluation.
Rules: 3 attempts per move, on failure = forfeit; move cap 150, then Stockfish adjudication at ±8 pawns.

## Score: Claude (claude-fable-5-1) 0.0 – 2.0 OpenAI (gpt-6-astra)

| Game | White | Black | Result | Termination | Plies |
|---|---|---|---|---|---|
| game1 | Claude (claude-fable-5-1) | OpenAI (gpt-6-astra) | 0-1 | checkmate | 68 |
| game2 | OpenAI (gpt-6-astra) | Claude (claude-fable-5-1) | 1-0 | checkmate | 61 |

## Per-side stats

| Game | Side | Player | Moves | Illegal attempts | Top-1 rate | Top-3 rate | Avg loss (pawns) | Blunders (≥2) | Avg s/move | Tokens in/out | Cost USD |
|---|---|---|---|---|---|---|---|---|---|---|---|
| game1 | White | Claude (claude-fable-5-1) | 34 | 1 | 0.529 | 0.765 | 0.706 | 3 | 9.1 | 15560/18025 | 1.0569 |
| game1 | Black | OpenAI (gpt-6-astra) | 34 | 1 | 0.382 | 0.794 | 0.442 | 3 | 46.0 | 10693/39169 | 2.0654 |
| game2 | White | OpenAI (gpt-6-astra) | 31 | 0 | 0.71 | 0.871 | 0.321 | 2 | 32.7 | 8804/26726 | 1.4243 |
| game2 | Black | Claude (claude-fable-5-1) | 30 | 0 | 0.367 | 0.667 | 0.655 | 4 | 3.9 | 12574/5822 | 0.4168 |

Files per game: `<game>.pgn` (with [%eval] comments), `<game>.json` (every prompt reply, attempt, eval), `<game>.log`, `<game>_replay.mp4`, `<game>_eval.png`, `<game>_key_moments.json`, `frames/<game>/*.png`.
