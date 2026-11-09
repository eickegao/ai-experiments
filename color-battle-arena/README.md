# Color Battle Arena: four frontier LLMs play a real-time territory game

English · [中文说明](README.zh.md)

Four language models each remote-control a ball in **Color Battle**, a 60-second, four-player territory game from [PlayDoz](https://playdoz.com). The game engine is the referee and the sandbox: every action goes through the game's own `command()` API, illegal commands are rejected by the engine itself, and the world only advances through the game's fixed-step simulation. The models never touch the state; they only read a text picture of the board and answer with a command.

Status: **harness ready, experiment not yet run** (2026-11-09). Results will be added below.

## The game

- 32×32 board, four teams start in the four quadrants (256 cells each). Each team has one ball moving at 22 cells/s.
- A ball passes freely over its own colour. When it touches a cell of any other colour it paints that cell and bounces back. Balls also bounce off the board edges.
- 60 seconds. Most cells wins.
- A player can point the ball at any spot (1 s cooldown) and, in the skills round, cast three level-1 skills: **FIRE** (paint a circle of radius 2 at a point, cd 12 s), **LIGHTNING** (paint a cross from the ball to the four edges, cd 14 s), **TELEPORT** (jump the ball anywhere, cd 28 s).

## Experiment design

- **Players**: four models, one per quadrant, plus a free baseline of the game's own scripted bot (`cd_ai.lua`).
- **Decisions**: every 2 seconds of game time (30 per game). Game time is frozen while the models think, so thinking time is recorded but never costs board time. All four models are queried in parallel at each decision.
- **What a model sees**: the board as 32 rows of characters (`.` neutral, `A`–`D` owner, lowercase letter = that team's ball, `@` = its own ball), cell counts, its ball's position and heading, cooldowns, and the verdict on its previous command. Nothing else: no history, no hints. Each decision is a fresh stateless request with the same system prompt for everyone (`arena/prompt.py`).
- **What a model answers**: up to two lines, `CMD: TURN x y`, `CMD: CAST slot [x y]` or `CMD: WAIT`. Anything the engine rejects (cooldown, off-board, frozen) is ignored and reported back next turn; a reply with no valid command line does nothing.
- **Rounds**: round 1 steering only; round 2 with the three skills above, identical for every team. Four games per round with fixed seeds; game g seats model k in quadrant (k + g) mod 4, so every model starts in every corner once. Within a decision the order in which commands are applied rotates too.
- **Reasoning depth**: the provider's "high" for everyone (Anthropic `effort`, OpenAI `reasoning.effort`, Gemini `thinking_level`, DeepSeek `reasoning_effort` with thinking enabled).
- **Recorded per call**: the exact prompt, the raw reply, wall-clock seconds, tokens, USD cost (DeepSeek converted from CNY with its peak / off-peak schedule), and whether each command was accepted.
- **Reproducible replay**: the simulation is deterministic given the seed, the loadout and the command log, so `replay.py` re-creates every frame of every game from the JSON alone and verifies the final cell counts match the recording.

## Models

| Player | Model ID | Vendor | Price (USD / 1M tokens, in / out) | Note |
|---|---|---|---|---|
| Claude | `claude-fable-5-1` | Anthropic | 10 / 50 | Anthropic's top tier |
| GPT | `gpt-6-astra` | OpenAI | 10 / 50 | OpenAI's flagship |
| Gemini | `gemini-4-argon` | Google | 2 / 10 (doubles 2026-12-01) | Google's flagship **callable through the public API**. Gemini 4 Carbon leads the leaderboards but had no public API model ID on 2026-11-09 (pre-release testers only). |
| DeepSeek | `deepseek-v4-pro` | DeepSeek | ≈ 1.27 / 3.80 peak, half off-peak (CNY 9 / 27 and 4.5 / 13.5 at 7.1 CNY/USD) | Serves DeepSeek-V4-Pro-0813, thinking on |

Prices read 2026-11-09 from each vendor's pricing page; see `arena/prices.py`.

## How to run

```sh
pip install -r requirements.txt            # lupa (Lua in Python), the four SDKs, pillow, matplotlib
cp ../.env.example ../.env                 # ANTHROPIC_API_KEY, OPENAI_API_KEY, GEMINI_API_KEY, DEEPSEEK_API_KEY
export PLAYDOZ_DIR=~/Projects/PlayDoz/PlayDozDefold   # where games/clashdoz/cd_sim.lua lives (default shown)

python3 run_match.py --players random,random,bot,bot --games 1 --skills on --out results/dry   # free dry run
./run_experiment.sh                        # round 1 (steering), round 2 (skills), bot baseline, replay check
python3 replay.py results/<dir>            # frames for the video + cells-over-time chart
```

The simulation source (`cd_sim.lua`, `cd_ai.lua`, `cd_config.lua`, `cd_rng.lua`) is the shipped PlayDoz game code and is read from `PLAYDOZ_DIR`; the harness adds only a two-line Defold `vmath` stub.

## Output files

Under `results/<timestamp>_<round>/`:

- `game_N.json`: every decision (board snapshot, each model's prompt, raw reply, parsed commands and verdicts, seconds, tokens, cost), the full command log with tick indices, a 10 Hz cell-count timeline, skill events, final ranking.
- `game_N.md`: readable transcript of every exchange.
- `summary.json` / `summary.md`: per-model aggregate across games (wins, average rank, cells, seconds per decision, rejected / missing commands, tokens, cost).
- `timeline.png`: cells over time per game; `frames/game_N/` (gitignored, regenerate with `replay.py`): 1920×1080 frames at 30 fps.

## Results

Not run yet.

## Credits

Game: Color Battle from [PlayDoz](https://playdoz.com), simulation by the same author. Videos: [**Build with AI**](https://www.youtube.com/@buildwithai2027) · [**独立营业中**](https://www.youtube.com/@独立营业中). License: MIT (see repo root).
