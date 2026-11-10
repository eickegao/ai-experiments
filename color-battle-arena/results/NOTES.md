# Run notes (kept by hand while the experiment ran, 2026-11-09)

All games: level-3 skills, 3 s between decisions (20 per game), Claude / GPT / Gemini at reasoning effort `low`,
DeepSeek with thinking switched off (at `high` it thought 20k+ tokens and 3-7 minutes per decision; at `medium` still 1-5 min).

| run | what | result | cells | cost | wall-clock |
|---|---|---|---|---|---|
| `2026-11-09_round1_draft_game1_notcounted` | first attempt: models drafted from one-line descriptions, 2 s decisions, effort high, DeepSeek medium | GPT > Gemini > Claude > DeepSeek | 397 / 341 / 175 / 111 | $4.30 | 1 h 26 min |
| `2026-11-09_round1` game 1 | **round 1, no teaching**: everyone gets the same SPLIT / SHOCKWAVE / GIANT, no draft | DeepSeek > Gemini > Claude > GPT | 274 / 264 / 248 / 238 | $0.89 | 3 min |
| `2026-11-09_round2` game 1 | **round 2, taught**: models study `tutorial/tutorial.md`, draft 3 skills | Gemini > GPT > Claude > DeepSeek | 400 / 290 / 201 / 133 | $2.11 (Claude 1.23, GPT 0.65, Gemini 0.14, DeepSeek 0.09) | 4 min 38 s |

Not counted: the first attempt had a bug (BOMB was still "player only" in the engine, so Gemini's 23 bomb casts were
rejected) and DeepSeek's draft reply was cut by the 6k token budget. Kept for the record (`*_notcounted`).

## Round 1 (same skills) observations

- Lead changed hands all game; the decisive moment was the last 3 s: Claude and GPT both cast level-3 GIANT (pierce) at
  t = 57 s and ploughed through DeepSeek's block (353 → 274), lifting themselves by 50-70 cells. DeepSeek still won by 10.
- Everyone cast SHOCKWAVE 4-5 times with no visible edge for anyone.

## Round 2 (taught) observations

- The material was clearly absorbed: three of four picked TELEPORT + SHATTER (+ ACCEL / GIANT) and quoted the tutorial's
  numbers in their reasons. DeepSeek (no thinking) answered with a bare `PICK: giant, fire, shatter` and no teleport.
- **Luck factor to stress in the analysis (user 2026-11-09):** at decision 1 both GPT and Gemini teleported into the same
  spot, (24, 8), inside DeepSeek's quadrant, and cast SHATTER. DeepSeek fell from 256 to 31 cells in 3 s and never
  recovered (133 at the end). That early double hit, plus being the only team without TELEPORT, decided its last place;
  nobody followed the tutorial's "hit the leader" advice at that moment (DeepSeek was not leading).
- The game became a teleport war: swings of 300+ cells within 6 s (Gemini 91 → 429 between decisions 8 and 10).
- Game 2 of this round (seats rotated, seed 1002) was run to see how much of this is chance.

## Cell curves

`charts.py results/<run>` → `game_N_cells.png` (one line per model, casts annotated) and `cells.png`.
