"""Players. Every player gets the same position description and returns one move (SAN) plus a short rationale.

All players share one prompt (SYSTEM) for fairness. The exchange is pure PGN: each move is a fresh, stateless request
carrying the game so far as PGN, and the model answers with one SAN move. The first attempt gets no legal-move list (it tests real chess ability);
the list is added only when retrying after an illegal move.
"""
from __future__ import annotations

import os
import random
import re
import time
from dataclasses import dataclass, field

import chess

SYSTEM = (
    "You are playing a game of chess against another AI. Play to win.\n"
    "Think briefly, then give exactly one move for the side to move, in standard algebraic notation (SAN), "
    "on the last line in the form:\nMOVE: <san>\n"
    "Examples: MOVE: e4   MOVE: Nf3   MOVE: O-O   MOVE: exd5   MOVE: Qxf7#   MOVE: e8=Q\n"
    "Keep the reasoning under 80 words. Never output more than one MOVE line."
)


def describe(board: chess.Board, feedback: str | None, legal: list[str] | None) -> str:
    """The whole exchange is PGN: the game so far as a PGN (headers + movetext), ending at the side to move."""
    color = "White" if board.turn == chess.WHITE else "Black"
    movetext = board.root().variation_san(board.move_stack) if board.move_stack else ""
    if board.turn == chess.WHITE:
        movetext = (movetext + f" {board.fullmove_number}.").strip()
    pgn = (
        '[Event "AI Chess Arena"]\n'
        '[White "?"]\n[Black "?"]\n[Result "*"]\n\n' + movetext + " *"
    )
    parts = [f"You are {color}. Here is the game so far in PGN. Give your next move.", pgn]
    if feedback:
        parts.append(f"IMPORTANT: {feedback}")
    if legal is not None:
        parts.append("Legal moves in this position: " + " ".join(legal))
    parts.append("Reply with brief reasoning, then the final line 'MOVE: <san>'.")
    return "\n\n".join(parts)


MOVE_RE = re.compile(r"MOVE\s*[:：]\s*\**\s*([A-Za-z0-9+#=\-]+)")


def parse_move(text: str) -> str | None:
    hits = MOVE_RE.findall(text)
    if hits:
        return hits[-1].strip().rstrip(".")
    # fallback: a move-like token on the last line
    tail = text.strip().splitlines()[-1] if text.strip() else ""
    m = re.search(r"\b(O-O-O|O-O|[KQRBN]?[a-h]?[1-8]?x?[a-h][1-8](?:=[QRBN])?[+#]?)\b", tail)
    return m.group(1) if m else None


@dataclass
class Reply:
    text: str
    move: str | None
    seconds: float
    usage: dict = field(default_factory=dict)
    error: str | None = None
    prompt: str = ""  # exact text sent to the model (for the public transcript)


class Player:
    name = "player"
    model = ""

    def propose(self, board: chess.Board, feedback: str | None = None, legal: list[str] | None = None) -> Reply:
        raise NotImplementedError


class ClaudePlayer(Player):
    """Anthropic. Default claude-fable-5-1 (Anthropic's strongest generally available model). Thinking is always on; depth via effort.
    No server-side fallback on purpose: the experiment is about this exact model, so a refusal is logged as a failed attempt."""

    def __init__(self, model: str = "claude-fable-5-1", effort: str = "high"):
        import anthropic

        self.client = anthropic.Anthropic()
        self.model = model
        self.effort = effort
        self.name = f"Claude ({model})"

    def propose(self, board, feedback=None, legal=None) -> Reply:
        import anthropic

        t0 = time.time()
        prompt = describe(board, feedback, legal)
        try:
            r = self.client.messages.create(
                model=self.model,
                max_tokens=4000,
                system=SYSTEM,
                output_config={"effort": self.effort},
                messages=[{"role": "user", "content": prompt}],
            )
        except anthropic.APIError as e:
            return Reply("", None, time.time() - t0, error=f"{type(e).__name__}: {e}", prompt=prompt)
        if r.stop_reason == "refusal":
            cat = getattr(r.stop_details, "category", None) if r.stop_details else None
            return Reply("", None, time.time() - t0, error=f"refusal ({cat})", prompt=prompt)
        text = "".join(b.text for b in r.content if b.type == "text")
        usage = {"input": r.usage.input_tokens, "output": r.usage.output_tokens}
        return Reply(text, parse_move(text), time.time() - t0, usage, prompt=prompt)


class OpenAIPlayer(Player):
    """OpenAI. Default gpt-6-astra (the flagship in the Nov 2026 model list; gpt-6.1-terra is the fast variant). Responses API + reasoning effort."""

    def __init__(self, model: str = "gpt-6-astra", effort: str = "high"):
        import openai

        self.client = openai.OpenAI()
        self.model = model
        self.effort = effort
        self.name = f"OpenAI ({model})"

    def propose(self, board, feedback=None, legal=None) -> Reply:
        import openai

        t0 = time.time()
        prompt = describe(board, feedback, legal)
        try:
            r = self.client.responses.create(
                model=self.model,
                instructions=SYSTEM,
                input=prompt,
                reasoning={"effort": self.effort},
                max_output_tokens=4000,
            )
        except openai.APIError as e:
            return Reply("", None, time.time() - t0, error=f"{type(e).__name__}: {e}", prompt=prompt)
        text = r.output_text or ""
        u = r.usage
        usage = {"input": getattr(u, "input_tokens", 0), "output": getattr(u, "output_tokens", 0)} if u else {}
        return Reply(text, parse_move(text), time.time() - t0, usage, prompt=prompt)


class StockfishPlayer(Player):
    """For dry runs / baselines: Stockfish plays with a time limit."""

    def __init__(self, engine, limit_ms: int = 50):
        self.engine = engine
        self.limit_ms = limit_ms
        self.model = f"stockfish-{limit_ms}ms"
        self.name = f"Stockfish ({limit_ms} ms)"

    def propose(self, board, feedback=None, legal=None) -> Reply:
        t0 = time.time()
        san = self.engine.best_san(board, self.limit_ms)
        return Reply(f"MOVE: {san}", san, time.time() - t0)


class RandomPlayer(Player):
    """For dry runs: random legal moves, with an optional rate of deliberate illegal moves to exercise the retry logic."""

    def __init__(self, illegal_rate: float = 0.0, seed: int = 0):
        self.rng = random.Random(seed)
        self.illegal_rate = illegal_rate
        self.model = "random"
        self.name = "Random"

    def propose(self, board, feedback=None, legal=None) -> Reply:
        t0 = time.time()
        if feedback is None and self.rng.random() < self.illegal_rate:
            return Reply("I'll play MOVE: Qh9", "Qh9", time.time() - t0)
        san = board.san(self.rng.choice(list(board.legal_moves)))
        return Reply(f"MOVE: {san}", san, time.time() - t0)


def make_player(spec: str, engine=None, effort: str = "high") -> Player:
    """spec: claude | claude:<model> | openai | openai:<model> | stockfish[:<ms>] | random[:<illegal_rate>]"""
    kind, _, arg = spec.partition(":")
    if kind == "claude":
        return ClaudePlayer(arg or "claude-fable-5-1", effort)
    if kind == "openai":
        return OpenAIPlayer(arg or "gpt-6-astra", effort)
    if kind == "stockfish":
        return StockfishPlayer(engine, int(arg or 50))
    if kind == "random":
        return RandomPlayer(float(arg or 0))
    raise SystemExit(f"unknown player {spec!r}")
