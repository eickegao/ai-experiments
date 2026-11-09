# Chess Arena: Anthropic's strongest model vs OpenAI's strongest model

English · [中文说明](README.zh.md)

Two frontier LLMs play chess against each other. Every move is verified independently:

- **Legality**: python-chess applies the rules. An illegal move never reaches the board. Each move gets up to 3 attempts; from the 2nd attempt the list of legal moves is included in the prompt; 3 failures forfeit the game (`--on-illegal random` plays a random legal move instead and keeps going).
- **Quality**: Stockfish 19 (depth 18, 3 principal variations) evaluates the position before and after every move, recording pawns lost, whether the move was Stockfish's top-1 or top-3 choice, and blunders (≥2 pawns lost).
- Games unresolved after 150 moves are adjudicated by Stockfish (±8 pawns = win, otherwise draw).

Both players receive **exactly the same prompt**, and the exchange is pure PGN: the game so far as a PGN record, the model answers with one SAN move. The first attempt does not include a legal-move list, so it measures the model's own chess ability. Players are stateless: one independent request per move, no multi-turn memory.

## Experiment design

Two rounds, two games per round with colors swapped, four games in total (`./run_experiment.sh`):

| Round | Reasoning effort (same for both models) | Question |
|---|---|---|
| round1 | `effort=low` | Can the models play legal, sensible chess when they think little? |
| round2 | `effort=high` | Do illegal moves and blunders drop when they think more? |

There is no time limit (the APIs do not support one), but the **wall-clock time of every attempt is recorded**, along with tokens and cost.

Per side we report: score, illegal attempts, top-1 / top-3 agreement with Stockfish, average pawns lost, blunders, seconds per move, tokens, and cost. `compare_rounds.py` merges the two rounds into one table and one chart.

Caveats stated up front: these are general-purpose language models, not chess engines, and they are far weaker than Stockfish. The point is to see how general models handle a task with exact rules. The full position is sent on every move, nothing relies on chat memory, and every reply is checked by python-chess before it is played.

## Models

| Side | Model ID | Notes |
|---|---|---|
| Anthropic | `claude-fable-5-1` | Thinking always on, `effort=high` / `low` per round |
| OpenAI | `gpt-6-astra` | Responses API, `reasoning.effort=high` / `low` per round |

Override with `--a claude:<id> --b openai:<id>`.

## Running

From the `chess-arena/` directory:

```bash
brew install stockfish librsvg ffmpeg
pip3 install -r requirements.txt
cp ../.env.example ../.env     # keys live at the repo root, shared by all experiments
./run_experiment.sh            # both rounds, four games
python3 run_match.py --a stockfish:50 --b random:0.1 --out results/dryrun   # free pipeline test
python3 run_match.py --render-only results/<dir> --layout portrait          # re-render assets
```

## Output (`results/<timestamp>_<A>_vs_<B>/`)

| File | Contents |
|---|---|
| `gameN.pgn` | Standard PGN with `[%eval]` comments |
| `gameN.json` | Every move: raw model reply, each attempt, seconds, tokens, Stockfish eval before/after, pawns lost, best move, top-3 |
| `gameN_transcript.md` | The full exchange, verbatim: every PGN prompt sent and every model reply, with the verifier’s verdict per attempt |
| `gameN_dialogue.mp4` + `frames_dialogue/gameN/*.png` | The same exchange as video frames: prompt left, reply right, verdict below (one frame per attempt) |
| `gameN.log` | Live log |
| `gameN_replay.mp4` | Replay video (1920×1080: board, eval bar, move, eval, best move, flags) |
| `gameN_eval.png` | Evaluation curve, red dots are blunders |
| `gameN_key_moments.json` | Illegal attempts, blunders, checkmates, forfeits |
| `frames/gameN/*.png` | One frame per ply (not committed, regenerate with `--render-only`) |
| `summary.md` / `summary.json` | Score and per-side stats for the round |
| `../comparison.md` / `comparison.png` | Round-vs-round comparison |

Prices used for cost (USD per million tokens, input / output) are in `arena/prices.py`: both flagships list at $10 / $50 (Anthropic price page; OpenAI developers.openai.com pricing, standard tier, read 2026-11-08).

## Results (2026-11-08, both models at effort=high)

Raw data: [`results/2026-11-08_2051_claude-fable-5-1_vs_gpt-6-astra/`](results/2026-11-08_2051_claude-fable-5-1_vs_gpt-6-astra/) (PGN, JSON with every prompt and reply, transcripts, replay and dialogue videos, eval charts).

**GPT-6 Astra won 2–0, both games by checkmate.**

| Game | White | Black | Result | Plies |
|---|---|---|---|---|
| game1 | Claude Fable 5.1 | GPT-6 Astra | 0–1, checkmate (34... Re1#) | 68 |
| game2 | GPT-6 Astra | Claude Fable 5.1 | 1–0, checkmate (31. Qe8#) | 61 |

| Both games combined | Claude Fable 5.1 | GPT-6 Astra |
|---|---|---|
| Moves played | 64 | 65 |
| Failed attempts (illegal / no move) | 1 (illegal `Rxf3`: its own queen on f2 blocked the rook) | 1 (empty reply: the 4,000-token output budget was spent on reasoning, no move returned) |
| Top-1 agreement with Stockfish | 45.3% | 53.8% |
| Top-3 agreement with Stockfish | 71.9% | 83.1% |
| Average pawns lost per move | 0.68 | 0.38 |
| Blunders (≥2 pawns) | 7 | 5 |
| Thinking time, total | 7 min 6 s (6.7 s/move) | 43 min (39.7 s/move) |
| Tokens in / out | 28,134 / 23,847 | 19,497 / 65,895 |
| Cost (both at $10 / $50 per 1M) | $1.47 | $3.49 |

How the games went:

- **Game 1.** A Sicilian; through move 13 both sides were mostly inside Stockfish's top 3. Claude (White) missed the free pawn `Qxb4` for several moves in a row, GPT blundered with `23...Qf8` (+2.7 for White), Claude gave it straight back with `24.Qf2`, then `26.Qe4` lost 10.8 pawns in one move and the game. GPT mated on move 34.
- **Game 2.** Quiet and level for 17 moves. GPT (White) blundered first with `18.b3` (−6.2), Claude answered with an equal blunder `18...Bd7`, then lost the thread with `20...g6`, `21...Qb7` (−6.6) and `22...d5`. GPT converted cleanly and mated on move 31.
- GPT thought about six times longer per move and spent 2.8× more output tokens; its moves agreed with Stockfish more often and lost fewer pawns. Claude answered in seconds and made more large errors.
- Legality held up: 129 moves were played, only two attempts failed (one each), both recovered on the retry with the legal-move list.

Caveats: two games is a sample, not a verdict. `max_output_tokens=4000` for OpenAI counts reasoning tokens, which caused the one empty reply; a higher cap would avoid it. Both models are far below Stockfish (top-1 agreement around 50%, several multi-pawn blunders per game).
