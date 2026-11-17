#!/usr/bin/env python3
"""Shortest solution of a Water Sort level with the whole board visible (the "perfect information" reference line).

A* over canonical states (tube order ignored). Heuristic: every run of same-coloured layers has to be poured at least
once, except one run per colour that already sits at the bottom of a tube and can stay there; a pour moves layers of one
run only, so  h = runs - colours_with_a_bottom_run  never overestimates. With --weight 1 the answer is provably
optimal; a larger weight finds a (possibly longer) solution fast and is reported as "best known".

Usage: python3 solve.py 286 [--weight 1.0] [--max-states 30000000] [--out results/solver_286.json]
"""
from __future__ import annotations

import argparse
import heapq
import json
import time

from arena.game import Game, load_level


def runs(t: str) -> int:
    return sum(1 for k in range(len(t)) if k == 0 or t[k] != t[k - 1])


def h(state: tuple[str, ...]) -> int:
    return sum(runs(t) for t in state) - len({t[0] for t in state if t})


def neighbours(state: tuple[str, ...], cap: int):
    seen_empty = False
    targets = []
    for j, b in enumerate(state):
        if not b:
            if seen_empty:
                continue          # all empty tubes are interchangeable
            seen_empty = True
        targets.append(j)
    for i, a in enumerate(state):
        if not a:
            continue
        top = a[-1]
        run = len(a) - len(a.rstrip(top))
        if run == len(a) and len(a) == cap:
            continue              # finished tube
        for j in targets:
            b = state[j]
            if i == j or len(b) == cap or (b and b[-1] != top):
                continue
            if not b and run == len(a):
                continue          # moving a single-colour tube into an empty one changes nothing
            k = min(run, cap - len(b))
            t = list(state)
            t[i], t[j] = a[:-k], b + top * k
            yield (a, b), tuple(sorted(t))


def solve(cap: int, tubes: list[str], weight: float = 1.0, max_states: int = 30_000_000):
    """→ (list of (source string, target string) pours on canonical states or None, states expanded)."""
    start = tuple(sorted(tubes))
    done = lambda s: all(not t or (len(t) == cap and len(set(t)) == 1) for t in s)
    g = {start: 0}
    parent: dict = {start: None}
    heap = [(weight * h(start), 0, start)]
    expanded = 0
    while heap:
        f, negg, s = heapq.heappop(heap)
        if -negg > g[s]:
            continue
        if done(s):
            path = []
            while parent[s]:
                s, mv = parent[s]
                path.append(mv)
            return path[::-1], expanded
        expanded += 1
        if expanded > max_states:
            return None, expanded
        for mv, n in neighbours(s, cap):
            ng = g[s] + 1
            if ng < g.get(n, 1 << 30):
                g[n] = ng
                parent[n] = (s, mv)
                heapq.heappush(heap, (ng + weight * h(n), -ng, n))
    return None, expanded


def to_tube_moves(cap: int, tubes: list[str], path) -> list[tuple[int, int]]:
    """Replay the canonical path on the real tube order → 1-based (from, to) pours, verified with the game engine."""
    game = Game(cap, tubes, fog=False)
    out = []
    for a, b in path:
        cur = ["".join(t) for t in game.tubes]
        src = cur.index(a)
        dst = next(j for j, t in enumerate(cur) if t == b and j != src)
        assert game.why_illegal(src + 1, dst + 1) is None
        game.pour(src + 1, dst + 1)
        out.append((src + 1, dst + 1))
    assert game.won()
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("level", type=int)
    ap.add_argument("--weight", type=float, default=1.0)
    ap.add_argument("--max-states", type=int, default=30_000_000)
    ap.add_argument("--out")
    a = ap.parse_args()
    cap, tubes, fog = load_level(a.level)
    t0 = time.time()
    path, expanded = solve(cap, tubes, a.weight, a.max_states)
    res = {"level": a.level, "capacity": cap, "tubes": tubes, "lower_bound": h(tuple(tubes)), "weight": a.weight,
           "states_expanded": expanded, "seconds": round(time.time() - t0, 1)}
    if path is None:
        res["solved"] = False
    else:
        moves = to_tube_moves(cap, tubes, path)
        res.update(solved=True, moves=len(moves), optimal=a.weight <= 1.0, path=moves)
    print(json.dumps({k: v for k, v in res.items() if k != "path"}))
    if a.out:
        json.dump(res, open(a.out, "w"), indent=1)
