# AI Chess Arena · Stockfish (50 ms) vs Random · effort=None

Verifier: python-chess 1.11.2 for legality, Stockfish 19 depth 10 for evaluation.
Rules: 3 attempts per move, on failure = random; move cap 30, then Stockfish adjudication at ±8 pawns.

## Score: Stockfish (50 ms) 2.0 – 0.0 Random

| Game | White | Black | Result | Termination | Plies |
|---|---|---|---|---|---|
| game1 | Stockfish (50 ms) | Random | 1-0 | checkmate | 19 |
| game2 | Random | Stockfish (50 ms) | 0-1 | checkmate | 36 |

## Per-side stats

| Game | Side | Player | Moves | Illegal attempts | Top-1 rate | Top-3 rate | Avg loss (pawns) | Blunders (≥2) | Avg s/move | Tokens in/out | Cost USD |
|---|---|---|---|---|---|---|---|---|---|---|---|
| game1 | White | Stockfish (50 ms) | 10 | 0 | 0.6 | 0.9 | 0.28 | 0 | 0.0 | 0/0 | None |
| game1 | Black | Random | 9 | 1 | 0.0 | 0.222 | 1.363 | 3 | 0.0 | 0/0 | None |
| game2 | White | Random | 18 | 3 | 0.111 | 0.111 | 0.676 | 1 | 0.0 | 0/0 | None |
| game2 | Black | Stockfish (50 ms) | 18 | 0 | 0.611 | 0.833 | 0.094 | 0 | 0.0 | 0/0 | None |

Files per game: `<game>.pgn` (with [%eval] comments), `<game>.json` (every prompt reply, attempt, eval), `<game>.log`, `<game>_replay.mp4`, `<game>_eval.png`, `<game>_key_moments.json`, `frames/<game>/*.png`.
