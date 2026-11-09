# Color Battle Arena: four frontier LLMs play a real-time territory game, inside the real game

English · [中文说明](README.zh.md)

Four language models each remote-control a ball in **Color Battle**, a 60-second, four-player territory game from
[PlayDoz](https://playdoz.com). The match runs **in the shipped game itself** (a trimmed copy of the Defold project, built
for the web): every action goes through the game's own `command()` API, illegal commands are rejected by the engine, and
the world only advances through the game's fixed-step simulation. Before the match each model **drafts its own skills**
from the game's list. The models never touch the state; they read a text picture of the board and answer with a command.

Status: **harness ready, experiment not yet run** (2026-11-09). Results will be added below.

## The game

- 32×32 board, four teams start in the four quadrants (256 cells each). Each team has one ball moving at 22 cells/s.
- A ball passes freely over its own colour. When it touches a cell of any other colour it paints that cell and bounces back.
  Balls also bounce off the board edges. 60 seconds. Most cells wins.
- A player can point the ball at any spot (1 s cooldown) and cast the skills it drafted (each with its own cooldown).
- Twelve skills to draft from (all level 1): FREEZE, SPLIT, ACCEL, BOMB, GIANT, FIRE, LIGHTNING, TELEPORT, SHATTER,
  SHOCKWAVE, CHAIN LIGHTNING, PLASMA. Each team picks three. The exact numbers (radius, duration, cooldown) are in
  `game/games/clashdoz/cd_config.lua` and are quoted to the models verbatim in the draft prompt.

## Experiment design

- **Players**: four models, one per quadrant, plus a free baseline of the game's own scripted bot (`cd_ai.lua`).
- **Draft**: before the game each model gets the same skill list with the same one-line descriptions and picks three
  (`PICK: a, b, c`). Bots and random players roll three at random.
- **Decisions**: every 2 seconds of game time (30 per game). Game time is frozen while the models think, so thinking time
  is recorded but never costs board time. All four models are queried in parallel at each decision.
- **What a model sees**: the board as 32 rows of characters (`.` neutral, `A`–`D` owner, lowercase letter = that team's
  ball, `@` = its own ball), cell counts, its ball's position and heading, cooldowns, and the engine's verdict on its
  previous commands. Nothing else: no history, no hints. Each decision is a fresh stateless request; the system prompt is
  identical for everyone except the list of the team's own drafted skills (`arena/prompt.py`).
- **What a model answers**: up to two lines, `CMD: TURN x y`, `CMD: CAST slot [x y]` or `CMD: WAIT`. Anything the engine
  rejects (cooldown, off-board, frozen) is ignored and reported back next turn; a reply with no valid command does nothing.
- **Four games** with fixed seeds (1001…1004); in game g player k sits in quadrant (k + g − 1) mod 4, so every model starts
  in every corner once. Within a decision the order in which commands are applied rotates too.
- **Reasoning depth**: the provider's "high" for everyone (Anthropic `effort`, OpenAI `reasoning.effort`, Gemini
  `thinking_level`, DeepSeek `reasoning_effort` with thinking enabled).
- **Recorded per call**: the exact prompt, the raw reply, wall-clock seconds, tokens, USD cost (DeepSeek converted from CNY
  with its peak / off-peak schedule), and whether each command was accepted.
- **Reproducible replay**: the game logs every accepted and rejected command with its tick. The same web build replays the
  log (`?arena=replay`) and checks the final cell counts against the record (`ARENA_REPLAY_OK` in the console), so the
  video footage is the real game re-running the real match, frame for frame.

## Models

| Player | Model ID | Vendor | Price (USD / 1M tokens, in / out) | Note |
|---|---|---|---|---|
| Claude | `claude-fable-5-1` | Anthropic | 10 / 50 | Anthropic's top tier |
| GPT | `gpt-6-astra` | OpenAI | 10 / 50 | OpenAI's flagship |
| Gemini | `gemini-4-argon` | Google | 2 / 10 (doubles 2026-12-01) | Google's flagship **callable through the public API**. Gemini 4 Carbon leads the leaderboards but had no public API model ID on 2026-11-09 (pre-release testers only). |
| DeepSeek | `deepseek-v4-pro` | DeepSeek | ≈ 1.27 / 3.80 peak, half off-peak (CNY 9 / 27 and 4.5 / 13.5 at 7.1 CNY/USD) | Serves DeepSeek-V4-Pro-0813, thinking on |

Prices read 2026-11-09 from each vendor's pricing page; see `arena/prices.py`.

## How it is built

```
game/                 standalone Defold project = the match screen of Color Battle (tools/import_game.py copies it from the
                      PlayDoz monorepo; cover, skill shop, levels, coins, result pages and 12 languages left out; one BGM)
game/games/clashdoz/arena.lua   arena mode (source: arena_game/arena.lua): URL params, draft, decision pauses, command log, replay
arena_server.py       localhost server: serves the web build and answers /draft, /decide, /finish; does all LLM calls and logging
arena/                players (one class per vendor), prompt + parser, prices
record_match.py       Playwright: runs one live game headless, then records the replay as a 1080×1920 mp4
tools/                import_game.py (re-create game/ from PlayDoz), web_smoke.py (headless screenshot of the bundle)
docs/                 design notes
```

## How to run

```sh
pip install -r requirements.txt            # the four SDKs, playwright (uses the installed Google Chrome), pillow, matplotlib
cp ../.env.example ../.env                 # ANTHROPIC_API_KEY, OPENAI_API_KEY, GEMINI_API_KEY, DEEPSEEK_API_KEY

# build the web bundle (Defold's bob.jar + the JDK shipped with the Defold editor; any JDK 21+ works)
JAVA=$(ls -d /Applications/Defold.app/Contents/Resources/packages/jdk-*/bin/java | tail -1)
(cd game && $JAVA -jar /path/to/bob.jar --platform wasm-web --architectures wasm-web --variant release --archive --bundle-output build_web resolve build bundle)

python3 arena_server.py --players random,random,bot,bot --out results/dry &      # free dry run
python3 record_match.py --game 1 --out results/dry                               # live game + replay mp4

./run_experiment.sh                        # the real thing: four games Claude / GPT / Gemini / DeepSeek + bot baseline
```

`game/` is a copy of the game's shipped code and art, included so the experiment is reproducible; the simulation
(`cd_sim.lua`) is byte-for-byte the one players get in the store build.

## Output files

Under `results/<run>/`:

- `game_N.json`: the draft (prompts, replies, picks), every decision (board snapshot, each model's prompt, raw reply,
  parsed commands and the engine's verdicts, seconds, tokens, cost), the full tick-indexed command log, a 10 Hz
  cell-count timeline, final ranking, per-player totals.
- `game_N.md`: readable transcript of every exchange. `game_N.mp4`: the replay, recorded from the real game (1080×1920).
- `summary.json` / `summary.md`: per-player aggregate across games (wins, average place, cells, seconds per decision,
  rejected / silent turns, casts, tokens, cost, drafted skills).

## Results

Not run yet.

## Credits

Game: Color Battle from [PlayDoz](https://playdoz.com), simulation by the same author. Videos: [**Build with AI**](https://www.youtube.com/@buildwithai2027) · [**独立营业中**](https://www.youtube.com/@独立营业中). License: MIT (see repo root).
