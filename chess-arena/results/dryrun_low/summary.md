# AI Chess Arena · Stockfish (50 ms) vs Random · effort=None

Verifier: python-chess 1.11.2 for legality, Stockfish 19 depth 10 for evaluation.
Rules: 3 attempts per move, on failure = random; move cap 30, then Stockfish adjudication at ±8 pawns.

## Score: Stockfish (50 ms) 2.0 – 0.0 Random

| Game | White | Black | Result | Termination | Plies |
|---|---|---|---|---|---|
| game1 | Stockfish (50 ms) | Random | 1-0 | checkmate | 27 |
| game2 | Random | Stockfish (50 ms) | 0-1 | checkmate | 30 |

## Per-side stats

| Game | Side | Player | Moves | Illegal attempts | Top-1 rate | Top-3 rate | Avg loss (pawns) | Blunders (≥2) | Avg s/move | Tokens in/out | Cost USD |
|---|---|---|---|---|---|---|---|---|---|---|---|
| game1 | White | Stockfish (50 ms) | 14 | 0 | 0.643 | 0.929 | 0.114 | 0 | 0.0 | 0/0 | None |
| game1 | Black | Random | 13 | 2 | 0.231 | 0.385 | 0.829 | 1 | 0.0 | 0/0 | None |
| game2 | White | Random | 15 | 2 | 0.2 | 0.4 | 0.656 | 1 | 0.0 | 0/0 | None |
| game2 | Black | Stockfish (50 ms) | 15 | 0 | 0.8 | 0.933 | 0.008 | 0 | 0.0 | 0/0 | None |

Files per game: `<game>.pgn` (with [%eval] comments), `<game>.json` (every prompt reply, attempt, eval), `<game>.log`, `<game>_replay.mp4`, `<game>_eval.png`, `<game>_key_moments.json`, `frames/<game>/*.png`.
