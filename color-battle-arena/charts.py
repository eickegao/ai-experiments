#!/usr/bin/env python3
"""Cell curves for every game of a run: results/<run>/game_N_cells.png (one line per model, 10 Hz timeline from the game,
decision ticks marked, casts annotated) and results/<run>/cells.png with all games side by side.

    python3 charts.py results/2026-11-09_round2
The curves are the thing to analyse (user 2026-11-09): who collapsed when, which cast caused which jump.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

COLOR = {"Claude": "#d97706", "GPT": "#10a37f", "Gemini": "#4285f4", "DeepSeek": "#4d6bfe", "Bot": "#888888", "Rand": "#bbbbbb"}
TEAM_RGB = {"A": "#ef5350", "B": "#42a5f5", "C": "#66bb6a", "D": "#ffca28"}   # the game's own seat colours


def label(rec: dict, L: str) -> str:
    t = rec["setup"]["teams"][L]
    return f"{t['name']} ({L}: {', '.join(s['id'] for s in t['skills'])})"


def colour(rec: dict, L: str) -> str:
    name = rec["setup"]["teams"][L]["name"].split()[0]
    return COLOR.get(name, TEAM_RGB[L])


def draw(ax, rec: dict, annotate: bool = True):
    tl = rec["timeline"]
    ts = [r[0] for r in tl]
    dt = rec.get("decision_dt", 2.0)
    for k, L in enumerate("ABCD"):
        ax.plot(ts, [r[k + 1] for r in tl], color=colour(rec, L), lw=2.2, label=label(rec, L))
    for n in range(rec.get("n_decisions", 30)):
        ax.axvline(n * dt, color="#000", alpha=0.06, lw=1)
    if annotate:
        sk = {L: [s["id"] for s in t["skills"]] for L, t in rec["setup"]["teams"].items()}
        by_tick = {}
        for c in rec["commands"]:
            if c["cmd"]["type"] == "cast" and c["accepted"]:
                by_tick.setdefault((c["tick"], c["team"]), []).append(sk[c["team"]][c["cmd"]["slot"] - 1][:5])
        counts_at = {round(r[0], 1): r for r in tl}
        for (tick, L), names in by_tick.items():
            t = tick / 60
            row = counts_at.get(round(t, 1)) or min(tl, key=lambda r: abs(r[0] - t))
            y = row["ABCD".index(L) + 1]
            ax.annotate("+".join(names), (t, y), textcoords="offset points", xytext=(0, 8), fontsize=6.5, color=colour(rec, L), ha="center")
    ax.set_xlim(0, 60)
    ax.set_ylim(0, max(520, max(max(r[1:]) for r in tl) + 20))
    ax.set_xlabel("game time (s)")
    ax.set_ylabel("cells owned")
    ax.grid(alpha=0.25)
    f = rec["final"]
    ax.set_title(f"game {rec['game']} (seed {rec['seed']}): {' > '.join(f['ranking'])}  —  " + "  ".join(f"{L} {f['counts'][L]}" for L in "ABCD"), fontsize=10)
    ax.legend(fontsize=7.5, loc="upper left")


def main():
    run = Path(sys.argv[1])
    games = sorted((p for p in run.glob("game_*.json") if p.stem.split("_")[1].isdigit()), key=lambda p: int(p.stem.split("_")[1]))
    recs = [json.loads(p.read_text()) for p in games]
    for rec in recs:
        fig, ax = plt.subplots(figsize=(12, 6))
        draw(ax, rec)
        fig.tight_layout()
        fig.savefig(run / f"game_{rec['game']}_cells.png", dpi=150)
        plt.close(fig)
    if recs:
        fig, axes = plt.subplots(len(recs), 1, figsize=(12, 5 * len(recs)))
        for ax, rec in zip(axes if len(recs) > 1 else [axes], recs):
            draw(ax, rec, annotate=False)
        fig.tight_layout()
        fig.savefig(run / "cells.png", dpi=130)
        plt.close(fig)
    print("charts →", run)


if __name__ == "__main__":
    main()
