"""Stockfish 封装：合法性由 python-chess 判（规则层），评估和最佳着法由 Stockfish 给（强度层）。"""
from __future__ import annotations

import shutil

import chess
import chess.engine


class Engine:
    def __init__(self, path: str | None = None, depth: int = 18):
        self.path = path or shutil.which("stockfish")
        if not self.path:
            raise SystemExit("找不到 stockfish，请 brew install stockfish 或用 --stockfish 指定路径")
        self.depth = depth
        self.sf = chess.engine.SimpleEngine.popen_uci(self.path)
        self.sf.configure({"Threads": 2, "Hash": 256})
        self.version = self.sf.id.get("name", "Stockfish")

    def analyse(self, board: chess.Board) -> dict:
        """返回白方视角的评估（厘兵）、是否将死分数、以及最佳着法 SAN。"""
        if board.is_game_over():
            # 终局：将死按 ±100 兵记给赢家，其他终局算和
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
    """把评估压成一个可画图的数：将死按 ±100 兵算，普通评估换成兵（cp/100），截断到 ±10。"""
    if a.get("terminal"):
        return {"1-0": 10.0, "0-1": -10.0}.get(a["terminal"], 0.0)
    if a.get("mate") is not None:
        return 10.0 if a["mate"] > 0 else -10.0
    if a.get("cp") is None:
        return 0.0
    return max(-10.0, min(10.0, a["cp"] / 100))
