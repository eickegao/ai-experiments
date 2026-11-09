# AI Chess Arena · Stockfish (50 ms) vs Random

Verifier: python-chess 1.11.2 for legality, Stockfish 19 depth 10 for evaluation.
Rules: 3 attempts per move, on failure = random; move cap 40, then Stockfish adjudication at ±8 pawns.

## Score: Stockfish (50 ms) 2.0 – 0.0 Random

| Game | White | Black | Result | Termination | Plies |
|---|---|---|---|---|---|
| game1 | Stockfish (50 ms) | Random | 1-0 | checkmate | 31 |
| game2 | Random | Stockfish (50 ms) | 0-1 | checkmate | 34 |

## Per-side stats

| Game | Side | Player | Moves | Illegal attempts | Best-move rate | Avg loss (pawns) | Blunders (≥2) | Avg s/move | Output tokens |
|---|---|---|---|---|---|---|---|---|---|
| game1 | White | Stockfish (50 ms) | 16 | 0 | 0.812 | 0.13 | 0 | 0.0 | 0 |
| game1 | Black | Random | 15 | 2 | 0.2 | 0.781 | 2 | 0.0 | 0 |
| game2 | White | Random | 17 | 1 | 0.235 | 0.609 | 1 | 0.0 | 0 |
| game2 | Black | Stockfish (50 ms) | 17 | 0 | 0.824 | 0.007 | 0 | 0.0 | 0 |

Files per game: `<game>.pgn` (with [%eval] comments), `<game>.json` (every prompt reply, attempt, eval), `<game>.log`, `<game>_replay.mp4`, `<game>_eval.png`, `<game>_key_moments.json`, `frames/<game>/*.png`.
