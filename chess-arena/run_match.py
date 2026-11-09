#!/usr/bin/env python3
"""AI 国际象棋对局：两位棋手各执一次白、一次黑，所有走法由 python-chess 验合法性、Stockfish 评估。

用法（在 chess-arena/ 下；密钥放仓库根目录 AIExperiments/.env：ANTHROPIC_API_KEY / OPENAI_API_KEY）：
  python3 run_match.py                                  # Claude (claude-fable-5-1) vs OpenAI (gpt-6-astra)，两局
  python3 run_match.py --a claude:claude-opus-5-5 --b openai:gpt-6.1-terra
  python3 run_match.py --a stockfish:50 --b random:0.1 --games 2 --out results/dryrun   # 不花钱的干跑
  python3 run_match.py --render-only results/2026-11-08_xxx                             # 只重新出图/视频

输出到 results/<时间戳>_<a>_vs_<b>/：
  game1.pgn / game1.json / game1.log   完整记录（每次提示的原始回复、尝试次数、每步 Stockfish 评估）
  game1_replay.mp4 / game1_eval.png / game1_key_moments.json / frames/game1/*.png   视频素材
  summary.md / summary.json            两局汇总
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
from arena.render import render_game


def load_env():
    """密钥统一放仓库根目录 AIExperiments/.env（所有实验共用）；实验目录自己的 .env 也认，优先级更高。都不入库。"""
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
    lines = [f"# AI Chess Arena · {a_name} vs {b_name}", "",
             f"Verifier: {games[0]['verifier']['legality']} for legality, {games[0]['verifier']['eval']} for evaluation.",
             f"Rules: {games[0]['rules']['max_attempts']} attempts per move, on failure = {games[0]['rules']['on_illegal']}; "
             f"move cap {games[0]['rules']['max_plies'] // 2}, then Stockfish adjudication at ±{games[0]['rules']['adjudicate_cp'] / 100:.0f} pawns.", "",
             f"## Score: {a_name} {score[a_name]} – {score[b_name]} {b_name}", "",
             "| Game | White | Black | Result | Termination | Plies |", "|---|---|---|---|---|---|"]
    for g in rows:
        lines.append(f"| {g['name']} | {g['white']['name']} | {g['black']['name']} | {g['result']} | {g['termination']} | {g['plies_total']} |")
    lines += ["", "## Per-side stats", "", "| Game | Side | Player | Moves | Illegal attempts | Best-move rate | Avg loss (pawns) | Blunders (≥2) | Avg s/move | Output tokens |", "|---|---|---|---|---|---|---|---|---|---|"]
    for g in rows:
        for side in ("White", "Black"):
            s = g["stats"][side]
            who = g["white"]["name"] if side == "White" else g["black"]["name"]
            lines.append(f"| {g['name']} | {side} | {who} | {s['moves']} | {s['illegal_attempts']} | {s['best_move_rate']} | {s['avg_loss_pawns']} | {s['blunders_2pawns']} | {s['avg_seconds']} | {s['tokens_out']} |")
    lines += ["", "Files per game: `<game>.pgn` (with [%eval] comments), `<game>.json` (every prompt reply, attempt, eval), `<game>.log`, `<game>_replay.mp4`, `<game>_eval.png`, `<game>_key_moments.json`, `frames/<game>/*.png`."]
    open(os.path.join(out_dir, "summary.md"), "w", encoding="utf-8").write("\n".join(lines) + "\n")
    json.dump({"score": score, "games": [{k: g[k] for k in ("name", "white", "black", "result", "termination", "plies_total", "stats")} for g in rows]},
              open(os.path.join(out_dir, "summary.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("\n".join(lines[:12]))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--a", default="claude", help="棋手 A：claude[:model] | openai[:model] | stockfish[:ms] | random[:illegal_rate]")
    ap.add_argument("--b", default="openai")
    ap.add_argument("--games", type=int, default=2, help="局数，奇数局 A 执白，偶数局 B 执白")
    ap.add_argument("--effort", default="high", help="两家模型的推理强度 low|medium|high")
    ap.add_argument("--attempts", type=int, default=3, help="每步最多尝试次数")
    ap.add_argument("--on-illegal", choices=["forfeit", "random"], default="forfeit", help="尝试用尽后：判负，或随机合法走法继续")
    ap.add_argument("--max-moves", type=int, default=150, help="回合上限，到了由 Stockfish 裁定")
    ap.add_argument("--depth", type=int, default=18, help="Stockfish 评估深度")
    ap.add_argument("--stockfish", default=None, help="stockfish 可执行文件路径")
    ap.add_argument("--out", default=None)
    ap.add_argument("--render-only", default=None, help="只对已有结果目录重新生成帧/视频/图")
    a = ap.parse_args()
    load_env()

    if a.render_only:
        for j in sorted(glob.glob(os.path.join(a.render_only, "game*.json"))):
            print(render_game(j))
        return

    engine = Engine(a.stockfish, a.depth)
    A = make_player(a.a, engine, a.effort)
    B = make_player(a.b, engine, a.effort)
    out_dir = a.out or os.path.join("results", f"{dt.datetime.now():%Y-%m-%d_%H%M}_{slug(A.model)}_vs_{slug(B.model)}")
    os.makedirs(out_dir, exist_ok=True)
    print(f"输出目录 {out_dir}")

    games = []
    try:
        for i in range(1, a.games + 1):
            white, black = (A, B) if i % 2 == 1 else (B, A)
            g = Game(white, black, engine, out_dir, f"game{i}", a.attempts, a.on_illegal, a.max_moves * 2).play()
            games.append(g)
            r = render_game(os.path.join(out_dir, f"game{i}.json"))
            print(f"  素材：{r['frames']} 帧，{r['replay']}，{r['chart']}，关键时刻 {len(r['key_moments'])} 个")
    finally:
        engine.close()
    summarize(out_dir, games, A.name, B.name)


if __name__ == "__main__":
    main()
