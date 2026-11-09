"""The one prompt every model gets, and the parser for its answer.

The exchange is plain text: the model receives the board as 32 rows of characters plus its own state, and answers with
one or two command lines. The engine (not the prompt) decides whether a command is legal.
"""
from __future__ import annotations

import math
import re

from .sim import LETTERS, Snapshot

SKILL_HELP = {
    "fire": "FIRE: pick a point (x y); after 0.35 s a circle of radius {r} cells around it is painted your colour.",
    "lightning": "LIGHTNING: from your main ball's cell, four 1-cell-wide lines shoot to the board edges (up/down/left/right) and paint every cell they cross.",
    "teleport": "TELEPORT: pick a point (x y); your main ball jumps there instantly and paints the landing cell. Any distance.",
    "accel": "ACCEL: all your balls move x{m} for {d} s.",
    "split": "SPLIT: your ball becomes {c} balls for {w} s, then the extras vanish.",
    "giant": "GIANT: your balls get bigger for {d} s and hit more cells per bounce.",
    "freeze": "FREEZE: a wave spreads from your ball; enemy teams it reaches are slowed for {d} s.",
    "shock": "SHOCKWAVE: an arc of {a} degrees spreads forward from your ball and paints the first non-own cell on every ray.",
    "shatter": "SHATTER: for {d} s every bounce on a foreign cell spawns a small extra ball that also paints.",
    "chain": "CHAIN LIGHTNING: stuns every enemy ball on the board for {s} s (does not paint).",
    "snowball": "PLASMA: your main ball grows on each hit; after 5 hits the next hit paints a circle around it.",
    "bomb": "BOMB: for {d} s your main ball also paints {e} neighbouring cell(s) on every bounce.",
}


def system_prompt(n_decisions: int, decision_dt: float, skills: list[dict]) -> str:
    rules = [
        "You are one of four AI players in Color Battle, a 60-second territory game on a 32x32 board.",
        "Each team has one ball. A ball moves at 22 cells/s in a straight line. It passes freely over cells of its own colour;",
        "when it touches a cell of any other colour (neutral or enemy) it paints that cell your colour and bounces back.",
        "Balls also bounce off the board edges. Whoever owns the most cells when time runs out wins.",
        f"You decide every {decision_dt:g} seconds of game time ({n_decisions} decisions per game). Between decisions the ball keeps",
        "flying and bouncing on its own, so think about where the ball will be, not just where it is now.",
        "",
        "Coordinates: x runs left to right from 0 to 32, y runs top to bottom from 0 to 32. Cell at column c, row r covers",
        "x in [c-1, c] and y in [r-1, r]; its centre is (c-0.5, r-0.5). Row 1 is the top line of the board text.",
        "",
        "Commands (one per line, at most two lines, each starting with 'CMD:'):",
        "  CMD: TURN x y     point your ball straight at (x, y). Turning has a 1-second cooldown.",
    ]
    if skills:
        rules.append("  CMD: CAST slot [x y]   use the skill in that slot (x y only for skills that need a target point).")
    rules += [
        "  CMD: WAIT         do nothing this turn.",
        "",
        "Rules of the exchange: a command the engine rejects (on cooldown, off the board, frozen) is simply ignored and you are",
        "told next turn. Reply with brief reasoning (under 60 words), then the CMD line(s) last. Play to win.",
        "Decide fast: this is a real-time game, so keep your thinking short and answer right away. A good move now beats a",
        "perfect move later; do not deliberate at length.",
    ]
    if skills:
        rules.append("")
        rules.append("Your skills this game (you picked them in the draft; the other teams picked their own):")
        for sk in skills:
            p = sk.get("params", {})
            text = SKILL_HELP.get(sk["id"], sk["id"]).format(
                r=p.get("radius", ""), m=p.get("mult", ""), d=p.get("dur", ""), c=p.get("count", ""), w=p.get("window", ""),
                a=p.get("arc", ""), s=p.get("stun", ""), e=p.get("extra", ""))
            rules.append(f"  slot {sk['slot']}: {text} Cooldown {sk['cd']:g} s.")
    return "\n".join(rules)


def heading_word(dx: float, dy: float) -> str:
    """Human words for a direction (y grows downward)."""
    ang = math.degrees(math.atan2(-dy, dx)) % 360
    names = ["right", "up-right", "up", "up-left", "left", "down-left", "down", "down-right"]
    return names[int((ang + 22.5) // 45) % 8]


def observation(snap: Snapshot, team: int, decision_no: int, n_decisions: int, last: str | None) -> str:
    me = LETTERS[team - 1]
    grid = [list(r) for r in snap.grid]
    # mark every ball with the lowercase team letter at its cell (own ball with '@')
    for t, balls in snap.balls.items():
        for k, (x, y, _, _) in enumerate(balls):
            i, j = min(31, max(0, int(x))), min(31, max(0, int(y)))
            grid[j][i] = "@" if (t == team and k == 0) else LETTERS[t - 1].lower()
    board = "\n".join(f"{j + 1:>2} {''.join(r)}" for j, r in enumerate(grid))
    scores = "  ".join(f"{LETTERS[t - 1]}{' (you)' if t == team else ''}: {snap.counts[t]}" for t in range(1, 5))
    x, y, dx, dy = snap.balls[team][0]
    lines = [
        f"Decision {decision_no} of {n_decisions}. Time left: {snap.time_left:.1f} s.",
        f"Cells owned: {scores}  neutral: {snap.counts[0]}",
        f"You are team {me}. Your ball '@' is at x={x:.1f}, y={y:.1f}, heading {heading_word(dx, dy)} (dx={dx:+.2f}, dy={dy:+.2f}).",
        "Turn: " + ("ready." if snap.turn_cd[team] <= 0 else f"cooldown {snap.turn_cd[team]:.1f} s."),
    ]
    if snap.skills[team]:
        lines.append("Skills: " + "  ".join(
            f"slot {s['slot']} {s['id'].upper()} " + ("ready" if s["ready"] else f"cooldown {s['cd']:.1f} s") for s in snap.skills[team]))
    if snap.frozen[team]:
        lines.append("You are FROZEN right now: commands will be rejected until it wears off.")
    if last:
        lines.append(f"Your last decision: {last}")
    lines.append("")
    lines.append("Board (row number, then 32 columns; '.' neutral, A-D owner, lowercase letter = that team's ball, '@' = your ball):")
    lines.append("   " + "".join(str((i + 1) % 10) for i in range(32)))
    lines.append(board)
    lines.append("")
    lines.append("Your command(s):")
    return "\n".join(lines)


CMD_RE = re.compile(r"CMD\s*[:：]\s*\**\s*(TURN|CAST|WAIT)\b\s*([^\n]*)", re.IGNORECASE)
NUM_RE = re.compile(r"[-+]?\d+(?:\.\d+)?")


def parse(text: str) -> list[dict]:
    """Return up to two commands: {"type": "turn", "x", "y"} | {"type": "cast", "slot", "x"?, "y"?} | {"type": "wait"}.
    Anything unparsable is dropped (and shows up as 'no valid command' in the log)."""
    out = []
    for kind, rest in CMD_RE.findall(text or ""):
        kind = kind.upper()
        nums = [float(n) for n in NUM_RE.findall(rest)]
        if kind == "WAIT":
            out.append({"type": "wait"})
        elif kind == "TURN" and len(nums) >= 2:
            out.append({"type": "turn", "x": nums[0], "y": nums[1]})
        elif kind == "CAST" and nums:
            c = {"type": "cast", "slot": int(nums[0])}
            if len(nums) >= 3:
                c["x"], c["y"] = nums[1], nums[2]
            out.append(c)
        if len(out) == 2:
            break
    return out


def fmt_cmd(c: dict) -> str:
    if c["type"] == "wait":
        return "WAIT"
    if c["type"] == "turn":
        return f"TURN {c['x']:g} {c['y']:g}"
    tail = f" {c['x']:g} {c['y']:g}" if "x" in c else ""
    return f"CAST {c['slot']}{tail}"
