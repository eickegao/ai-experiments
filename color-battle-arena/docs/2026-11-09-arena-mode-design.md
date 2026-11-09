# Arena mode: four LLMs play Color Battle inside the real game (2026-11-09)

Supersedes the headless-only plan in the READMEs. The user's call (2026-11-09): take the real Defold game, put four AIs in
it, let each AI pick its own skills, run the match, record the real game screen for the video.

## Why the game runs the match (not Python)

The first harness ran `cd_sim.lua` headless in Python (lupa) and drew its own frames. Re-running the command log inside the
Defold engine later would risk drift (different Lua build / libm → a bounce lands one cell off → a different game). So the
**game is the only simulation**: the HTML5 build runs the match; a small Python server on localhost does the LLM calls and
keeps the records. Replay for the video is the same wasm build re-running the same command log → identical frames.

## Pieces

```
game/                       standalone Defold project (tools/import_game.py copies it from PlayDoz; arena/ is ours)
  games/clashdoz/arena.lua  arena mode: URL params, HTTP to the server, decision pauses, command log, replay
  games/clashdoz/clashdoz_game.gui_script   two hooks: start_match(opts.arena) and the step loop asks arena.drive()
  games/clashdoz/clashdoz_controller.script start_game{arena=…} → skip cover/prep → start_match
arena_server.py             HTTP server: /draft, /decide, /finish (LLM calls, logging, results JSON)
arena/players.py, prompt.py, prices.py      unchanged (reused by the server)
replay: ?arena=replay&log=<url>             same build re-runs a results JSON; window.__arena_done = 1 at the end
record_match.py             Playwright: open the live URL → wait for __arena_done → fetch results; then open the replay URL
                            with recordVideo → 1080×1920 mp4 (same recipe as PlayDoz tools/render_replay.py)
```

## URL contract (HTML5 only, read with html5.run)

- `?arena=live&server=http://127.0.0.1:8787&seed=1001&game=1` — play one game against the server.
- `?arena=replay&log=http://127.0.0.1:8787/results/<run>/game_1.json` — replay it, no server calls.
- `&speed=1` optional playback factor for replays.

## Live game flow

1. **Draft** — the game GETs `/draft?seed=…&game=…`. The server has already asked each LLM (in parallel) to pick skills from
   the catalogue (all 12 skills, `cd_config.SKILL_IDS`, with the same SKILL_HELP text the game prompt uses, every skill at
   level 1, **3 slots**, order = slot order) and replies `{ "teams": { "A": {"name","model","skills":[{"id","level"}]}, … } }`.
   The game maps A..D → teams 1..4 (`loadout` for team 1, `enemies[t].skills` for 2..4) and starts `sim.new(seed, …)` with
   no bots (`ais = {}`).
2. **Decision every 2 s of game time** (120 fixed steps): the game stops stepping, POSTs `/decide` with
   `{ game, tick, t, time_left, counts, grid (32 strings), balls, skills (slot/id/level/cd/ready), turn_cd, frozen, last_verdicts }`
   and waits (HUD shows "AI thinking…" and the elapsed wall-clock). The server renders each team's observation with
   `prompt.observation`, queries the four models in parallel, parses, and replies
   `{ "cmds": { "A": [ {type,x,y|slot}, … ], … }, "say": { "A": "<reasoning excerpt>", … } }`.
   The game applies the commands through `sim.command` in rotating team order (team (k + decision) mod 4 first), records
   `{ tick, team, cmd, ok }` and the verdicts, then resumes stepping. Game time never advances while models think.
3. **Finish** — when `s.over`, the game POSTs `/finish` with the full command log, verdicts, 10 Hz cell timeline and final
   counts/ranking; the server merges it with the LLM exchanges into `results/<run>/game_N.json` + `.md`, sets the run
   summary, and the game sets `window.__arena_done = 1`.

## Replay flow

`?arena=replay&log=…`: the game fetches the JSON, starts `sim.new(seed, loadouts)` and before each fixed step applies every
logged command whose tick matches (same order as recorded). Verified by comparing final counts with the log
(prints `ARENA_REPLAY_OK` / `ARENA_REPLAY_MISMATCH`). Overlay: team name + model under each colour in the HUD, the latest
reasoning excerpt (`say`) shown as a small caption so the video can cut to it.

## Experiment plan

- Players: Claude Fable 5.1, GPT-6 Astra, Gemini 4 Argon, DeepSeek V4 Pro (keys in `../.env`; Gemini / DeepSeek still to add).
- Draft once per game (models may pick differently when seated elsewhere). 4 games, seeds 1001…1004, seat rotation as before.
- Baseline: the game's own bot ×4 (free) with the same draft rules replaced by random loadouts.
- Everything recorded per call: prompt, raw reply, seconds, tokens, USD.

## Open points

- Determinism inside the wasm build is a given (same binary, same seed, same commands). Not verified against lupa; not needed.
- Decision latency: the live game is frozen while waiting; the recording for the video is the replay, so waiting never shows.
- Public repo: `game/` is the user's shipped game code and art (user's decision 2026-11-09). Not pushed until the user says so.
