"""One model, one level, one conversation. Every turn is appended to a JSONL log, and the whole session (board, counters,
conversation) can be rebuilt from that log, so an interrupted run resumes without paying for any turn twice.
"""
from __future__ import annotations

import json
import time
from datetime import datetime
from pathlib import Path

from . import prompt
from .game import Game, color_name
from .players import Player
from .prices import call_cost


def apply(game: Game, reply: str) -> tuple[tuple | None, bool, str]:
    """Carry out the command in a reply. → (parsed command, was it accepted, feedback line for the next turn)."""
    cmd = prompt.parse(reply)
    if cmd is None:
        return None, False, ("FOUL: I could not read a command on your last line. Nothing changed. "
                             "End your reply with exactly one of: MOVE <from> <to>, UNDO, RESTART.")
    if cmd[0] == "undo":
        if not game.can_undo():
            return cmd, False, "FOUL: there is no pour to undo in this attempt. Nothing changed."
        game.undo()
        return cmd, True, "OK: your last pour was taken back."
    if cmd[0] == "restart":
        game.restart()
        return cmd, True, f"OK: restarted. This is attempt {game.attempts}."
    _, a, b = cmd
    why = game.why_illegal(a, b)
    if why:
        return cmd, False, f"FOUL: MOVE {a} {b} is not allowed: {why}. Nothing changed."
    color = color_name(game.tubes[a - 1][-1])
    k = game.pour(a, b)
    return cmd, True, f"OK: poured {k} layer{'s' if k > 1 else ''} of {color} from tube {a} to tube {b}."


class Session:
    def __init__(self, level: int, capacity: int, tubes: list[str], player: Player, effort: str, log: Path,
                 max_pours: int = 500, max_turns: int = 1500):
        self.level, self.player, self.effort, self.log = level, player, effort, log
        self.max_pours, self.max_turns = max_pours, max_turns
        self.game = Game(capacity, tubes, fog=True)
        self.system = prompt.system_prompt(self.game, max_pours)
        self.messages: list[dict] = []
        self.turns = self.fouls = 0
        self.seconds = self.cost = 0.0
        self.tokens = {"input": 0, "cached": 0, "output": 0}
        self.cost_known = True
        self.status = "running"
        header = {"type": "header", "level": level, "capacity": capacity, "tubes": tubes, "player": player.name,
                  "model": player.model, "vendor": player.vendor, "effort": effort, "max_pours": max_pours,
                  "max_turns": max_turns, "system": self.system}
        if log.exists() and log.stat().st_size:
            self._replay(header)
        else:
            log.parent.mkdir(parents=True, exist_ok=True)
            self._write(header)
            self.messages.append({"role": "user", "content": prompt.board_text(self.game, max_pours)})

    def _write(self, row: dict):
        with self.log.open("a") as f:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")

    def _replay(self, header: dict):
        rows = [json.loads(ln) for ln in self.log.read_text().splitlines() if ln.strip()]
        old = rows[0]
        for k in ("level", "tubes", "model", "effort", "max_pours", "system"):
            if old.get(k) != header[k]:
                raise SystemExit(f"{self.log} was recorded with a different {k}; use another --out directory")
        self.messages.append({"role": "user", "content": prompt.board_text(self.game, self.max_pours)})
        for row in rows[1:]:
            if row["type"] == "turn":
                self._account(row["seconds"], row["usage"], row.get("cost"))
                self._advance(row["reply"])
        self._check_end()

    def _account(self, seconds: float, usage: dict, cost: float | None):
        self.seconds += seconds
        for k in self.tokens:
            self.tokens[k] += usage.get(k, 0)
        if cost is None:
            self.cost_known = False
        else:
            self.cost += cost

    def _advance(self, reply: str) -> tuple[tuple | None, bool, str]:
        cmd, ok, feedback = apply(self.game, reply)
        self.turns += 1
        self.fouls += 0 if ok else 1
        self.messages.append({"role": "assistant", "content": reply})
        if not self.game.won():
            self.messages.append({"role": "user", "content": feedback + "\n\n" + prompt.board_text(self.game, self.max_pours)})
        return cmd, ok, feedback

    def _check_end(self):
        if self.game.won():
            self.status = "solved"
        elif self.game.pours >= self.max_pours:
            self.status = "pour_limit"
        elif self.turns >= self.max_turns:
            self.status = "turn_limit"

    def step(self, retries: int = 3) -> bool:
        """One model call. Returns False when the session is over (or the API keeps failing)."""
        if self.status != "running":
            return False
        if hasattr(self.player, "game"):
            self.player.game = self.game
        for attempt in range(retries):
            r = self.player.chat(self.system, self.messages)
            if not r.error:
                break
            self._write({"type": "api_error", "turn": self.turns + 1, "error": r.error, "seconds": round(r.seconds, 2),
                         "usage": r.usage, "at": r.at})
            time.sleep(5 * (attempt + 1))
        else:
            self.status = "api_error"
            return False
        when = datetime.fromisoformat(r.at) if r.at else None
        cost = 0.0 if self.player.vendor == "random" else call_cost(self.player.model, r.usage, when)
        self._account(r.seconds, r.usage, cost)
        sent = self.messages[-1]["content"]
        cmd, ok, feedback = self._advance(r.text)
        g = self.game
        self._write({"type": "turn", "turn": self.turns, "sent": sent, "reply": r.text, "cmd": cmd, "accepted": ok,
                     "feedback": feedback, "seconds": round(r.seconds, 2), "usage": r.usage, "cost": cost, "at": r.at,
                     "attempt": g.attempts, "pours": g.pours, "undos": g.undos, "restarts": g.restarts,
                     "fouls": self.fouls, "path_len": len(g.path), "tubes": ["".join(t) for t in g.tubes],
                     "view": g.view(), "won": g.won()})
        self._check_end()
        return self.status == "running"

    def summary(self, optimal: int | None = None) -> dict:
        g = self.game
        out = {"level": self.level, "player": self.player.name, "model": self.player.model, "vendor": self.player.vendor,
               "effort": self.effort, "status": self.status, "solved": g.won(), "turns": self.turns,
               "total_pours": g.pours, "undos": g.undos, "restarts": g.restarts, "attempts": g.attempts,
               "fouls": self.fouls, "seconds": round(self.seconds, 1), "tokens": self.tokens,
               "cost_usd": round(self.cost, 4) if self.cost_known else None}
        if g.won():
            check = Game(g.capacity, g.start, fog=False)
            for a, b in g.path:
                assert check.why_illegal(a, b) is None
                check.pour(a, b)
            assert check.won()
            out.update(solution_pours=len(g.path), solution=g.path)
            if optimal:
                out.update(optimal_pours=optimal, over_optimal=len(g.path) - optimal)
        return out
