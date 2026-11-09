#!/usr/bin/env python3
"""Write gameN_transcript.md: the complete exchange between the arena and the two models, move by move.

For each attempt it shows the exact PGN prompt the model received and the model's verbatim reply, then what the
verifier did (legal / illegal, Stockfish eval and best move). Prompts stored in the JSON are used as-is; for runs made
before prompts were stored, they are rebuilt deterministically from the move list with the same describe() function.

Usage: python3 transcript.py results/<dir>            # all games in the dir
"""
import glob, json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import chess
from arena.players import SYSTEM, describe


def rebuild_prompt(board: chess.Board, attempts: list, i: int) -> str:
    """Same logic as Game.play(): attempt 1 has no feedback; later attempts carry feedback + the legal-move list."""
    if i == 0:
        return describe(board, None, None)
    prev = attempts[i - 1]
    if prev.get("error"):
        fb = f"Your previous reply failed ({prev['error']}). Answer again with a legal move."
    elif prev.get("parsed") is None:
        fb = "Your previous reply had no 'MOVE: <san>' line. Answer again and end with 'MOVE: <san>'."
    else:
        fb = f"'{prev['parsed']}' is not a legal move in this position. Choose one of the legal moves listed below."
    return describe(board, fb, [board.san(m) for m in board.legal_moves])


def transcript(json_path: str) -> str:
    g = json.load(open(json_path, encoding="utf-8"))
    out = [f"# {g['name']}: {g['white']['name']} (White) vs {g['black']['name']} (Black)", "",
           f"Result **{g['result']}** ({g['termination']}). Verifier: {g['verifier']['legality']} for legality, {g['verifier']['eval']} for evaluation.", "",
           "Both models get the same system prompt on every request:", "", "```", SYSTEM, "```", "",
           "Then, for every move, the arena sends the game so far as PGN and the model answers. Everything below is verbatim.", ""]
    board = chess.Board()
    for p in g["plies"]:
        side = p["side"]
        who = g["white"]["name"] if side == "White" else g["black"]["name"]
        num = f"{(len(board.move_stack)) // 2 + 1}{'.' if side == 'White' else '...'}"
        out.append(f"## Move {num} {p.get('san') or '(no legal move)'} by {who}")
        out.append("")
        for i, a in enumerate(p["attempts"]):
            prompt = a.get("prompt") or rebuild_prompt(board, p["attempts"], i)
            out += [f"**Attempt {a['n']}: arena → model**", "", "```", prompt, "```", "",
                    f"**model → arena** ({a['seconds']}s" + (f", {a['usage'].get('input', 0)} in / {a['usage'].get('output', 0)} out tokens" if a.get("usage") else "") + ")", "", "```",
                    a["raw"] if a["raw"] else f"(no text; error: {a.get('error')})", "```", ""]
            verdict = "legal, played" if a["legal"] else ("ILLEGAL (" + repr(a["parsed"]) + "), model asked to retry" if a.get("parsed") else "no move found, model asked to retry")
            out.append(f"**verifier**: {verdict}")
            out.append("")
        if p.get("san"):
            ev = p["eval_after"]
            evs = ev.get("terminal") or (f"mate in {ev['mate']}" if ev.get("mate") is not None else (f"{ev['cp'] / 100:+.2f}" if ev.get("cp") is not None else "-"))
            flags = []
            if p["was_best"]: flags.append("Stockfish's top choice")
            elif p["in_top3"]: flags.append("in Stockfish's top 3")
            if p["loss_pawns"] >= 2: flags.append(f"blunder, lost {p['loss_pawns']:.1f} pawns")
            if p["forced_random"]: flags.append("forced random move")
            out.append(f"**Stockfish after {p['san']}**: eval {evs}; best was {p['best_move']}" + (f"; {', '.join(flags)}" if flags else ""))
            out.append("")
            board.push(chess.Move.from_uci(p["uci"]))
        else:
            out.append(f"**verifier**: {side} forfeits, {len(p['attempts'])} attempts without a legal move.")
            out.append("")
    return "\n".join(out)


def main():
    d = sys.argv[1]
    for j in sorted(glob.glob(os.path.join(d, "game*.json"))):
        md = j[:-5] + "_transcript.md"
        open(md, "w", encoding="utf-8").write(transcript(j))
        print(md)


if __name__ == "__main__":
    main()
