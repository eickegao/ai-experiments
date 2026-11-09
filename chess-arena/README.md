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

## Results

To be filled in after the match.
