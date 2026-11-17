import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from arena.game import Game, load_level


def test_level_286():
    cap, tubes, fog = load_level(286)
    assert (cap, fog, len(tubes)) == (5, True, 14)
    assert tubes[0] == "idhfi" and tubes[-2:] == ["", ""]
    flat = "".join(tubes)
    assert sorted(set(flat)) == list("abcdefghijkl") and all(flat.count(c) == 5 for c in set(flat))


def test_level_numbering_matches_file():
    assert load_level(1) == (4, ["accb", "caba", "bcba", "", ""], False)
    assert load_level(5)[2] is True


def test_fog_shows_only_top_run():
    g = Game(4, ["abcc", "abba", "", ""])
    assert g.view() == [["?", "?", "green", "green"], ["?", "?", "?", "red"], [], []]


def test_pour_moves_whole_run_and_reveals():
    g = Game(4, ["abcc", "abba", "", ""])
    assert g.pour(1, 3) == 2
    assert g.view()[0] == ["?", "blue"] and g.view()[2] == ["green", "green"]
    assert g.pour(2, 4) == 1
    assert g.view()[1] == ["?", "blue", "blue"]


def test_partial_pour_when_target_lacks_room():
    g = Game(4, ["baa", "cca", ""], fog=False)
    assert g.pour(1, 2) == 1
    assert g.tubes[0] == ["b", "a"] and g.tubes[1] == list("ccaa")


def test_illegal_moves():
    g = Game(4, ["abcc", "aba", "cc", ""])
    assert "empty" in g.why_illegal(4, 1)
    assert "full" in g.why_illegal(3, 1)
    assert "green" in g.why_illegal(1, 2) and "red" in g.why_illegal(1, 2)
    assert "same tube" in g.why_illegal(1, 1)
    assert "1 to 4" in g.why_illegal(0, 9)
    assert g.why_illegal(1, 3) is None and g.why_illegal(2, 4) is None


def test_undo_restores_tubes_fog_and_counts():
    g = Game(4, ["abcc", "abba", "", ""])
    before = (g.view(), [t[:] for t in g.tubes])
    g.pour(1, 3)
    g.undo()
    assert (g.view(), g.tubes) == before
    assert (g.pours, g.undos, g.path, g.can_undo()) == (1, 1, [], False)


def test_restart_refogs_and_keeps_totals():
    g = Game(4, ["abcc", "abba", "", ""])
    g.pour(1, 3); g.pour(1, 4)
    g.restart()
    assert g.view()[0] == ["?", "?", "green", "green"]
    assert (g.pours, g.restarts, g.attempts, g.path) == (2, 1, 2, [])


def test_win():
    g = Game(2, ["ab", "ba", ""], fog=False)
    for s, d in ((1, 3), (2, 1), (2, 3)):
        g.pour(s, d)
    assert g.won() and g.path == [(1, 3), (2, 1), (2, 3)]
