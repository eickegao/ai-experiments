"""Water Sort rules with fog, undo and restart, mirroring PlayDoz's game (games/nutssort/nutssort_logic.lua for the pour
rules, games/watersort/watersort_game.gui_script init_fog / reveal_top for the fog).

Tubes are lists of colour letters, bottom first. A pour moves the whole run of same-coloured layers on top of the source
(or as much of it as fits) onto an empty tube or a tube whose top layer has the same colour. Fog: only the top run of each
tube is visible; a layer stays visible once it has been revealed, an undo puts the fog back the way it was before the
undone pour (as the game does), a restart fogs everything again.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

LEVELS_LUA = Path.home() / "Projects/PlayDoz/PlayDozDefold/games/watersort/watersort_levels.lua"
PALETTE = ["red", "blue", "green", "yellow", "purple", "orange", "pink", "cyan", "brown", "lime", "navy", "coral",
           "teal", "magenta", "olive", "salmon", "forest", "lavender", "sky", "slate"]
LETTERS = "abcdefghijklmnopqrst"


def color_name(letter: str) -> str:
    return PALETTE[LETTERS.index(letter)]


def load_level(n: int, path: Path = LEVELS_LUA) -> tuple[int, list[str], bool]:
    """→ (capacity, tubes as letter strings bottom-first, fog flag) for baked level n (1..300)."""
    rows = re.findall(r"^\s*\{ c = (\d+),( f = 1,)? b = \{([^}]*)\} \},?\s*$", path.read_text(), re.M)
    cap, fog, tubes = rows[n - 1]
    return int(cap), re.findall(r'"([a-t]*)"', tubes), bool(fog)


def top_run(tube: list[str]) -> int:
    if not tube:
        return 0
    n = 1
    while n < len(tube) and tube[-1 - n] == tube[-1]:
        n += 1
    return n


@dataclass
class Game:
    capacity: int
    start: list[str]
    fog: bool = True
    tubes: list[list[str]] = field(default_factory=list)
    revealed: list[list[bool]] = field(default_factory=list)   # revealed[i][k] for layer k of tube i (always all True without fog)
    undo_stack: list[tuple] = field(default_factory=list)
    path: list[tuple[int, int]] = field(default_factory=list)  # pours of the current attempt that are still standing (1-based tubes)
    # counters over the whole session
    pours: int = 0        # every pour ever made, including ones undone later and ones in abandoned attempts
    undos: int = 0
    restarts: int = 0

    def __post_init__(self):
        self._reset()

    def _reset(self):
        self.tubes = [list(t) for t in self.start]
        self.revealed = [[not self.fog] * len(t) for t in self.tubes]
        for i in range(len(self.tubes)):
            self._reveal_top(i)
        self.undo_stack, self.path = [], []

    def _reveal_top(self, i: int):
        t = self.tubes[i]
        for k in range(len(t) - top_run(t), len(t)):
            self.revealed[i][k] = True

    @property
    def attempts(self) -> int:
        return self.restarts + 1

    def won(self) -> bool:
        return all(not t or (len(t) == self.capacity and len(set(t)) == 1) for t in self.tubes)

    def why_illegal(self, src: int, dst: int) -> str | None:
        """src / dst are 1-based. None if the pour is legal, otherwise a sentence for the player."""
        n = len(self.tubes)
        if not (1 <= src <= n and 1 <= dst <= n):
            return f"tube numbers go from 1 to {n}"
        if src == dst:
            return "source and target are the same tube"
        a, b = self.tubes[src - 1], self.tubes[dst - 1]
        if not a:
            return f"tube {src} is empty"
        if len(b) >= self.capacity:
            return f"tube {dst} is full"
        if b and b[-1] != a[-1]:
            return f"the top of tube {src} is {color_name(a[-1])} but the top of tube {dst} is {color_name(b[-1])}"
        return None

    def pour(self, src: int, dst: int) -> int:
        """Legal pour (check why_illegal first). Returns the number of layers moved."""
        assert self.why_illegal(src, dst) is None
        a, b = self.tubes[src - 1], self.tubes[dst - 1]
        k = min(top_run(a), self.capacity - len(b))
        self.undo_stack.append((src, dst, k, [r[:] for r in self.revealed]))
        color = a[-1]
        del a[-k:]
        del self.revealed[src - 1][-k:]
        b.extend(color * k)
        self.revealed[dst - 1].extend([True] * k)
        self._reveal_top(src - 1)
        self._reveal_top(dst - 1)
        self.path.append((src, dst))
        self.pours += 1
        return k

    def can_undo(self) -> bool:
        return bool(self.undo_stack)

    def undo(self):
        src, dst, k, revealed = self.undo_stack.pop()
        a, b = self.tubes[src - 1], self.tubes[dst - 1]
        color = b[-1]
        del b[-k:]
        a.extend(color * k)
        self.revealed = revealed
        self.path.pop()
        self.undos += 1

    def restart(self):
        self._reset()
        self.restarts += 1

    def view(self) -> list[list[str]]:
        """What the player sees: per tube, bottom first, a colour name or '?' per layer."""
        return [[color_name(c) if r else "?" for c, r in zip(t, rev)] for t, rev in zip(self.tubes, self.revealed)]
