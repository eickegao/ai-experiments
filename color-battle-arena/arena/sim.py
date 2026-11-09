"""Bridge to the real Color Battle simulation (PlayDoz, `games/clashdoz/cd_sim.lua`), run headless through lupa.

The Lua code is the referee: all actions go through `cd_sim.command`, illegal ones are rejected by the engine itself, and the
world only advances through `cd_sim.step` with a fixed dt and a seeded RNG, so a game is fully reproducible from
(seed, loadout, command log).

Coordinates: x runs left to right (0..32), y runs top to bottom (0..32). Cell (col c, row r) covers x in [c-1, c), y in [r-1, r).
Teams are 1..4 and are shown to the models as letters A..D.
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field

from lupa import lua51 as _lua  # PUC Lua 5.1 build shipped with lupa; the game is written for Defold's Lua 5.1 dialect

PLAYDOZ = os.environ.get("PLAYDOZ_DIR", os.path.expanduser("~/Projects/PlayDoz/PlayDozDefold"))
LETTERS = "ABCD"
GRID = 32
ROUND_TIME = 60.0
FIXED_DT = 1.0 / 60.0

_BOOT = """
vmath = vmath or { vector4 = function(r, g, b, a) return { x = r, y = g, z = b, w = a } end,
                   vector3 = function(x, y, z) return { x = x, y = y, z = z } end }
package.path = "%s/?.lua;" .. package.path
"""


@dataclass
class Snapshot:
    t: float  # seconds elapsed
    time_left: float
    counts: dict  # team -> cells (0 = neutral)
    grid: list  # 32 strings, row 1 first; '.' neutral, 'A'..'D' owner
    balls: dict  # team -> list of (x, y, dx, dy); index 0 is the main ball
    skills: dict  # team -> list of {id, level, cd, ready}
    turn_cd: dict  # team -> seconds
    frozen: dict  # team -> bool
    events: list = field(default_factory=list)
    over: bool = False
    winner: int | None = None


class ColorBattle:
    """One game. `skills` is a list of (id, level) given to every team, or None for steering only."""

    def __init__(self, seed: int, skills: list[tuple[str, int]] | None = None, layout: str = "quad"):
        self.L = _lua.LuaRuntime(unpack_returned_tuples=False)
        self.L.execute(_BOOT % PLAYDOZ)
        self.sim = self.L.require("games.clashdoz.cd_sim")
        self.ai = self.L.require("games.clashdoz.cd_ai")
        self.config = self.L.require("games.clashdoz.cd_config")
        self.seed = seed
        self.skills = skills or []
        opts = {"layout": layout}
        if skills:
            lo = self._loadout(skills)
            opts["loadout"] = lo
            opts["enemies"] = self.L.table_from({t: self.L.table(skills=self._loadout(skills)) for t in range(2, 5)})
        self.s = self.sim.new(seed, self.L.table(**opts))
        self.n = int(self.s.n)
        self.tick = 0
        self._bots = {}

    def _loadout(self, skills):
        return self.L.table_from([self.L.table(id=i, level=l) for i, l in skills])

    # ---- control -------------------------------------------------------------------------------------------------
    def add_bot(self, team: int, eager: float = 0.6):
        """Let the game's built-in bot drive this team (it acts every tick, like in the shipped game)."""
        self._bots[team] = self.ai.new(team, 100 + team + self.seed, self.L.table(eager=eager))

    def command(self, team: int, cmd: dict) -> bool:
        """cmd: {"type": "turn", "x", "y"} | {"type": "cast", "slot", "x"?, "y"?}. Returns True if the engine accepted it."""
        lua_cmd = self.L.table(**{k: v for k, v in cmd.items() if v is not None})
        return bool(self.sim.command(self.s, team, lua_cmd))

    def step(self, dt: float = FIXED_DT):
        for team, bot in self._bots.items():
            self.ai.update(bot, self.s, dt)
        self.sim.step(self.s, dt)
        self.tick += 1
        # the renderer-facing queues are never drained headless; keep them small
        self.s.changed = self.L.table()
        self.s.flips = self.L.table()

    def drain_events(self) -> list[dict]:
        out = []
        ev = self.s.events
        for k in range(1, len(ev) + 1):
            e = ev[k]
            out.append({str(key): (float(v) if isinstance(v, (int, float)) else str(v)) for key, v in e.items() if not hasattr(v, "items")})
        self.s.events = self.L.table()
        return out

    @property
    def over(self) -> bool:
        return bool(self.s.over)

    # ---- observation ---------------------------------------------------------------------------------------------
    def snapshot(self) -> Snapshot:
        s = self.s
        grid = []
        for j in range(1, GRID + 1):
            row = []
            for i in range(1, GRID + 1):
                v = s.grid[i][j]
                row.append("." if (v == 0 or v is False or v is None) else LETTERS[int(v) - 1])
            grid.append("".join(row))
        counts = {0: int(s.counts[0])}
        balls, skills, turn_cd, frozen = {}, {}, {}, {}
        for t in range(1, self.n + 1):
            tm = s.teams[t]
            counts[t] = int(s.counts[t])
            balls[t] = [(float(b.x), float(b.y), float(b.dx), float(b.dy)) for b in (tm.balls[k] for k in range(1, len(tm.balls) + 1))]
            sk = []
            for k in range(1, len(tm.skills) + 1):
                e = tm.skills[k]
                cd = float(tm.cd[e.id] or 0)
                sk.append({"slot": k, "id": str(e.id), "level": int(e.level), "cd": round(cd, 1), "ready": bool(self.sim.can_cast(s, tm, k))})
            skills[t] = sk
            turn_cd[t] = round(float(tm.turn_cd or 0), 2)
            frozen[t] = bool(self.sim.is_frozen(s, tm))
        return Snapshot(
            t=round(float(s.elapsed), 3), time_left=round(float(s.time_left), 3), counts=counts, grid=grid, balls=balls,
            skills=skills, turn_cd=turn_cd, frozen=frozen, over=bool(s.over), winner=int(s.winner) if s.winner else None,
        )

    def ranking(self) -> list[int]:
        r = self.sim.ranking(self.s)
        return [int(r[k]) for k in range(1, self.n + 1)]

    def skill_info(self) -> list[dict]:
        """Static description of the loadout (cooldowns at level) for the prompt."""
        out = []
        for i, l in self.skills:
            d = self.config.SKILLS[i]
            params = {}
            for key in ("radius", "mult", "dur", "count", "window", "arc", "stun"):
                v = d[key]
                if v is not None:
                    params[key] = float(v[l])
            out.append({"id": i, "level": l, "name": str(d.name), "cd": float(d.cd[l]), "target": bool(d.target), "params": params})
        return out
