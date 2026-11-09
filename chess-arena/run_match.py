#!/usr/bin/env python3
"""AI chess match: two players, each plays once as White and once as Black. python-chess checks legality, Stockfish scores every move.

Usage (from chess-arena/; keys in the repo-root AIExperiments/.env: ANTHROPIC_API_KEY / OPENAI_API_KEY):
  python3 run_match.py                                  # Claude (claude-fable-5-1) vs OpenAI (gpt-6-astra), two games
  python3 run_match.py --a claude:claude-opus-5-5 --b openai:gpt-6.1-terra
  python3 run_match.py --a stockfish:50 --b random:0.1 --games 2 --out results/dryrun   # free pipeline test
  python3 run_match.py --render-only results/2026-11-08_xxx                             # re-render frames/video/charts only

Output in results/<timestamp>_<a>_vs_<b>/:
  game1.pgn / game1.json / game1.log   full record (every raw reply, attempt, Stockfish eval per move)
  game1_transcript.md / game1_dialogue.mp4   the full PGN exchange, verbatim, as text and as frames
  game1_replay.mp4 / game1_eval.png / game1_key_moments.json / frames/game1/*.png   video assets
  summary.md / summary.json            round summary
"""
from __future__ import annotations

import argparse
import datetime as dt
import glob
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from arena.engine import Engine
from arena.game import Game
from arena.players import make_player
from arena.dialogue import render_dialogue
from arena.render import render_game
from transcript import transcript


def load_env():
    """Keys live in the repo-root AIExperiments/.env (shared by all experiments); an experiment-local .env is also read and wins. Neither is committed."""
    here = os.path.dirname(os.path.abspath(__file__))
    for p in (os.path.join(here, ".env"), os.path.join(os.path.dirname(here), ".env")):
        if os.path.exists(p):
            for line in open(p, encoding="utf-8"):
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def slug(s: str) -> str:
    return re.sub(r"[^A-Za-z0-9.]+", "-", s).strip("-")


def summarize(out_dir: str, games: list[dict], a_name: str, b_name: str) -> None:
    score = {a_name: 0.0, b_name: 0.0}
    rows = []
    for g in games:
        w, b = g["white"]["name"], g["black"]["name"]
        r = g["result"]
        if r == "1-0":
            score[w] += 1
        elif r == "0-1":
            score[b] += 1
        else:
            score[w] += 0.5; score[b] += 0.5
        rows.append(g)
    lines = [f"# AI Chess Arena · {a_name} vs {b_name} · effort={games[0].get('effort')}", "",
             f"Verifier: {games[0]['verifier']['legality']} for legality, {games[0]['verifier']['eval']} for evaluation.",
             f"Rules: {games[0]['rules']['max_attempts']} attempts per move, on failure = {games[0]['rules']['on_illegal']}; "
             f"move cap {games[0]['rules']['max_plies'] // 2}, then Stockfish adjudication at ±{games[0]['rules']['adjudicate_cp'] / 100:.0f} pawns.", "",
             f"## Score: {a_name} {score[a_name]} – {score[b_name]} {b_name}", "",
             "| Game | White | Black | Result | Termination | Plies |", "|---|---|---|---|---|---|"]
    for g in rows:
        lines.append(f"| {g['name']} | {g['white']['name']} | {g['black']['name']} | {g['result']} | {g['termination']} | {g['plies_total']} |")
    lines += ["", "## Per-side stats", "", "| Game | Side | Player | Moves | Illegal attempts | Top-1 rate | Top-3 rate | Avg loss (pawns) | Blunders (≥2) | Avg s/move | Tokens in/out | Cost USD |", "|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for g in rows:
        for side in ("White", "Black"):
            s = g["stats"][side]
            who = g["white"]["name"] if side == "White" else g["black"]["name"]
            lines.append(f"| {g['name']} | {side} | {who} | {s['moves']} | {s['illegal_attempts']} | {s['best_move_rate']} | {s['top3_rate']} | {s['avg_loss_pawns']} | {s['blunders_2pawns']} | {s['avg_seconds']} | {s['tokens_in']}/{s['tokens_out']} | {s['cost_usd']} |")
    lines += ["", "Files per game: `<game>.pgn` (with [%eval] comments), `<game>.json` (every prompt reply, attempt, eval), `<game>.log`, `<game>_replay.mp4`, `<game>_eval.png`, `<game>_key_moments.json`, `frames/<game>/*.png`."]
    open(os.path.join(out_dir, "summary.md"), "w", encoding="utf-8").write("\n".join(lines) + "\n")
    json.dump({"score": score, "games": [{k: g[k] for k in ("name", "white", "black", "result", "termination", "plies_total", "stats")} for g in rows]},
              open(os.path.join(out_dir, "summary.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("\n".join(lines[:12]))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--a", default="claude", help="player A: claude[:model] | openai[:model] | stockfish[:ms] | random[:illegal_rate]")
    ap.add_argument("--b", default="openai")
    ap.add_argument("--games", type=int, default=2, help="number of games; A is White in odd games, B in even games")
    ap.add_argument("--effort", default="high", help="reasoning effort for both models: low|medium|high")
    ap.add_argument("--attempts", type=int, default=3, help="max attempts per move")
    ap.add_argument("--on-illegal", choices=["forfeit", "random"], default="forfeit", help="when attempts run out: forfeit the game, or play a random legal move")
    ap.add_argument("--max-moves", type=int, default=150, help="move cap; Stockfish adjudicates when reached")
    ap.add_argument("--depth", type=int, default=18, help="Stockfish analysis depth")
    ap.add_argument("--stockfish", default=None, help="path to the stockfish binary")
    ap.add_argument("--out", default=None)
    ap.add_argument("--render-only", default=None, help="only re-render frames/video/charts for an existing results dir")
    ap.add_argument("--layout", choices=["landscape", "portrait"], default="landscape", help="asset format: landscape 1920x1080 (default) or portrait 1080x1350")
    a = ap.parse_args()
    load_env()

    if a.render_only:
        for j in sorted(glob.glob(os.path.join(a.render_only, "game*.json"))):
            if not re.fullmatch(r"game\d+\.json", os.path.basename(j)):
                continue
            print(render_game(j, layout=a.layout))
            open(j[:-5] + "_transcript.md", "w", encoding="utf-8").write(transcript(j))
            print(render_dialogue(j))
        return

    engine = Engine(a.stockfish, a.depth)
    A = make_player(a.a, engine, a.effort)
    B = make_player(a.b, engine, a.effort)
    out_dir = a.out or os.path.join("results", f"{dt.datetime.now():%Y-%m-%d_%H%M}_{slug(A.model)}_vs_{slug(B.model)}")
    os.makedirs(out_dir, exist_ok=True)
    print(f"output dir {out_dir}")

    games = []
    try:
        for i in range(1, a.games + 1):
            white, black = (A, B) if i % 2 == 1 else (B, A)
            g = Game(white, black, engine, out_dir, f"game{i}", a.attempts, a.on_illegal, a.max_moves * 2).play()
            games.append(g)
            r = render_game(os.path.join(out_dir, f"game{i}.json"), layout=a.layout)
            open(os.path.join(out_dir, f"game{i}_transcript.md"), "w", encoding="utf-8").write(transcript(os.path.join(out_dir, f"game{i}.json")))
            print(f"  dialogue video: {render_dialogue(os.path.join(out_dir, f'game{i}.json'))}")
            print(f"  assets: {r['frames']} frames, {r['replay']}, {r['chart']}, {len(r['key_moments'])} key moments")
    finally:
        engine.close()
    summarize(out_dir, games, A.name, B.name)


if __name__ == "__main__":
    main()
