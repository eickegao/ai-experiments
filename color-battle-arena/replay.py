#!/usr/bin/env python3
"""Replay a recorded game deterministically (same seed, same loadout, same commands at the same ticks) and render frames
for the video. The LLM replies are not re-run; they are read from the JSON. Frames go to <results dir>/frames/game_N/.

  python3 replay.py results/<dir> [--game N] [--fps 30] [--check]
--check only re-simulates and verifies the final cell counts match the recording (proves the log is complete)."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from arena.render import chart_timeline, draw_frame  # noqa: E402
from arena.sim import FIXED_DT, LETTERS, ColorBattle  # noqa: E402


def replay(rec: dict, frames_dir: Path | None, fps: int, title: str) -> dict:
    skills = [tuple(s) for s in rec["skills"]] or None
    cb = ColorBattle(rec["seed"], skills)
    for L, p in rec["players"].items():
        if not p["llm"]:
            cb.add_bot(LETTERS.index(L) + 1, 0.6)
    by_tick: dict[int, list] = {}
    for c in rec["commands"]:
        by_tick.setdefault(c["tick"], []).append(c)
    say_by_tick = {d["tick"]: d for d in rec["decisions"]}
    names = {LETTERS.index(L) + 1: p["name"] for L, p in rec["players"].items()}
    last = {}
    every = max(1, round(1 / (fps * FIXED_DT)))
    n = 0
    if frames_dir:
        frames_dir.mkdir(parents=True, exist_ok=True)
    while not cb.over:
        if cb.tick in say_by_tick:
            for L, e in say_by_tick[cb.tick]["teams"].items():
                cmd = ", ".join(c["cmd"] + ("" if c["accepted"] else " ✗") for c in e["commands"]) or ("error" if e["error"] else "no command")
                say = (e["reply"] or "").split("CMD:")[0].strip()
                last[LETTERS.index(L) + 1] = {"cmd": cmd, "say": say}
        for c in by_tick.get(cb.tick, []):
            if c["cmd"]["type"] != "wait":
                cb.command(LETTERS.index(c["team"]) + 1, c["cmd"])
        if frames_dir and cb.tick % every == 0:
            snap = cb.snapshot()
            ev = cb.drain_events()
            im = draw_frame(snap.grid, snap.balls, snap.counts, snap.t, names, last, None, title, ev)
            im.save(frames_dir / f"f{n:05d}.png")
            n += 1
        cb.step()
    final = cb.snapshot()
    return {"counts": final.counts, "frames": n}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--game", type=int, default=0, help="1-based; default all")
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    d = Path(a.dir)
    files = sorted(d.glob("game_*.json"), key=lambda p: int(p.stem.split("_")[1]))
    if a.game:
        files = [d / f"game_{a.game}.json"]
    recs = []
    for f in files:
        rec = json.loads(f.read_text())
        recs.append(rec)
        g = f.stem.split("_")[1]
        out = replay(rec, None if a.check else d / "frames" / f"game_{g}", a.fps, f"Color Battle · game {g}")
        ok = all(out["counts"][k] == rec["final"]["counts"][str(k)] if str(k) in rec["final"]["counts"] else out["counts"][k] == rec["final"]["counts"][k] for k in range(1, 5))
        print(f"game {g}: replay {'matches' if ok else 'DOES NOT MATCH'} the recording; counts {out['counts']}; frames {out['frames']}")
    if not a.check and recs:
        chart_timeline(recs, None, str(d / "timeline.png"))
        print("chart:", d / "timeline.png")


if __name__ == "__main__":
    main()
