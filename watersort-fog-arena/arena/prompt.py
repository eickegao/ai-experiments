"""The system prompt (identical for every model), the per-turn board text, and the reply parser."""
from __future__ import annotations

import re

from .game import Game

SYSTEM = """You are playing Water Sort, a puzzle game, one command at a time.

THE BOARD
There are {n} tubes, numbered 1 to {n}. Each tube holds up to {cap} layers of coloured water. I always list a tube from bottom to top.

GOAL
Every tube must end up either empty or completely full of a single colour.

POURING
"MOVE a b" pours from tube a into tube b. It is allowed only if tube a is not empty, tube b is not full, and tube b is either empty or has the same colour on top as tube a. All the touching layers of that colour at the top of tube a move together; if tube b does not have room for all of them, only as many as fit are moved.

FOG
This level is fogged. In each tube you can see only the top colour (and any layers of the same colour directly under it). Everything below is hidden and shown as "?". When a pour uncovers a hidden layer, it becomes visible and stays visible for the rest of that attempt.

OTHER COMMANDS
"UNDO" takes back your most recent pour in the current attempt. You can repeat it. The board goes back exactly as it was, including the fog over anything that pour uncovered.
"RESTART" puts the board back to the starting position, with the fog back in place, and begins a new attempt.
The level never changes: the hidden colours are the same in every attempt.

WHAT WE RECORD
- the total number of pours you make over the whole session (pours you later undo and pours in abandoned attempts all count)
- how many times you use UNDO and RESTART
- the number of pours in the attempt that finally solves the level (pours you undid are left out)
Fewer is better on every count. You have at most {max_pours} pours in total; if you reach that without solving the level, the session ends unsolved.

HOW TO ANSWER
Each turn I send you the board. Reply with a brief reason (three sentences at most) and then, on the last line, exactly one command:
MOVE <from> <to>
UNDO
RESTART
If the command is illegal or I cannot read it, nothing changes, I tell you why, and it is recorded as a foul."""


def system_prompt(game: Game, max_pours: int) -> str:
    return SYSTEM.format(n=len(game.tubes), cap=game.capacity, max_pours=max_pours)


def board_text(game: Game, max_pours: int) -> str:
    head = (f"Attempt {game.attempts} | pours this attempt: {len(game.path)} | total pours: {game.pours}/{max_pours} | "
            f"undos: {game.undos} | restarts: {game.restarts}")
    rows = [f"{i:>2}: {' '.join(t) if t else '(empty)'}" for i, t in enumerate(game.view(), 1)]
    return head + "\nTubes (bottom → top):\n" + "\n".join(rows)


_CMD = re.compile(r"^(?:MOVE\s+(\d+)\s+(?:TO\s+)?(\d+)|(UNDO)|(RESTART))$", re.I)


def parse(reply: str) -> tuple | None:
    """Reads the last non-empty line. → ("move", a, b) | ("undo",) | ("restart",) | None if unreadable."""
    lines = [ln for ln in reply.strip().splitlines() if ln.strip()]
    if not lines:
        return None
    last = re.sub(r"\s+", " ", lines[-1].strip().strip("`*_ .:>-").strip())
    m = _CMD.match(last)
    if not m:
        return None
    if m.group(3):
        return ("undo",)
    if m.group(4):
        return ("restart",)
    return ("move", int(m.group(1)), int(m.group(2)))
