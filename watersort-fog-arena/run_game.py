#!/usr/bin/env python3
"""Let one model play a fogged Water Sort level in a single conversation.

  python3 run_game.py --player random:1                      # free dry run, no API key
  python3 run_game.py --player claude --effort medium        # paid
  python3 run_game.py --player openai --stop-after-turns 10 --out results/pilot/openai-medium   # short timing pilot

Re-running with the same --out resumes from the log (results/<out>/turns.jsonl) without repeating paid turns.
Players: claude | openai | gemini | deepseek, optionally :<model id>; random[:seed]. Keys: repo-root .env.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from arena.game import load_level
from arena.players import make_player
from arena.session import Session

HERE = Path(__file__).resolve().parent


def load_env():
    p = HERE.parent / ".env"
    if p.exists():
        for line in p.read_text().splitlines():
            if "=" in line and not line.lstrip().startswith("#"):
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--player", required=True)
    ap.add_argument("--effort", default="medium", help="reasoning effort, same word for every vendor (medium | high)")
    ap.add_argument("--level", type=int, default=286)
    ap.add_argument("--max-pours", type=int, default=500)
    ap.add_argument("--max-turns", type=int, default=1500, help="hard stop on model replies (fouls, undos and restarts count here)")
    ap.add_argument("--stop-after-turns", type=int, help="pause after this many turns in total (timing pilots); resume later with the same --out")
    ap.add_argument("--budget-usd", type=float, help="pause once this session has cost this much (resume later with the same --out)")
    ap.add_argument("--out", help="output directory (default results/<player>-<effort>)")
    a = ap.parse_args()

    load_env()
    cap, tubes, fog = load_level(a.level)
    if not fog:
        print(f"note: level {a.level} is not a fog level in the game; playing it fogged anyway")
    player = make_player(a.player, a.effort)
    out = Path(a.out) if a.out else HERE / "results" / f"{a.player.replace(':', '-')}-{a.effort}"
    s = Session(a.level, cap, tubes, player, a.effort, out / "turns.jsonl", a.max_pours, a.max_turns)
    solver = HERE / "results" / f"solver_{a.level}.json"
    optimal = json.loads(solver.read_text()).get("moves") if solver.exists() else None

    print(f"{player.name} @ {a.effort} on level {a.level} → {out}  (resuming at turn {s.turns + 1})" if s.turns else
          f"{player.name} @ {a.effort} on level {a.level} → {out}")
    while s.status == "running" and not (a.stop_after_turns and s.turns >= a.stop_after_turns):
        if a.budget_usd is not None and (s.cost >= a.budget_usd or not s.cost_known):
            print(f"budget reached (${s.cost:.2f}) or a call had no known price: pausing")
            break
        if not s.step():
            break
        last = s.messages[-2]["content"] if s.status == "running" else s.messages[-1]["content"]
        g = s.game
        print(f"turn {s.turns:>4} | attempt {g.attempts} | pours {g.pours:>3} | undos {g.undos} | fouls {s.fouls} | "
              f"{s.seconds / s.turns:5.1f}s/turn | ${s.cost:.2f} | {last.strip().splitlines()[-1][:40]}", flush=True)
    summ = s.summary(optimal)
    if s.status == "running":
        summ["status"] = "paused"
    (out / "summary.json").write_text(json.dumps(summ, indent=1))
    print(json.dumps({k: v for k, v in summ.items() if k != "solution"}, indent=1))


if __name__ == "__main__":
    main()
