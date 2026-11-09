"""一局棋：轮流向两位棋手要走法，python-chess 验合法性，Stockfish 评估每一步，全部记进 JSON。"""
from __future__ import annotations

import datetime as dt
import json
import os
import sys
import time

import chess
import chess.pgn

from .engine import Engine, cp_for_chart
from .players import Player


class Game:
    def __init__(self, white: Player, black: Player, engine: Engine, out_dir: str, name: str,
                 max_attempts: int = 3, on_illegal: str = "forfeit", max_plies: int = 300, adjudicate_cp: int = 800):
        self.white, self.black, self.engine = white, black, engine
        self.out_dir, self.name = out_dir, name
        self.max_attempts, self.on_illegal, self.max_plies, self.adjudicate_cp = max_attempts, on_illegal, max_plies, adjudicate_cp
        os.makedirs(out_dir, exist_ok=True)
        self.board = chess.Board()
        self.plies: list[dict] = []
        self.log_path = os.path.join(out_dir, f"{name}.log")
        self.logf = open(self.log_path, "w", encoding="utf-8")

    def say(self, s: str):
        print(s, flush=True)
        self.logf.write(s + "\n")
        self.logf.flush()

    def player(self) -> Player:
        return self.white if self.board.turn == chess.WHITE else self.black

    def play(self) -> dict:
        started = dt.datetime.now(dt.timezone.utc)
        self.say(f"=== {self.name}: White = {self.white.name}  |  Black = {self.black.name}  |  verifier = python-chess + {self.engine.version}")
        before = self.engine.analyse(self.board)
        result, reason = None, None

        while not self.board.is_game_over(claim_draw=True):
            if len(self.board.move_stack) >= self.max_plies:
                result, reason = self._adjudicate(before), f"move cap {self.max_plies // 2}, adjudicated by Stockfish"
                break
            p = self.player()
            side = "White" if self.board.turn == chess.WHITE else "Black"
            attempts: list[dict] = []
            feedback, legal_list = None, None
            move = None
            for n in range(1, self.max_attempts + 1):
                rep = p.propose(self.board, feedback, legal_list)
                att = {"n": n, "raw": rep.text, "parsed": rep.move, "seconds": round(rep.seconds, 2), "usage": rep.usage, "error": rep.error, "legal": False}
                if rep.error:
                    feedback = f"Your previous reply failed ({rep.error}). Answer again with a legal move."
                elif rep.move is None:
                    feedback = "Your previous reply had no 'MOVE: <san>' line. Answer again and end with 'MOVE: <san>'."
                else:
                    try:
                        mv = self.board.parse_san(rep.move)
                        att["legal"] = True
                        move = mv
                    except ValueError:
                        feedback = f"'{rep.move}' is not a legal move in this position. Choose one of the legal moves listed below."
                attempts.append(att)
                self.say(f"  {side} try {n}: {rep.move!r} {'ok' if att['legal'] else 'ILLEGAL'} ({rep.seconds:.1f}s){' err=' + rep.error if rep.error else ''}")
                if move is not None:
                    break
                legal_list = [self.board.san(m) for m in self.board.legal_moves]

            forced = False
            if move is None:
                if self.on_illegal == "forfeit":
                    result = "0-1" if self.board.turn == chess.WHITE else "1-0"
                    reason = f"{side} failed to produce a legal move in {self.max_attempts} attempts (forfeit)"
                    self.plies.append({"ply": len(self.board.move_stack) + 1, "side": side, "san": None, "attempts": attempts, "forfeit": True})
                    break
                import random
                move = random.choice(list(self.board.legal_moves))
                forced = True

            san = self.board.san(move)
            best_before = before["best"]
            self.board.push(move)
            after = self.engine.analyse(self.board)
            # 评估差：从走棋方视角看，这一步丢了多少（兵）
            sign = 1 if side == "White" else -1
            loss = sign * (cp_for_chart(before) - cp_for_chart(after))
            ply = {
                "ply": len(self.board.move_stack), "move_no": (len(self.board.move_stack) + 1) // 2, "side": side,
                "san": san, "uci": move.uci(), "fen": self.board.fen(), "forced_random": forced,
                "eval_before": before, "eval_after": after, "loss_pawns": round(loss, 2),
                "was_best": san == best_before, "best_move": best_before,
                "check": self.board.is_check(), "capture": "x" in san,
                "attempts": attempts, "seconds": round(sum(a["seconds"] for a in attempts), 2),
            }
            self.plies.append(ply)
            ev = after.get("terminal") or (f"M{after['mate']}" if after["mate"] is not None else (f"{after['cp'] / 100:+.2f}" if after["cp"] is not None else "end"))
            flag = " BLUNDER" if loss >= 2 else (" mistake" if loss >= 1 else "")
            self.say(f"{ply['move_no']}{'.' if side == 'White' else '...'} {san:7s} eval {ev:>7s}  best {best_before or '-':6s}{flag}{' (forced random)' if forced else ''}")
            before = after

        if result is None:
            result = self.board.result(claim_draw=True)
            reason = self._end_reason()
        self.say(f"=== Result {result}: {reason}")
        self.logf.close()
        return self._save(result, reason, started)

    def _adjudicate(self, ev: dict) -> str:
        if ev.get("mate") is not None:
            return "1-0" if ev["mate"] > 0 else "0-1"
        cp = ev.get("cp") or 0
        if cp >= self.adjudicate_cp:
            return "1-0"
        if cp <= -self.adjudicate_cp:
            return "0-1"
        return "1/2-1/2"

    def _end_reason(self) -> str:
        b = self.board
        if b.is_checkmate():
            return "checkmate"
        if b.is_stalemate():
            return "stalemate"
        if b.is_insufficient_material():
            return "insufficient material"
        if b.can_claim_fifty_moves():
            return "fifty-move rule"
        if b.can_claim_threefold_repetition():
            return "threefold repetition"
        return "game over"

    def _save(self, result: str, reason: str, started) -> dict:
        game = chess.pgn.Game()
        game.headers.update({
            "Event": "AI Chess Arena", "Site": "API", "Date": started.strftime("%Y.%m.%d"), "Round": self.name,
            "White": self.white.name, "Black": self.black.name, "Result": result, "Termination": reason,
            "Annotator": f"python-chess (legality) + {self.engine.version} depth {self.engine.depth} (eval)",
        })
        node = game
        for p in self.plies:
            if p.get("san") is None:
                continue
            node = node.add_variation(chess.Move.from_uci(p["uci"]))
            a = p["eval_after"]
            ev = f"M{a['mate']}" if a["mate"] is not None else (f"{a['cp'] / 100:+.2f}" if a["cp"] is not None else "")
            node.comment = f"[%eval {ev}]" + (" forced random" if p["forced_random"] else "") + (f" illegal attempts: {len(p['attempts']) - 1}" if len(p["attempts"]) > 1 else "")
        with open(os.path.join(self.out_dir, f"{self.name}.pgn"), "w") as f:
            print(game, file=f)

        def side_stats(side: str) -> dict:
            ps = [p for p in self.plies if p["side"] == side and p.get("san")]
            illegal = sum(len(p["attempts"]) - 1 for p in self.plies if p["side"] == side)
            return {
                "moves": len(ps), "illegal_attempts": illegal, "forced_random": sum(p["forced_random"] for p in ps),
                "best_move_rate": round(sum(p["was_best"] for p in ps) / len(ps), 3) if ps else None,
                "avg_loss_pawns": round(sum(max(0, p["loss_pawns"]) for p in ps) / len(ps), 3) if ps else None,
                "blunders_2pawns": sum(p["loss_pawns"] >= 2 for p in ps),
                "avg_seconds": round(sum(p["seconds"] for p in ps) / len(ps), 1) if ps else None,
                "tokens_out": sum(a["usage"].get("output", 0) for p in ps for a in p["attempts"]),
            }

        data = {
            "name": self.name, "started_utc": started.isoformat(), "white": {"name": self.white.name, "model": self.white.model},
            "black": {"name": self.black.name, "model": self.black.model}, "result": result, "termination": reason,
            "plies_total": len([p for p in self.plies if p.get("san")]), "verifier": {"legality": f"python-chess {chess.__version__}", "eval": f"{self.engine.version} depth {self.engine.depth}"},
            "rules": {"max_attempts": self.max_attempts, "on_illegal": self.on_illegal, "max_plies": self.max_plies, "adjudicate_cp": self.adjudicate_cp},
            "stats": {"White": side_stats("White"), "Black": side_stats("Black")}, "final_fen": self.board.fen(), "plies": self.plies,
        }
        with open(os.path.join(self.out_dir, f"{self.name}.json"), "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=1)
        return data
