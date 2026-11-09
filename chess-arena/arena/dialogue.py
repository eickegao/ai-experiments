"""Dialogue frames: what the two models actually exchanged, as pictures for the video.

One 1920x1080 frame per attempt: left panel = the PGN prompt the arena sent, right panel = the model's verbatim reply,
bottom = the verifier's verdict (legal / illegal / Stockfish eval). Frames are joined into gameN_dialogue.mp4.
"""
from __future__ import annotations

import json
import os
import subprocess
import textwrap

import chess
from PIL import Image, ImageDraw, ImageFont

W, H = 1920, 1080
BG, PANEL, GOLD, WHITE, DIM, RED, GREEN = "#0d1530", "#141f45", "#ffc94a", "#ffffff", "#9aa3c2", "#ff5a5a", "#6fe07f"
MONO = "/System/Library/Fonts/Menlo.ttc"
SANS = "/System/Library/Fonts/Helvetica.ttc"


def font(path: str, size: int, bold: bool = False):
    try:
        return ImageFont.truetype(path, size, index=1 if bold else 0)
    except OSError:
        return ImageFont.load_default()


def wrap(text: str, width: int) -> list[str]:
    lines: list[str] = []
    for para in text.split("\n"):
        lines += textwrap.wrap(para, width=width, replace_whitespace=False, drop_whitespace=False) or [""]
    return lines


def panel(draw: ImageDraw.ImageDraw, x: int, y: int, w: int, h: int, title: str, body: str, mono_size: int = 22, max_lines: int = 30):
    draw.rounded_rectangle([x, y, x + w, y + h], radius=18, fill=PANEL, outline="#2a3a70", width=2)
    draw.text((x + 28, y + 22), title, font=font(SANS, 26, True), fill=GOLD)
    f = font(MONO, mono_size)
    cols = max(20, int((w - 56) / (mono_size * 0.6)))
    lines = wrap(body, cols)
    if len(lines) > max_lines:
        lines = lines[: max_lines - 1] + ["…"]
    ty = y + 72
    for ln in lines:
        draw.text((x + 28, ty), ln, font=f, fill=WHITE)
        ty += int(mono_size * 1.45)


def frame(move_label: str, who: str, side: str, attempt: dict, verdict: str, verdict_color: str, path: str):
    im = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(im)
    d.text((60, 44), move_label, font=font(MONO, 54, True), fill=GOLD)
    d.text((60, 118), f"{who} · {side} · attempt {attempt['n']}", font=font(SANS, 30), fill=DIM)
    panel(d, 60, 180, 900, 740, "arena → model  (PGN)", attempt.get("prompt") or "", 22, 28)
    reply = attempt["raw"] if attempt["raw"] else f"(no text; error: {attempt.get('error')})"
    panel(d, 980, 180, 880, 740, f"model → arena  ({attempt['seconds']}s)", reply, 24, 26)
    d.rounded_rectangle([60, 950, 1860, 1030], radius=16, fill="#0a1026", outline=verdict_color, width=3)
    d.text((84, 968), verdict, font=font(SANS, 30, True), fill=verdict_color)
    im.save(path)


def rebuild_prompt(board: chess.Board, attempts: list, i: int) -> str:
    from .players import describe
    if i == 0:
        return describe(board, None, None)
    prev = attempts[i - 1]
    if prev.get("error"):
        fb = f"Your previous reply failed ({prev['error']}). Answer again with a legal move."
    elif prev.get("parsed") is None:
        fb = "Your previous reply had no 'MOVE: <san>' line. Answer again and end with 'MOVE: <san>'."
    else:
        fb = f"'{prev['parsed']}' is not a legal move in this position. Choose one of the legal moves listed below."
    return describe(board, fb, [board.san(m) for m in board.legal_moves])


def render_dialogue(json_path: str, hold: float = 2.5) -> str:
    g = json.load(open(json_path, encoding="utf-8"))
    out_dir = os.path.dirname(json_path)
    name = g["name"]
    fdir = os.path.join(out_dir, "frames_dialogue", name)
    os.makedirs(fdir, exist_ok=True)
    board = chess.Board()
    n = 0
    for p in g["plies"]:
        side = p["side"]
        who = g["white"]["name"] if side == "White" else g["black"]["name"]
        label = f"{len(board.move_stack) // 2 + 1}{'.' if side == 'White' else '...'} {p.get('san') or '?'}"
        for i, a in enumerate(p["attempts"]):
            a = dict(a)
            a["prompt"] = a.get("prompt") or rebuild_prompt(board, p["attempts"], i)
            if a["legal"]:
                ev = p["eval_after"]
                evs = ev.get("terminal") or (f"mate in {ev['mate']}" if ev.get("mate") is not None else (f"{ev['cp'] / 100:+.2f}" if ev.get("cp") is not None else "-"))
                extra = " · Stockfish's top choice" if p["was_best"] else (" · in top 3" if p["in_top3"] else f" · best was {p['best_move']}")
                extra += f" · BLUNDER, lost {p['loss_pawns']:.1f} pawns" if p["loss_pawns"] >= 2 else ""
                verdict, color = f"python-chess: legal ✓   Stockfish after move: {evs}{extra}", GREEN if p["loss_pawns"] < 2 else RED
            elif a.get("parsed"):
                verdict, color = f"python-chess: '{a['parsed']}' is ILLEGAL ✗  →  retry with the legal-move list", RED
            else:
                verdict, color = "no 'MOVE:' line found  →  retry", RED
            frame(label, who, side, a, verdict, color, os.path.join(fdir, f"{n:04d}.png"))
            n += 1
        if p.get("san"):
            board.push(chess.Move.from_uci(p["uci"]))
    mp4 = os.path.join(out_dir, f"{name}_dialogue.mp4")
    if n:
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", f"1/{hold}", "-i", os.path.join(fdir, "%04d.png"),
                        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-r", "30", mp4], check=True)
    return mp4
