"""Stockfish wrapper. Legality is handled by python-chess (rules); evaluation and best moves come from Stockfish (strength)."""
from __future__ import annotations

import shutil

import chess
import chess.engine


class Engine:
    def __init__(self, path: str | None = None, depth: int = 18):
        self.path = path or shutil.which("stockfish")
        if not self.path:
            raise SystemExit("stockfish not found: brew install stockfish, or pass --stockfish <path>")
        self.depth = depth
        self.sf = chess.engine.SimpleEngine.popen_uci(self.path)
        self.sf.configure({"Threads": 2, "Hash": 256})
        self.version = self.sf.id.get("name", "Stockfish")

    def analyse(self, board: chess.Board) -> dict:
        """Evaluation from White's point of view (centipawns), mate distance if any, best move and top-3 moves in SAN."""
        if board.is_game_over():
            # terminal position: checkmate counts as ±100 pawns for the winner, other endings as a draw
            return {"cp": None, "mate": None, "best": None, "terminal": board.result()}
        infos = self.sf.analyse(board, chess.engine.Limit(depth=self.depth), multipv=3)
        info = infos[0]
        score = info["score"].white()
        top = []
        for i in infos:
            pv = i.get("pv") or []
            if pv:
                top.append(board.san(pv[0]))
        return {
            "cp": score.score(mate_score=100000) if not score.is_mate() else None,
            "mate": score.mate(),
            "best": top[0] if top else None,
            "top3": top,
        }

    def best_san(self, board: chess.Board, ms: int) -> str:
        r = self.sf.play(board, chess.engine.Limit(time=ms / 1000))
        return board.san(r.move)

    def close(self):
        self.sf.quit()


def cp_for_chart(a: dict) -> float:
    """Squash an evaluation into a plottable number: mate = ±10, otherwise cp/100 clamped to ±10."""
    if a.get("terminal"):
        return {"1-0": 10.0, "0-1": -10.0}.get(a["terminal"], 0.0)
    if a.get("mate") is not None:
        return 10.0 if a["mate"] > 0 else -10.0
    if a.get("cp") is None:
        return 0.0
    return max(-10.0, min(10.0, a["cp"] / 100))
