# Water Sort in the Fog

English · [中文说明](README.zh.md)

Four LLMs each play the same fogged level of PlayDoz's Water Sort (level 286) on their own, in one long conversation, with undo and restart allowed. Made for [**Build with AI**](https://www.youtube.com/@buildwithai2027) and [**独立营业中**](https://www.youtube.com/@独立营业中); more at [videodoz.com](https://videodoz.com).

Status: done (2026-11-17). GPT-6.2 Astra solved the level in 52 pours; the other three did not finish.

## What and why

A fogged Water Sort level hides everything but the top colour of each tube. You cannot plan it from the start: you have to pour to find out what is underneath, back out of dead ends, and remember what you saw. That makes it a test of exploring under missing information and of using memory, not of running a search algorithm.

We list the numbers and do not rank the models.

## The level

Level 286: 14 tubes, 5 layers each, 12 colours (5 layers of each), 12 tubes full and 2 empty. With the whole board visible the shortest solution is **50 pours** (`solve.py`, A* with an admissible heuristic, so 50 is proven optimal).

## Rules given to the models

- `MOVE a b` pours the whole run of same-coloured layers on top of tube a into tube b (empty, or same colour on top; as much as fits).
- Fog: only the top run of each tube is visible, the rest shows as `?`. A pour reveals what it uncovers.
- `UNDO` takes back the last pour (the fog goes back too, as in the game). `RESTART` goes back to the start with the fog back on. The level is the same in every attempt.
- The whole session is one conversation, so everything seen and tried earlier stays in the model's context.
- Limit: 500 pours in total. An illegal or unreadable command changes nothing and is recorded as a foul.

The full system prompt, identical for every model, is in `arena/prompt.py`. It explains the rules and what we record, and gives no strategy.

## What we record

| Number | Meaning |
|---|---|
| total pours | every pour over the session, including undone ones and abandoned attempts |
| undos, restarts, attempts | how much backing out it took |
| solution pours | pours in the attempt that solved the level, undone pours left out |
| over optimal | solution pours minus 50 |
| fouls | illegal or unreadable commands |
| seconds, tokens, USD | per call and in total |

## Verification

The rules are a Python port of the game's own logic (`nutssort_logic.lua` for pouring, `watersort_game.gui_script` for the fog) with unit tests in `tests/`. A solved session is re-checked by replaying its solution on a fresh board. Every model reply is stored verbatim.

## Models

| Vendor | Model ID |
|---|---|
| Anthropic | `claude-fable-5-2` |
| OpenAI | `gpt-6.2-astra` |
| Google | `gemini-4-carbon` |
| DeepSeek | `deepseek-v4-pro` |

The official runs use the lowest thinking setting each API accepts (see Results). Prices are in `arena/prices.py`.

## How to run

```bash
pip install -r requirements.txt
python3 -m pytest -q tests                      # rules, parser, session, resume
python3 solve.py 286 --out results/solver_286.json
python3 run_game.py --player random:1           # free dry run, no API key
python3 run_game.py --player claude --effort medium --budget-usd 30
```

Keys go in the repo-root `.env`. The level data is read from a local checkout of the game (`arena/game.py`, `LEVELS_LUA`); the level itself is also stored in `results/solver_286.json`. Re-running with the same `--out` resumes from the log without repeating paid turns.

## Output files

- `results/<player>-<effort>/turns.jsonl`: header (level, model, system prompt) and one line per turn: what was sent, the raw reply, the parsed command, whether it was accepted, the board, counters, seconds, tokens, cost.
- `results/<player>-<effort>/summary.json`: the numbers in the table above, plus the solution.
- `results/solver_286.json`: the reference solution with the whole board visible.

## Results

Run on 2026-11-17, one session per model. Reference: 50 pours with the whole board visible.

| Model | Thinking setting sent | Solved | Solution pours | Total pours | Undos | Restarts | Fouls | Minutes | USD |
|---|---|---|---|---|---|---|---|---|---|
| gpt-6.2-astra | reasoning effort low | yes, on attempt 17 | 52 (+2) | 348 | 44 | 16 | 0 | 40.7 | 11.57 |
| claude-fable-5-2 | effort low | no, stopped by us | - | 127 | 11 | 6 | 17 (11 of them replies cut off by the output cap) | 96.4 | 23.45 |
| gemini-4-carbon | thinking level low | no, stopped by us | - | 60 | 9 | 2 | 14 (10 of them empty replies) | 47.1 | 1.59 |
| deepseek-v4-pro | thinking on, effort low | no, stopped by us | - | 71 | 22 | 5 | 9 | 93.4 | 1.41 |
| deepseek-v4-pro | thinking off | no, hit the 500-pour limit | - | 500 | 166 | 166 | 6 | 26.9 | 1.97 |

Read these with care:

- **One session per model.** This is one run, not a statistic.
- **Three of the four unsolved sessions were stopped by us** (too slow or too expensive), not by the 500-pour limit. They might have solved the level with more time.
- **Thinking settings.** The plan was "thinking off" for speed. Only DeepSeek can switch it off; Claude Fable 5.2 and GPT-6.2 Astra reject that and bottom out at "low". So the four listed runs use "low", and the thinking-off DeepSeek run is kept as an extra. In that run DeepSeek repeated the same five commands 163 times.
- **Claude and the output cap.** Thinking counts against the reply length. With our 16,000-token cap Claude ran out before writing a command 10 times (recorded as fouls in the raw log; they are ours, not the model's). From turn 159 the cap was 64,000; it then spent the full 64,000 tokens twice in a row, about 12 minutes each, without giving a command, and we stopped it.
- **Gemini** first ran through an AI Studio key at thinking_budget 0 (`gemini-off-stopped-credit-ran-out/`); that project ran out of prepaid credit at turn 108. The listed run is a fresh one through Vertex AI at thinking level low.
- `deepseek-medium-stopped-after-4-turns/` and `pilot/` are timing pilots and not part of the results.

Files: `results/summary.md`, and per run `turns.jsonl` (every board sent, every raw reply), `summary.json`, `attempts.json`.
