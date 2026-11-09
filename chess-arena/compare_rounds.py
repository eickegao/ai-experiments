#!/usr/bin/env python3
"""Merge per-round summaries (low vs high effort) into one table and one chart: illegal attempts, top-1/top-3 agreement, average loss, seconds per move, cost."""
import json, os, sys

def load(d):
    return json.load(open(os.path.join(d, "summary.json"), encoding="utf-8"))

def agg(summary):
    out = {}
    for g in summary["games"]:
        for side in ("White", "Black"):
            who = g[side.lower()]["name"]
            s = g["stats"][side]
            o = out.setdefault(who, {"moves": 0, "illegal": 0, "top1": 0, "top3": 0, "loss": 0.0, "blunders": 0, "secs": 0.0, "cost": 0.0, "cost_known": True, "score": 0.0})
            o["moves"] += s["moves"]; o["illegal"] += s["illegal_attempts"]
            o["top1"] += (s["best_move_rate"] or 0) * s["moves"]; o["top3"] += (s["top3_rate"] or 0) * s["moves"]
            o["loss"] += (s["avg_loss_pawns"] or 0) * s["moves"]; o["blunders"] += s["blunders_2pawns"]
            o["secs"] += s["total_seconds"]
            if s["cost_usd"] is None: o["cost_known"] = False
            else: o["cost"] += s["cost_usd"]
    for who, o in out.items():
        o["score"] = summary["score"].get(who, 0)
        m = max(1, o["moves"])
        o["top1"] = round(o["top1"] / m, 3); o["top3"] = round(o["top3"] / m, 3); o["loss"] = round(o["loss"] / m, 3)
        o["secs_per_move"] = round(o["secs"] / m, 1)
        o["cost"] = round(o["cost"], 3) if o["cost_known"] else None
    return out

def main():
    dirs = sys.argv[1:]
    rounds = [(d, agg(load(d))) for d in dirs]
    lines = ["# Rounds comparison", "", "| Round | Player | Score | Moves | Illegal attempts | Top-1 | Top-3 | Avg loss | Blunders | s/move | Cost USD |", "|---|---|---|---|---|---|---|---|---|---|---|"]
    for d, a in rounds:
        for who, o in a.items():
            lines.append(f"| {os.path.basename(d)} | {who} | {o['score']} | {o['moves']} | {o['illegal']} | {o['top1']} | {o['top3']} | {o['loss']} | {o['blunders']} | {o['secs_per_move']} | {o['cost']} |")
    out_dir = os.path.dirname(dirs[0].rstrip("/")) or "."
    md = os.path.join(out_dir, "comparison.md")
    open(md, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    json.dump({os.path.basename(d): a for d, a in rounds}, open(os.path.join(out_dir, "comparison.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("\n".join(lines))
    try:
        import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt
        metrics = [("illegal", "Illegal attempts"), ("top1", "Top-1 agreement"), ("top3", "Top-3 agreement"), ("loss", "Avg loss (pawns)"), ("secs_per_move", "Seconds / move")]
        players = list(rounds[0][1].keys())
        fig, axes = plt.subplots(1, len(metrics), figsize=(4 * len(metrics), 4), dpi=150)
        fig.patch.set_facecolor("#0d1530")
        for ax, (k, title) in zip(axes, metrics):
            ax.set_facecolor("#0d1530"); ax.set_title(title, color="#fff", fontsize=11)
            w = 0.8 / len(players)
            for i, who in enumerate(players):
                ys = [a[who][k] for _, a in rounds]
                ax.bar([j + i * w for j in range(len(rounds))], ys, w, label=who.split(" (")[0], color=["#ffc94a", "#7fb3ff", "#ff7f7f"][i % 3])
            ax.set_xticks([j + w * (len(players) - 1) / 2 for j in range(len(rounds))]); ax.set_xticklabels([os.path.basename(d).split("_")[-1] for d, _ in rounds], color="#fff")
            ax.tick_params(colors="#fff"); [s.set_color("#ffffff55") for s in ax.spines.values()]
        axes[0].legend(facecolor="#0d1530", labelcolor="#fff", fontsize=9)
        fig.tight_layout(); fig.savefig(os.path.join(out_dir, "comparison.png"), facecolor=fig.get_facecolor()); plt.close(fig)
        print("chart:", os.path.join(out_dir, "comparison.png"))
    except Exception as e:
        print("chart failed:", e)

if __name__ == "__main__":
    main()
