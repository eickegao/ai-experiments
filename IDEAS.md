# Experiment backlog

Ideas we've scoped but not run yet. One section per idea; move to its own directory when it starts.

## color-battle-arena: four LLMs play Color Battle (PlayDoz) at once

Scoped 2026-11-09, waiting for a go.

- **Game**: Color Battle (`~/Projects/PlayDoz/PlayDozDefold/games/clashdoz/`, pure-Lua sim `cd_sim.lua`). 32×32 board, 60 s, each team's ball paints the cells it bounces through; most cells wins. Four teams start in four quadrants.
- **Why it fits**: the sim runs headless with LuaJIT (needs a one-line `vmath` stub; a full 4-bot game takes 0.02 s), every action goes through one `command()` API (turn toward a point / cast a skill), and the engine rejects illegal commands itself. The engine is referee and sandbox; the LLMs are remote controls.
- **Players**: Anthropic (Claude Fable 5.1), OpenAI (GPT-6 Astra), Google (Gemini 4 Carbon, missed the chess round), fourth TBD (DeepSeek / xAI / Meta; user decides). Keys for Google and the fourth are needed.
- **Proposed rules**: decision every 2 s of game time (30 decisions per team per game); model wall-clock time recorded but not charged against game time; skills off in round one (steering only), on in round two; each model plays every quadrant once (≥4 games, fixed seeds); the built-in bot as a fifth reference player; log every board state per tick for a Remotion replay with each model's verbatim replies.
- **Prompt**: text board (32×32 ownership), cell counts, own ball position/direction, cooldowns → one command.
- **Open**: fourth player; skills on/off in round one.
