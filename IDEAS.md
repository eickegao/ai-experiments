# Experiment backlog

Ideas we've scoped but not run yet. One section per idea; move to its own directory when it starts.

## color-battle-arena: four LLMs play Color Battle (PlayDoz) at once

Started 2026-11-09: see [`color-battle-arena/`](color-battle-arena/). Decisions taken: fourth player DeepSeek (`deepseek-v4-pro`); Google plays `gemini-4-argon` because Gemini 4 Carbon has no public API; round 1 steering only, round 2 with fire / lightning / teleport at level 1. The original scoping notes stay below for the record.

- **Game**: Color Battle (`~/Projects/PlayDoz/PlayDozDefold/games/clashdoz/`, pure-Lua sim `cd_sim.lua`). 32×32 board, 60 s, each team's ball paints the cells it bounces through; most cells wins. Four teams start in four quadrants.
- **Why it fits**: the sim runs headless with LuaJIT (needs a one-line `vmath` stub; a full 4-bot game takes 0.02 s), every action goes through one `command()` API (turn toward a point / cast a skill), and the engine rejects illegal commands itself. The engine is referee and sandbox; the LLMs are remote controls.
- **Players**: Anthropic (Claude Fable 5.1), OpenAI (GPT-6 Astra), Google (Gemini 4 Carbon, missed the chess round), fourth TBD (DeepSeek / xAI / Meta; user decides). Keys for Google and the fourth are needed.
- **Proposed rules**: decision every 2 s of game time (30 decisions per team per game); model wall-clock time recorded but not charged against game time; skills off in round one (steering only), on in round two; each model plays every quadrant once (≥4 games, fixed seeds); the built-in bot as a fifth reference player; log every board state per tick for a Remotion replay with each model's verbatim replies.
- **Prompt**: text board (32×32 ownership), cell counts, own ball position/direction, cooldowns → one command.
- **Open**: fourth player; skills on/off in round one.

## midterm-forecast: can LLMs call the 2026 US midterms better than polls and prediction markets?

Scoped 2026-11-09 from published results, waiting for a go.

- **What happened** (Nov 3, 2026, per AP/CBS/CNN as of Nov 8): Democrats won both chambers; House roughly D 254 / R 162 with a few races uncalled, Senate D 52–54 with Alaska and Mississippi still counting; Democrats flipped Senate seats in KS, IA, TX, OH, ME, NC, SC. Kalshi claims 98% of resolved race markets called correctly, Polymarket 98.4% (self-reported, resolved races only). Wesleyan Media Project: ~$137M spent on 220 AI-generated political ads through Oct 11 (vs <$50K in 2024), 81% of ads / 88% of spend from Republicans, only 27% carried an AI disclaimer, nearly half were deepfakes of real politicians.
- **Experiment**: give several frontier LLMs (Claude Fable 5.1, GPT-6 Astra, Gemini 4 Carbon, DeepSeek…) the same pre-election packet per race (candidates, incumbent, 2024 result, latest public polls as of Nov 2, generic ballot, fundraising) with web tools OFF, and ask for a winner + probability for every Senate, governor and competitive House race. Score against the certified results with hit rate and Brier score; compare with Kalshi/Polymarket day-before prices and the final polling averages. Also test a "no polls" variant (candidates + fundamentals only) to see how much the model knows vs how much it just reads the polls.
- **Contamination guard**: only models whose training cutoff is before 2026-11-03 (check each model card; Fable 5.1 cutoff is 2026-06), tools disabled, prompts logged verbatim. State this limit on screen.
- **Video angle**: "预测市场 98% 对了，AI 能到多少？" plus the AI-ads data as a second chapter (AI 广告 1.37 亿美元、八成来自共和党、结果民主党大胜：钱没买到票). Charts: hit rate and Brier per model vs markets vs polls; map of misses.
- **Data sources to pull**: AP race calls (final), FiveThirtyEight/RealClearPolitics-style polling averages as of Nov 2, Kalshi + Polymarket day-before prices (public), Wesleyan Media Project releases, FEC.
- **Cost**: ~470 races × 4 models × 2 variants ≈ 4k calls, mostly short; estimate $40–80.
- **Open**: which models; whether to include House (470 prompts) or only Senate + governors (~70) for round one.
