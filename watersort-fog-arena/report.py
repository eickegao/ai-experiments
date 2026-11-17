#!/usr/bin/env python3
"""Build results/summary.md (the numbers side by side) and results/<run>/attempts.json (one row per attempt: how many
pours, undos, how it ended) from the session logs. Reads logs only, costs nothing.

Usage: python3 report.py claude-off openai-off gemini-off deepseek-off
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def load(run: str):
    rows = [json.loads(ln) for ln in (HERE / "results" / run / "turns.jsonl").read_text().splitlines() if ln.strip()]
    return rows[0], [r for r in rows[1:] if r["type"] == "turn"], [r for r in rows[1:] if r["type"] == "api_error"]


def attempts(turns: list[dict]) -> list[dict]:
    """Split the session at each RESTART."""
    out, cur = [], {"attempt": 1, "first_turn": 1, "pours": 0, "undos": 0, "fouls": 0, "seconds": 0.0}
    for t in turns:
        cmd = t["cmd"]
        cur["seconds"] += t["seconds"]
        if not t["accepted"]:
            cur["fouls"] += 1
        elif cmd[0] == "move":
            cur["pours"] += 1
        elif cmd[0] == "undo":
            cur["undos"] += 1
        elif cmd[0] == "restart":
            cur.update(ended="restart", last_turn=t["turn"], standing_pours=cur["pours"] - cur["undos"])
            out.append(cur)
            cur = {"attempt": t["attempt"], "first_turn": t["turn"] + 1, "pours": 0, "undos": 0, "fouls": 0, "seconds": 0.0}
        if t["won"]:
            cur.update(ended="solved", last_turn=t["turn"], standing_pours=t["path_len"])
    if "ended" not in cur:
        cur.update(ended="unfinished", last_turn=turns[-1]["turn"] if turns else 0, standing_pours=cur["pours"] - cur["undos"])
    out.append(cur)
    for a in out:
        a["seconds"] = round(a["seconds"], 1)
    return out


def main(runs: list[str]):
    solver = json.loads((HERE / "results" / "solver_286.json").read_text())
    lines = ["# Results: level 286, fogged", "",
             f"Reference: with the whole board visible the shortest solution is **{solver['moves']} pours** (proven optimal).", "",
             "| Model | Thinking setting sent | Solved | Solution pours | Over optimal | Total pours | Undos | Restarts | Attempts | Fouls | Turns | Minutes | USD |",
             "|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for run in runs:
        head, turns, errs = load(run)
        summ = json.loads((HERE / "results" / run / "summary.json").read_text())
        att = attempts(turns)
        (HERE / "results" / run / "attempts.json").write_text(json.dumps(att, indent=1))
        sol = summ.get("solution_pours")
        how = "yes" if summ["solved"] else f"no ({summ['status']})"
        cost = f"{summ['cost_usd']:.2f}" if summ["cost_usd"] is not None else "?"
        lines.append(f"| {head['model']} | {head.get('thinking_sent', head['effort'])} | {how} | {sol or '-'} | "
                     f"{'+' + str(sol - solver['moves']) if sol else '-'} | {summ['total_pours']} | {summ['undos']} | {summ['restarts']} | "
                     f"{summ['attempts']} | {summ['fouls']} | {summ['turns']} | {summ['seconds'] / 60:.1f} | {cost} |")
    lines += ["", "Total pours counts every pour of the session, including undone ones and abandoned attempts. "
              "Solution pours is the length of the attempt that solved the level, undone pours left out. "
              "Minutes is model response time only."]
    (HERE / "results" / "summary.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main(sys.argv[1:] or ["claude-off", "openai-off", "gemini-off", "deepseek-off"])
