import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from arena import prompt
from arena.game import Game
from arena.players import Player, RandomPlayer, Reply
from arena.session import Session, apply


def test_parse():
    assert prompt.parse("Tube 3 has red on top.\nMOVE 3 13") == ("move", 3, 13)
    assert prompt.parse("reason\n\n**move 3 to 13**\n") == ("move", 3, 13)
    assert prompt.parse("`UNDO`") == ("undo",) and prompt.parse("ok\nRestart.") == ("restart",)
    assert prompt.parse("MOVE 3 13\nthat should work") is None      # command must be the last line
    assert prompt.parse("MOVE three four") is None and prompt.parse("") is None
    assert prompt.parse("I will MOVE 3 13") is None


def test_apply_feedback():
    g = Game(4, ["abcc", "aba", "", ""])
    assert apply(g, "MOVE 1 3") == (("move", 1, 3), True, "OK: poured 2 layers of green from tube 1 to tube 3.")
    cmd, ok, fb = apply(g, "MOVE 1 2")
    assert not ok and fb.startswith("FOUL") and "blue" in fb and g.pours == 1
    assert apply(g, "UNDO")[1] and not apply(g, "UNDO")[1]
    assert apply(g, "hmm")[0] is None
    assert apply(g, "RESTART")[2] == "OK: restarted. This is attempt 2."


def test_board_text():
    g = Game(4, ["abcc", "aba", "", ""])
    assert prompt.board_text(g, 500).splitlines()[-4:] == [" 1: ? ? green green", " 2: ? ? red", " 3: (empty)", " 4: (empty)"]


class Scripted(Player):
    name, model, vendor = "Scripted", "scripted", "random"

    def __init__(self, replies):
        self.replies, self.seen = list(replies), []

    def chat(self, system, messages):
        self.seen.append([dict(m) for m in messages])
        return Reply(self.replies.pop(0), 0.5, {"input": 10, "output": 2})


def test_session_solves_logs_and_counts(tmp_path):
    script = ["MOVE 1 3", "MOVE 9 9", "UNDO", "MOVE 1 3", "RESTART", "MOVE 1 3", "MOVE 2 1", "MOVE 2 3"]
    p = Scripted(script)
    s = Session(0, 2, ["ab", "ba", ""], p, "medium", tmp_path / "turns.jsonl", max_pours=50)
    while s.step():
        pass
    summ = s.summary(optimal=3)
    assert (summ["status"], summ["solved"], summ["solution_pours"], summ["over_optimal"]) == ("solved", True, 3, 0)
    assert (summ["total_pours"], summ["undos"], summ["restarts"], summ["attempts"], summ["fouls"], summ["turns"]) == (5, 1, 1, 2, 1, 8)
    assert summ["solution"] == [(1, 3), (2, 1), (2, 3)]
    # one conversation: the last call saw every earlier board and reply
    assert len(p.seen[-1]) == 15 and p.seen[-1][1] == {"role": "assistant", "content": "MOVE 1 3"}
    assert p.seen[-1][-1]["content"].startswith("OK: poured 1 layer of red from tube 2 to tube 1.")
    rows = [json.loads(x) for x in (tmp_path / "turns.jsonl").read_text().splitlines()]
    assert rows[0]["type"] == "header" and len(rows) == 9 and rows[-1]["won"]


def test_resume_rebuilds_state_without_new_calls(tmp_path):
    log = tmp_path / "turns.jsonl"
    a = Session(0, 2, ["ab", "ba", ""], Scripted(["MOVE 1 3", "nonsense", "MOVE 2 1"]), "medium", log, max_pours=50)
    for _ in range(3):
        a.step()
    p = Scripted(["MOVE 2 3"])
    b = Session(0, 2, ["ab", "ba", ""], p, "medium", log, max_pours=50)
    assert (b.turns, b.fouls, b.game.pours, b.messages) == (3, 1, 2, a.messages)
    assert not b.step() and b.status == "solved" and len(p.seen) == 1


def test_pour_limit_ends_session(tmp_path):
    p = Scripted(["MOVE 1 3", "UNDO"] * 5)
    s = Session(0, 2, ["ab", "ba", ""], p, "medium", tmp_path / "t.jsonl", max_pours=3)
    while s.step():
        pass
    assert s.status == "pour_limit" and s.game.pours == 3 and not s.summary()["solved"]


def test_api_errors_stop_the_session_and_can_resume(tmp_path, monkeypatch):
    monkeypatch.setattr("time.sleep", lambda s: None)

    class Flaky(Player):
        name, model, vendor = "Flaky", "flaky", "random"

        def chat(self, system, messages):
            return Reply("", 0.1, error="boom")

    s = Session(0, 2, ["ab", "ba", ""], Flaky(), "medium", tmp_path / "t.jsonl")
    assert not s.step() and s.status == "api_error" and s.turns == 0
    s2 = Session(0, 2, ["ab", "ba", ""], Flaky(), "medium", tmp_path / "t.jsonl")
    assert s2.turns == 0 and s2.status == "running" and len(s2.messages) == 1


def test_random_player_dry_run_on_286(tmp_path):
    from arena.game import load_level
    cap, tubes, _ = load_level(286)
    s = Session(286, cap, tubes, RandomPlayer(3), "medium", tmp_path / "t.jsonl", max_pours=60)
    while s.step():
        pass
    assert s.status in ("pour_limit", "solved") and s.fouls > 0 and s.game.undos > 0


def test_prices():
    from datetime import datetime, timezone
    from arena.prices import call_cost
    u = {"input": 1_000_000, "cached": 900_000, "cache_write": 50_000, "output": 100_000}
    assert abs(call_cost("claude-fable-5-2", u) - (50_000 * 8 + 50_000 * 10 + 900_000 * 0.2 + 100_000 * 40) / 1e6) < 1e-9
    assert abs(call_cost("gpt-6.2-astra", {"input": 1_000_000, "cached": 500_000, "output": 0}) - (4 + 0.2)) < 1e-9
    offpeak = datetime(2026, 11, 21, 3, 0, tzinfo=timezone.utc)   # Saturday
    assert abs(call_cost("deepseek-v4-pro", {"input": 1_000_000, "output": 1_000_000}, offpeak) - (4.5 + 13.5) / 7.1) < 1e-9
    assert call_cost("unknown-model", {"input": 1}) is None
