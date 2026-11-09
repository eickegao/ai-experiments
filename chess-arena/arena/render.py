"""Video assets: one board PNG per ply (eval bar + captions), evaluation chart, replay mp4, key-moment list."""
from __future__ import annotations

import json
import os
import subprocess

import chess
import chess.svg

from .engine import cp_for_chart

# two formats: landscape 1920x1080 (long-form, default), portrait 1080x1350 (Shorts)
LAYOUT = {"landscape": (1920, 1080), "portrait": (1080, 1350)}
W, H = LAYOUT["landscape"]


def _svg_board(board: chess.Board, last: chess.Move | None, flipped: bool) -> str:
    check = board.king(board.turn) if board.is_check() else None
    return chess.svg.board(board, lastmove=last, check=check, size=880, orientation=chess.BLACK if flipped else chess.WHITE,
                           colors={"square light": "#f0d9b5", "square dark": "#b58863", "square light lastmove": "#cdd26a", "square dark lastmove": "#aaa23a"})


def frame_svg(board: chess.Board, last: chess.Move | None, caption: str, sub: str, ev: float, white_name: str, black_name: str, layout: str = "landscape") -> str:
    if layout == "landscape":
        return frame_svg_landscape(board, last, caption, sub, ev, white_name, black_name)
    bar_h = 880
    white_frac = max(0.02, min(0.98, 0.5 + ev / 20))  # ev ∈ [-10, 10] → 白方占比
    board_svg = _svg_board(board, last, flipped=False)
    import re
    vb = re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', board_svg)
    scale = 880 / float(vb.group(1)) if vb else 1.0  # chess.svg draws in viewBox units; scale up to 880px
    inner = board_svg.split(">", 1)[1].rsplit("</svg>", 1)[0]  # strip the outer <svg>
    return f"""<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
<rect width="{W}" height="{H}" fill="#0d1530"/>
<text x="60" y="78" font-family="Helvetica, Arial, sans-serif" font-size="40" font-weight="700" fill="#ffffff">{_esc(black_name)}</text>
<text x="60" y="118" font-family="Helvetica, Arial, sans-serif" font-size="26" fill="#ffffff99">Black</text>
<g transform="translate(60,150) scale({scale:.4f})">{inner}</g>
<g transform="translate(980,150)">
  <rect x="0" y="0" width="40" height="{bar_h}" fill="#222" rx="6"/>
  <rect x="0" y="{bar_h * (1 - white_frac):.1f}" width="40" height="{bar_h * white_frac:.1f}" fill="#f0f0f0" rx="6"/>
  <text x="20" y="{bar_h + 36}" text-anchor="middle" font-family="Menlo, monospace" font-size="24" fill="#ffc94a">{ev:+.1f}</text>
</g>
<text x="60" y="1082" font-family="Helvetica, Arial, sans-serif" font-size="40" font-weight="700" fill="#ffffff">{_esc(white_name)}</text>
<text x="60" y="1122" font-family="Helvetica, Arial, sans-serif" font-size="26" fill="#ffffff99">White</text>
<text x="60" y="1210" font-family="Menlo, monospace" font-size="54" font-weight="700" fill="#ffc94a">{_esc(caption)}</text>
<text x="60" y="1268" font-family="Helvetica, Arial, sans-serif" font-size="30" fill="#ffffffcc">{_esc(sub)}</text>
</svg>"""


def frame_svg_landscape(board, last, caption, sub, ev, white_name, black_name) -> str:
    W, H = LAYOUT["landscape"]
    size = 960
    board_svg = _svg_board(board, last, flipped=False)
    import re
    vb = re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', board_svg)
    scale = size / float(vb.group(1)) if vb else 1.0
    inner = board_svg.split(">", 1)[1].rsplit("</svg>", 1)[0]
    white_frac = max(0.02, min(0.98, 0.5 + ev / 20))
    x0, y0 = 60, 60
    bx = x0 + size + 30
    tx = bx + 90
    # split the caption on " · " so it fits the right column
    sub_lines = [sub] if len(sub) < 48 else sub.split(" · ", 1)
    sub_svg = "".join(f'<text x="{tx}" y="{760 + i * 44}" font-family="Helvetica, Arial, sans-serif" font-size="32" fill="#ffffffcc">{_esc(t)}</text>' for i, t in enumerate(sub_lines))
    return f"""<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
<rect width="{W}" height="{H}" fill="#0d1530"/>
<g transform="translate({x0},{y0}) scale({scale:.4f})">{inner}</g>
<g transform="translate({bx},{y0})">
  <rect x="0" y="0" width="40" height="{size}" fill="#222" rx="6"/>
  <rect x="0" y="{size * (1 - white_frac):.1f}" width="40" height="{size * white_frac:.1f}" fill="#f0f0f0" rx="6"/>
</g>
<text x="{tx}" y="110" font-family="Helvetica, Arial, sans-serif" font-size="30" fill="#ffffff99">Black</text>
<text x="{tx}" y="160" font-family="Helvetica, Arial, sans-serif" font-size="44" font-weight="700" fill="#ffffff">{_esc(black_name)}</text>
<text x="{tx}" y="930" font-family="Helvetica, Arial, sans-serif" font-size="30" fill="#ffffff99">White</text>
<text x="{tx}" y="980" font-family="Helvetica, Arial, sans-serif" font-size="44" font-weight="700" fill="#ffffff">{_esc(white_name)}</text>
<text x="{tx}" y="500" font-family="Menlo, monospace" font-size="120" font-weight="700" fill="#ffc94a">{_esc(caption)}</text>
<text x="{tx}" y="600" font-family="Menlo, monospace" font-size="52" fill="#ffffff">Stockfish {ev:+.1f}</text>
{sub_svg}
</svg>"""


def _esc(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def render_game(json_path: str, fps_hold: float = 1.6, layout: str = "landscape") -> dict:
    global W, H
    W, H = LAYOUT[layout]
    data = json.load(open(json_path, encoding="utf-8"))
    out_dir = os.path.dirname(json_path)
    name = data["name"]
    frames_dir = os.path.join(out_dir, "frames", name)
    os.makedirs(frames_dir, exist_ok=True)
    wn, bn = data["white"]["name"], data["black"]["name"]
    board = chess.Board()
    paths = []

    def emit(i, caption, sub, ev, last):
        svg = frame_svg(board, last, caption, sub, ev, wn, bn, layout)
        p = os.path.join(frames_dir, f"{i:04d}.png")
        subprocess.run(["rsvg-convert", "-w", str(W), "-h", str(H), "-o", p], input=svg.encode(), check=True)
        paths.append(p)

    emit(0, "Start", f"{wn} (White) vs {bn} (Black)", 0.0, None)
    key = []
    for p in data["plies"]:
        if p.get("san") is None:
            key.append({"ply": p["ply"], "type": "forfeit", "text": f"{p['side']} could not produce a legal move in {len(p['attempts'])} attempts"})
            continue
        mv = chess.Move.from_uci(p["uci"])
        board.push(mv)
        ev = cp_for_chart(p["eval_after"])
        tag = ""
        if len(p["attempts"]) > 1:
            tag = f" · {len(p['attempts']) - 1} illegal attempt{'s' if len(p['attempts']) > 2 else ''}"
            key.append({"ply": p["ply"], "type": "illegal", "text": f"{p['side']} tried {[a['parsed'] for a in p['attempts'][:-1]]} before {p['san']}"})
        if p["loss_pawns"] >= 2:
            tag += " · BLUNDER"
            key.append({"ply": p["ply"], "type": "blunder", "text": f"{p['side']} {p['san']} lost {p['loss_pawns']:.1f} pawns (best was {p['best_move']})"})
        if p["forced_random"]:
            tag += " · forced random"
        if board.is_checkmate():
            key.append({"ply": p["ply"], "type": "mate", "text": f"{p['side']} delivers checkmate with {p['san']}"})
        num = f"{p['move_no']}." if p["side"] == "White" else f"{p['move_no']}..."
        emit(p["ply"], f"{num} {p['san']}", f"best {p['best_move'] or '-'}{tag}", ev, mv)

    # final frame
    emit(len(paths), data["result"], data["termination"], cp_for_chart(data["plies"][-1]["eval_after"]) if data["plies"] and data["plies"][-1].get("san") else 0.0, None)

    # replay video: hold each frame fps_hold seconds
    mp4 = os.path.join(out_dir, f"{name}_replay.mp4")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", f"1/{fps_hold}", "-i", os.path.join(frames_dir, "%04d.png"),
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-r", "30", mp4], check=True)

    chart = eval_chart(data, os.path.join(out_dir, f"{name}_eval.png"))
    with open(os.path.join(out_dir, f"{name}_key_moments.json"), "w", encoding="utf-8") as f:
        json.dump(key, f, ensure_ascii=False, indent=1)
    return {"frames": len(paths), "replay": mp4, "chart": chart, "key_moments": key}


def eval_chart(data: dict, path: str) -> str:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    xs = [0] + [p["ply"] for p in data["plies"] if p.get("san")]
    ys = [0.0] + [cp_for_chart(p["eval_after"]) for p in data["plies"] if p.get("san")]
    fig, ax = plt.subplots(figsize=(12, 4.5), dpi=150)
    fig.patch.set_facecolor("#0d1530"); ax.set_facecolor("#0d1530")
    ax.fill_between(xs, ys, 0, where=[y >= 0 for y in ys], color="#f0f0f0", alpha=0.85, interpolate=True)
    ax.fill_between(xs, ys, 0, where=[y <= 0 for y in ys], color="#555", alpha=0.85, interpolate=True)
    ax.plot(xs, ys, color="#ffc94a", lw=2)
    for p in data["plies"]:
        if p.get("san") and p["loss_pawns"] >= 2:
            ax.scatter([p["ply"]], [cp_for_chart(p["eval_after"])], color="#ff5a5a", zorder=5, s=40)
    ax.set_ylim(-10.5, 10.5); ax.set_xlim(0, max(xs) if xs else 1)
    ax.set_xlabel("ply", color="#fff"); ax.set_ylabel("Stockfish eval (pawns, + = White)", color="#fff")
    ax.tick_params(colors="#fff"); [s.set_color("#ffffff55") for s in ax.spines.values()]
    ax.set_title(f"{data['white']['name']} (White) vs {data['black']['name']} (Black) — {data['result']}, {data['termination']}", color="#fff", fontsize=11)
    fig.tight_layout(); fig.savefig(path, facecolor=fig.get_facecolor()); plt.close(fig)
    return path
