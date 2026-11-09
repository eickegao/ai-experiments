"""One game: four players, 60 s of game time, a decision every `decision_dt` seconds of game time.

Game time is frozen while the models think (the simulation only advances between decisions), so thinking time is
recorded but never costs a player board time. All LLM players are queried in parallel at each decision.
"""
from __future__ import annotations

import json
import os
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

from .players import Player
from .prices import call_cost
from .prompt import fmt_cmd, observation, parse, system_prompt
from .sim import FIXED_DT, LETTERS, ROUND_TIME, ColorBattle


def run_game(players: dict[int, Player], seed: int, skills: list[tuple[str, int]] | None, decision_dt: float = 2.0,
             out_path: str | None = None, log=print) -> dict:
    cb = ColorBattle(seed, skills)
    for t, p in players.items():
        if not p.is_llm:
            cb.add_bot(t, p.eager)
    llm_teams = [t for t, p in players.items() if p.is_llm]
    n_dec = int(round(ROUND_TIME / decision_dt))
    dec_steps = int(round(decision_dt / FIXED_DT))
    sk_info = cb.skill_info()
    for k, s in enumerate(sk_info):
        s["slot"] = k + 1
    system = system_prompt(n_dec, decision_dt, sk_info)
    last_fb: dict[int, str | None] = {t: None for t in llm_teams}

    record = {
        "seed": seed, "skills": skills or [], "decision_dt": decision_dt, "n_decisions": n_dec,
        "started": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "players": {LETTERS[t - 1]: {"name": p.name, "model": p.model, "vendor": p.vendor, "llm": p.is_llm} for t, p in players.items()},
        "system_prompt": system,
        "decisions": [],  # one entry per decision tick: snapshot + every team's exchange
        "commands": [],   # every command handed to the engine, with tick index: replays the game exactly
        "timeline": [],   # (t, counts) at 10 Hz for charts
    }

    def ask(t: int, obs: str):
        return t, players[t].decide(system, obs)

    pool = ThreadPoolExecutor(max_workers=max(1, len(llm_teams)))
    dec_no = 0
    while not cb.over:
        if cb.tick % dec_steps == 0 and dec_no < n_dec:
            dec_no += 1
            snap = cb.snapshot()
            entry = {"no": dec_no, "tick": cb.tick, "t": snap.t, "counts": snap.counts, "grid": snap.grid,
                     "balls": {LETTERS[t - 1]: b for t, b in snap.balls.items()}, "teams": {}}
            obs = {t: observation(snap, t, dec_no, n_dec, last_fb[t]) for t in llm_teams}
            replies = dict(pool.map(lambda t: ask(t, obs[t]), llm_teams)) if llm_teams else {}
            # apply in rotating order so no team always moves first within a tick
            order = sorted(llm_teams, key=lambda t: (t + dec_no) % 4)
            for t in order:
                r = replies[t]
                cmds = parse(r.text) if not r.error else []
                applied = []
                for c in cmds:
                    ok = True if c["type"] == "wait" else cb.command(t, {k: v for k, v in c.items()})
                    applied.append({"cmd": fmt_cmd(c), "accepted": ok})
                    record["commands"].append({"tick": cb.tick, "team": LETTERS[t - 1], "cmd": c, "accepted": ok})
                if r.error:
                    fb = f"(your reply failed: {r.error})"
                elif not cmds:
                    fb = "(no valid CMD line found in your reply, nothing was done)"
                else:
                    fb = "; ".join(f"{a['cmd']} -> {'accepted' if a['accepted'] else 'REJECTED'}" for a in applied)
                last_fb[t] = fb
                cost = call_cost(players[t].model, r.usage, datetime.fromisoformat(r.at) if r.at else None)
                entry["teams"][LETTERS[t - 1]] = {
                    "prompt": r.prompt, "reply": r.text, "seconds": round(r.seconds, 2), "usage": r.usage,
                    "cost_usd": round(cost, 5) if cost is not None else None, "error": r.error, "commands": applied, "at": r.at,
                }
            record["decisions"].append(entry)
            lead = max((t for t in range(1, 5)), key=lambda t: snap.counts[t])
            log(f"  t={snap.t:4.0f}s  " + "  ".join(f"{LETTERS[t-1]}:{snap.counts[t]:3d}" for t in range(1, 5)) +
                f"  lead {LETTERS[lead-1]}  " + " | ".join(f"{LETTERS[t-1]} {entry['teams'][LETTERS[t-1]]['seconds']:.0f}s" for t in llm_teams))
        cb.step()
        if cb.tick % 6 == 0:
            s = cb.s
            record["timeline"].append([round(cb.tick * FIXED_DT, 1)] + [int(s.counts[t]) for t in range(1, 5)])
        ev = cb.drain_events()
        if ev:
            record.setdefault("events", []).extend({**e, "tick": cb.tick} for e in ev)
    pool.shutdown()

    final = cb.snapshot()
    rank = cb.ranking()
    record["final"] = {"counts": final.counts, "ranking": [LETTERS[t - 1] for t in rank], "winner": LETTERS[rank[0] - 1], "grid": final.grid}
    record["totals"] = {}
    for t in llm_teams:
        L = LETTERS[t - 1]
        ex = [d["teams"][L] for d in record["decisions"]]
        cmds = [c for e in ex for c in e["commands"]]
        record["totals"][L] = {
            "model": players[t].model, "decisions": len(ex),
            "seconds": round(sum(e["seconds"] for e in ex), 1),
            "input_tokens": sum(e["usage"].get("input", 0) for e in ex),
            "output_tokens": sum(e["usage"].get("output", 0) for e in ex),
            "cost_usd": round(sum(e["cost_usd"] or 0 for e in ex), 4),
            "errors": sum(1 for e in ex if e["error"]),
            "no_command": sum(1 for e in ex if not e["error"] and not e["commands"]),
            "commands": len(cmds), "rejected": sum(1 for c in cmds if not c["accepted"]),
            "casts": sum(1 for c in cmds if c["cmd"].startswith("CAST") and c["accepted"]),
            "final_cells": final.counts[t],
        }
    record["finished"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    if out_path:
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        with open(out_path, "w") as f:
            json.dump(record, f, ensure_ascii=False, indent=1)
    return record


def transcript_md(rec: dict) -> str:
    """Human-readable log of every exchange (what each model saw is in the JSON; here: scores, replies, verdicts)."""
    out = [f"# Game seed {rec['seed']} — {'skills ' + ', '.join(i for i, _ in rec['skills']) if rec['skills'] else 'steering only'}", ""]
    out.append("Players: " + ", ".join(f"**{L}** {p['name']}" for L, p in rec["players"].items()))
    out.append("")
    out.append(f"Result: {' > '.join(rec['final']['ranking'])}  (cells " + ", ".join(f"{L} {rec['final']['counts'][k+1]}" for k, L in enumerate(LETTERS)) + ")")
    out.append("")
    for d in rec["decisions"]:
        out.append(f"## Decision {d['no']} — t = {d['t']:.0f} s — cells " + " ".join(f"{L} {d['counts'][k+1]}" for k, L in enumerate(LETTERS)))
        for L, e in d["teams"].items():
            verdict = "; ".join(f"`{c['cmd']}` {'✓' if c['accepted'] else '✗ rejected'}" for c in e["commands"]) or ("error: " + e["error"] if e["error"] else "no valid command")
            out.append(f"**{L}** ({e['seconds']:.1f} s): {verdict}")
            if e["reply"]:
                out.append("")
                out.append("> " + e["reply"].strip().replace("\n", "\n> "))
            out.append("")
    return "\n".join(out)
