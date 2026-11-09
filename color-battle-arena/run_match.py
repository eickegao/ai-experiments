#!/usr/bin/env python3
"""Run a set of Color Battle games between four players and write everything under results/<dir>/.

Examples
  python3 run_match.py --players random,random,bot,bot --games 1 --out results/dry          # free dry run
  python3 run_match.py --players claude,openai,gemini,deepseek --games 4 --skills off --out results/2026-11-10_round1
  python3 run_match.py --players claude,openai,gemini,deepseek --games 4 --skills on  --out results/2026-11-10_round2

With --rotate (default) game g seats player k in quadrant (k + g) mod 4, so every model starts in every corner once.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from arena.game import run_game, transcript_md  # noqa: E402
from arena.players import make_player  # noqa: E402
from arena.sim import LETTERS  # noqa: E402

DEFAULT_SKILLS = [("fire", 1), ("lightning", 1), ("teleport", 1)]


def load_env():
    p = Path(__file__).resolve().parent.parent / ".env"
    if p.exists():
        for line in p.read_text().splitlines():
            if "=" in line and not line.strip().startswith("#"):
                k, _, v = line.partition("=")
                os.environ.setdefault(k.strip(), v.strip())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--players", default="claude,openai,gemini,deepseek", help="four comma-separated specs (see arena/players.py)")
    ap.add_argument("--games", type=int, default=4)
    ap.add_argument("--seeds", default="", help="comma-separated; default 1001.. (one per game)")
    ap.add_argument("--skills", default="off", help="off | on (fire,lightning,teleport at level 1) | comma list of skill ids")
    ap.add_argument("--effort", default="high")
    ap.add_argument("--decision", type=float, default=2.0, help="seconds of game time between decisions")
    ap.add_argument("--no-rotate", action="store_true")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    load_env()

    specs = a.players.split(",")
    if len(specs) != 4:
        raise SystemExit("need exactly four players")
    if a.skills == "off":
        skills = None
    elif a.skills == "on":
        skills = DEFAULT_SKILLS
    else:
        skills = [(s.strip(), 1) for s in a.skills.split(",")]
    seeds = [int(s) for s in a.seeds.split(",")] if a.seeds else [1001 + g for g in range(a.games)]
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    base = [make_player(s, a.effort, seed=k, slots=len(skills or [])) for k, s in enumerate(specs)]

    games = []
    for g in range(a.games):
        players = {}
        for k, p in enumerate(base):
            team = ((k + g) % 4 if not a.no_rotate else k) + 1
            players[team] = p
        print(f"Game {g + 1}/{a.games} seed {seeds[g]}: " + ", ".join(f"{LETTERS[t-1]}={players[t].name}" for t in sorted(players)))
        rec = run_game(players, seeds[g], skills, a.decision, str(out / f"game_{g + 1}.json"))
        (out / f"game_{g + 1}.md").write_text(transcript_md(rec))
        print(f"  result: {' > '.join(rec['final']['ranking'])}  cells " + " ".join(f"{L}={rec['final']['counts'][k+1]}" for k, L in enumerate(LETTERS)))
        games.append(rec)

    # per-model aggregate across games (a model sits in a different seat each game)
    agg = {}
    for rec in games:
        for L, tot in rec["totals"].items():
            m = agg.setdefault(rec["players"][L]["name"], {"model": tot["model"], "games": 0, "wins": 0, "ranks": [], "cells": [],
                                                           "seconds": 0, "input_tokens": 0, "output_tokens": 0, "cost_usd": 0,
                                                           "commands": 0, "rejected": 0, "no_command": 0, "errors": 0, "casts": 0})
            m["games"] += 1
            m["wins"] += rec["final"]["winner"] == L
            m["ranks"].append(rec["final"]["ranking"].index(L) + 1)
            m["cells"].append(tot["final_cells"])
            for k in ("seconds", "input_tokens", "output_tokens", "cost_usd", "commands", "rejected", "no_command", "errors", "casts"):
                m[k] += tot[k]
        for L, p in rec["players"].items():
            if not p["llm"]:
                m = agg.setdefault(p["name"], {"model": p["model"], "games": 0, "wins": 0, "ranks": [], "cells": [], "bot": True})
                m["games"] += 1
                m["wins"] += rec["final"]["winner"] == L
                m["ranks"].append(rec["final"]["ranking"].index(L) + 1)
                m["cells"].append(rec["final"]["counts"][LETTERS.index(L) + 1])
    for m in agg.values():
        m["avg_rank"] = round(sum(m["ranks"]) / len(m["ranks"]), 2)
        m["avg_cells"] = round(sum(m["cells"]) / len(m["cells"]), 1)
        if "seconds" in m:
            n = sum(1 for _ in range(m["games"])) * games[0]["n_decisions"]
            m["avg_seconds_per_decision"] = round(m["seconds"] / max(1, n), 1)
            m["cost_usd"] = round(m["cost_usd"], 3)
    summary = {"players": specs, "games": len(games), "seeds": seeds, "skills": skills or [], "effort": a.effort,
               "decision_dt": a.decision, "results": [{"seed": r["seed"], "players": {L: p["name"] for L, p in r["players"].items()},
                                                       "ranking": r["final"]["ranking"], "counts": r["final"]["counts"]} for r in games],
               "aggregate": agg}
    (out / "summary.json").write_text(json.dumps(summary, indent=1, ensure_ascii=False))
    (out / "summary.md").write_text(summary_md(summary))
    print((out / "summary.md").read_text())


def summary_md(s: dict) -> str:
    out = [f"# Color Battle arena — {s['games']} games, {'skills: ' + ', '.join(i for i, _ in s['skills']) if s['skills'] else 'steering only'}, effort {s['effort']}", ""]
    out.append("| Game | seed | A | B | C | D | ranking |")
    out.append("|---|---|---|---|---|---|---|")
    for g, r in enumerate(s["results"], 1):
        cells = {L: r["counts"][str(k + 1)] if str(k + 1) in r["counts"] else r["counts"][k + 1] for k, L in enumerate(LETTERS)}
        out.append(f"| {g} | {r['seed']} | " + " | ".join(f"{r['players'][L]} ({cells[L]})" for L in LETTERS) + f" | {' > '.join(r['ranking'])} |")
    out.append("")
    out.append("| Player | wins | avg rank | avg cells | s / decision | rejected | no cmd | errors | casts | tokens in / out | cost USD |")
    out.append("|---|---|---|---|---|---|---|---|---|---|---|")
    for name, m in sorted(s["aggregate"].items(), key=lambda kv: kv[1]["avg_rank"]):
        if m.get("bot"):
            out.append(f"| {name} | {m['wins']} | {m['avg_rank']} | {m['avg_cells']} | — | — | — | — | — | — | — |")
        else:
            out.append(f"| {name} | {m['wins']} | {m['avg_rank']} | {m['avg_cells']} | {m['avg_seconds_per_decision']} | {m['rejected']}/{m['commands']} | {m['no_command']} | {m['errors']} | {m['casts']} | {m['input_tokens']:,} / {m['output_tokens']:,} | {m['cost_usd']} |")
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    main()
