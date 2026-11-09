"""Frames and charts for the video. Frames are drawn from a replayed simulation (see replay.py), 1920x1080:
board on the left, one card per player on the right with its cell count, latest command and a reasoning excerpt."""
from __future__ import annotations

import textwrap

from PIL import Image, ImageDraw, ImageFont

from .sim import LETTERS

W, H = 1920, 1080
TEAM_RGB = {1: (229, 72, 77), 2: (59, 130, 246), 3: (34, 197, 94), 4: (245, 179, 1)}  # A red, B blue, C green, D yellow
NEUTRAL = (236, 236, 240)
INK = (13, 21, 48)
PAPER = (250, 250, 252)


def _font(size: int, bold=False):
    for name in (["/System/Library/Fonts/SFNS.ttf"] if not bold else ["/System/Library/Fonts/SFNSDisplay-Bold.otf", "/System/Library/Fonts/SFNS.ttf"]):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    for name in ("/System/Library/Fonts/Helvetica.ttc", "/Library/Fonts/Arial.ttf", "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(name, size, index=1 if bold and name.endswith(".ttc") else 0)
        except OSError:
            continue
    return ImageFont.load_default()


F_BIG, F_MID, F_SM, F_MONO = _font(44, True), _font(30, True), _font(24), _font(22)


def draw_frame(grid: list[str], balls: dict, counts: dict, t: float, names: dict, last: dict, rank: list[int] | None = None,
               title: str = "", events: list | None = None) -> Image.Image:
    im = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(im)
    # board: 32 cells * 30 px = 960, centred vertically
    cell = 30
    bx, by = 60, (H - 32 * cell) // 2
    for j, row in enumerate(grid):
        for i, ch in enumerate(row):
            col = NEUTRAL if ch == "." else TEAM_RGB[LETTERS.index(ch) + 1]
            d.rectangle([bx + i * cell, by + j * cell, bx + (i + 1) * cell - 1, by + (j + 1) * cell - 1], fill=col)
    d.rectangle([bx - 3, by - 3, bx + 32 * cell + 2, by + 32 * cell + 2], outline=INK, width=4)
    # fire targets / lightning flashes from the events of this frame
    for e in events or []:
        if e.get("skill") == "fire" and e.get("phase") == "aim":
            cx, cy = bx + e["x"] * cell, by + e["y"] * cell
            r = e.get("radius", 2) * cell
            d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=INK, width=4)
    for team, bl in balls.items():
        for k, (x, y, dx, dy) in enumerate(bl):
            cx, cy = bx + x * cell, by + y * cell
            r = 14 if k == 0 else 9
            d.ellipse([cx - r - 4, cy - r - 4, cx + r + 4, cy + r + 4], fill=(255, 255, 255))
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=TEAM_RGB[team], outline=INK, width=3)
            if k == 0:
                d.line([cx, cy, cx + dx * 36, cy + dy * 36], fill=INK, width=3)
    # right panel
    px = bx + 32 * cell + 60
    d.text((px, by - 6), title or "Color Battle · four AIs", font=F_BIG, fill=INK)
    d.text((px, by + 50), f"time left {max(0.0, 60 - t):4.1f} s", font=F_MID, fill=(90, 96, 120))
    order = rank or sorted(range(1, 5), key=lambda tm: -counts[tm])
    cy0 = by + 110
    card_h = 200
    total = sum(counts[tm] for tm in range(1, 5)) + counts.get(0, 0)
    for n, team in enumerate(order):
        y0 = cy0 + n * (card_h + 12)
        d.rounded_rectangle([px, y0, W - 60, y0 + card_h], radius=16, fill=(255, 255, 255), outline=INK, width=3)
        d.rectangle([px, y0, px + 14, y0 + card_h], fill=TEAM_RGB[team])
        d.text((px + 34, y0 + 14), f"{LETTERS[team - 1]}  {names.get(team, '')}", font=F_MID, fill=INK)
        d.text((W - 80 - 150, y0 + 10), f"{counts[team]:4d}", font=F_BIG, fill=TEAM_RGB[team], anchor="la")
        # bar
        bw = (W - 60 - px) - 60
        frac = counts[team] / max(1, total)
        d.rectangle([px + 34, y0 + 60, px + 34 + bw, y0 + 72], fill=NEUTRAL)
        d.rectangle([px + 34, y0 + 60, px + 34 + int(bw * frac), y0 + 72], fill=TEAM_RGB[team])
        info = last.get(team) or {}
        cmd = info.get("cmd", "")
        if cmd:
            d.text((px + 34, y0 + 84), cmd, font=F_MONO, fill=INK)
        say = (info.get("say") or "").replace("\n", " ")
        if say:
            lines = textwrap.wrap(say, 58)[:3]
            for k, ln in enumerate(lines):
                d.text((px + 34, y0 + 116 + k * 26), ln, font=F_SM, fill=(90, 96, 120))
    return im


def chart_timeline(records: list[dict], names_of, path: str):
    """Cells over time, one subplot per game; the same model keeps its colour across games."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    n = len(records)
    fig, axes = plt.subplots(1, n, figsize=(5 * n, 4), sharey=True)
    if n == 1:
        axes = [axes]
    palette = {}
    for ax, rec in zip(axes, records):
        tl = rec["timeline"]
        ts = [r[0] for r in tl]
        for k, L in enumerate(LETTERS):
            name = rec["players"][L]["name"]
            col = palette.setdefault(name, f"C{len(palette)}")
            ax.plot(ts, [r[k + 1] for r in tl], color=col, label=name, lw=2)
        ax.set_title(f"seed {rec['seed']}: {' > '.join(rec['final']['ranking'])}")
        ax.set_xlabel("game time (s)")
        ax.grid(alpha=0.3)
    axes[0].set_ylabel("cells owned")
    seen = {}
    for ax in axes:
        for h, l in zip(*ax.get_legend_handles_labels()):
            seen.setdefault(l, h)
    fig.legend(seen.values(), seen.keys(), loc="lower center", ncol=min(4, len(seen)), frameon=False)
    fig.tight_layout(rect=(0, 0.1, 1, 1))
    fig.savefig(path, dpi=150)
    plt.close(fig)
