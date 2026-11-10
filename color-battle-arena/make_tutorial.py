#!/usr/bin/env python3
"""Teaching material for round 2 ("我们来教"): every skill at level 3 demonstrated once in the real simulation.

    python3 make_tutorial.py            # → tutorial/tutorial.json + tutorial/tutorial.md (English only: fed to the models, shown in the video)

Method (user 2026-11-09): take one real mid-game board (seed 1001, the game's own bots steering all four teams for 30 s),
give team A one skill at level 3, and cast it twice from the same position:
  - "aimed":   the ball is first pointed at the enemy mass (target skills get a chosen point: densest enemy spot for FIRE,
               a pocket deep inside enemy territory for TELEPORT), then the skill is cast;
  - "unaimed": cast as is, wherever the ball happens to be heading.
The world then runs 6 more seconds (bots keep steering B–D). A control run with the same turn but no cast gives the
baseline, so "effect" = cells gained with the cast minus cells gained without it. Boards before / after (aimed case)
are included as text so the models can see what the skill does to the map, plus one tip per skill written by us.
Everything is deterministic (same seed, same commands), so the material is reproducible with this script.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from arena.prompt import SKILL_HELP  # noqa: E402
from arena.sim import FIXED_DT, LETTERS, ColorBattle  # noqa: E402

SEED = 1001
T0 = 30.0            # the board shown in the material
BOARDS = (20.0, 30.0, 40.0)   # effects are averaged over casts on these three moments of the same game (one board is noisy: the bots react)
INSTANT = 1.0        # seconds after the cast for the "instant" effect
WATCH = 6.0          # seconds observed after the cast
LEVEL = 3
OUT = Path(__file__).parent / "tutorial"

ZH = {"freeze": "冰冻", "split": "分身", "accel": "加速", "bomb": "炸弹", "giant": "巨球", "fire": "火焰", "lightning": "闪电",
      "teleport": "传送", "shatter": "碎裂", "shock": "冲击波", "chain": "链式闪电", "snowball": "等离子"}

# our summary, one tip per skill (en for the models, zh for the video). Written from the rules + what we saw in play.
TIPS = {
    "freeze": ("Freeze slows (or at level 3 stops) enemy balls that the wave reaches; it paints nothing itself. It is only worth a slot if you plan to use the frozen seconds to paint inside their area.",
               "冰冻只减速 / 定住被波及的敌球，自己不染格；只有打算趁对手定住的几秒冲进去染色时才值得带。"),
    "split": ("Split copies your main ball into 5 for 4 s. The copies start where your ball is, so cast it when the ball is already inside or at the edge of enemy territory, not deep in your own colour where there is nothing to flip.",
              "分身把主球复制成 5 颗、持续 4 秒，分身从主球所在位置出发，所以要在球已经进到敌区或贴着边界时放，在自家地盘里放没东西可染。"),
    "accel": ("Accel doubles the speed of all your balls for 6 s on an 8 s cooldown, so it can be active most of the game. It multiplies whatever else is happening: pair it with split / shatter / giant, or with a ball heading into enemy ground.",
              "加速让所有己方球双倍速 6 秒、冷却 8 秒，几乎可以常驻；它放大其他一切效果，和分身 / 碎裂 / 巨球或一颗正冲向敌区的球搭配最好。"),
    "bomb": ("Bomb makes the main ball paint 3 extra neighbouring cells on every bounce for 7 s. Good when the ball is bouncing along an enemy border; useless while it cruises through your own colour.",
             "炸弹让主球 7 秒内每次反弹多染 3 个相邻格；球在敌方边界上来回弹时最好用，在自家颜色里巡航时没用。"),
    "giant": ("At level 3 the giant ball PIERCES for 3 s: it does not bounce, it ploughs straight through enemy cells painting a wide trail. Point the ball at the biggest enemy block first, then cast; saved for the last seconds it can swing the result.",
              "3 级巨球 3 秒内穿透不反弹，笔直犁过敌区留下一条宽带；先把球对准对手最大的一块地再放。留到最后几秒放，一下能改写排名。"),
    "fire": ("Fire paints a circle of radius 3 (about 29 cells) at any point you choose, after a short delay. Aim at the densest enemy area, not at neutral or your own cells, and keep it ready for the final seconds when the paint cannot be undone.",
             "火焰在你指定的点染一个半径 3 的圆（约 29 格），稍有延迟。瞄准对手最密的地方，别浪费在中立或自家格子上；留到最后几秒放，染上就没人能改回去。"),
    "lightning": ("Lightning paints four lines from your ball to the edges, up to ~63 cells, no aiming needed. It is worth most when your ball sits in the middle of the board or inside enemy colour, so that the lines cross their cells instead of yours.",
                  "闪电从球所在格向四个方向画到边缘，最多约 63 格，不用瞄准；球在棋盘中部或敌区里时最划算，让线穿过对手的格子而不是自己的。"),
    "teleport": ("Teleport moves the main ball to any point instantly. Do not teleport onto open enemy ground: pick a SMALL pocket enclosed by enemy cells; the ball bounces back and forth in the pocket and repaints a big patch very fast. Teleporting into your own colour wastes it.",
                 "传送把主球瞬间移到任意点。别传到敌区的开阔地：要选一个被敌方格子包围的小口袋，球在口袋里快速来回弹，很快把周围一大块刷成自己的颜色。传回自家地盘等于白放。"),
    "shatter": ("Shatter: for 7 s every cell your balls flip spawns a short-lived extra ball, up to 16. It snowballs only where there is foreign colour to flip, so trigger it as the ball enters enemy or neutral ground, ideally together with accel.",
                "碎裂 7 秒内每染一个格就从撞点生出一颗小球，最多 16 颗；只有在有别人颜色可染的地方才会滚雪球，所以要在球进入敌区或中立区时放，最好配合加速。"),
    "shock": ("Shockwave sends an arc of 120° forward from the ball; each ray paints the first non-own cell it meets. Aim the ball at the enemy mass first: fired into your own colour the rays travel far and paint little.",
              "冲击波从球的正前方张开 120° 的扇面，每条射线染遇到的第一个非己方格；先把球对准敌方大块地再放，朝自家颜色放射线要飞很远才染到一格。"),
    "chain": ("Chain lightning stuns every enemy ball for 2.5 s and paints nothing. Use it when you are about to paint a lot (giant, split active) so nobody can answer; otherwise it is a wasted slot.",
              "链式闪电定住所有敌球 2.5 秒，自己不染格。只在你马上要大量染色（巨球、分身生效中）时用，让对手无法回应；否则是浪费的一个位置。"),
    "snowball": ("Plasma grows your main ball on each hit; after 5 hits the next hit bursts and paints a circle around it. It needs the ball to keep hitting foreign cells, so it pays off along contested borders, not at home.",
                 "等离子球每撞一次变大，撞够 5 次后再撞一下爆开染一圈；需要球不断撞到别人的格子，在争夺中的边界上才有收益，在家里没用。"),
}


def fresh(skill: str, t0: float = T0) -> ColorBattle:
    cb = ColorBattle(SEED, [(skill, LEVEL)], team1_only=True)
    for t in range(2, 5):
        cb.add_bot(t, 0.6)
    for _ in range(int(t0 / FIXED_DT)):
        cb.step()
    return cb


def grid_cells(grid: list[str], letter: str) -> list[tuple[int, int]]:
    return [(i, j) for j, row in enumerate(grid) for i, ch in enumerate(row) if ch == letter]


def centroid(cells):
    return (sum(c[0] for c in cells) / len(cells) + 0.5, sum(c[1] for c in cells) / len(cells) + 0.5)


def enemy_centroid(grid):
    cells = [c for L in "BCD" for c in grid_cells(grid, L)]
    return centroid(cells)


def densest_enemy_spot(grid, radius=3):
    best, best_n = None, -1
    for j in range(32):
        for i in range(32):
            n = sum(1 for dj in range(-radius, radius + 1) for di in range(-radius, radius + 1)
                    if 0 <= i + di < 32 and 0 <= j + dj < 32 and di * di + dj * dj <= radius * radius and grid[j + dj][i + di] in "BCD")
            if n > best_n:
                best, best_n = (i + 0.5, j + 0.5), n
    return best, best_n


def enemy_pocket(grid):
    """enemy cell whose 5×5 neighbourhood is all enemy colour, as far from our cells as possible"""
    ours = grid_cells(grid, "A")
    best, best_d = None, -1
    for j in range(2, 30):
        for i in range(2, 30):
            if grid[j][i] not in "BCD":
                continue
            if all(grid[j + dj][i + di] in "BCD" for dj in range(-2, 3) for di in range(-2, 3)):
                d = min(math.hypot(i - a, j - b) for a, b in ours)
                if d > best_d:
                    best, best_d = (i + 0.5, j + 0.5), d
    return best


def mark(grid, balls):
    g = [list(r) for r in grid]
    for t, bl in balls.items():
        for k, (x, y, _, _) in enumerate(bl):
            i, j = min(31, max(0, int(x))), min(31, max(0, int(y)))
            g[j][i] = "@" if (t == 1 and k == 0) else LETTERS[t - 1].lower()
    return "\n".join(f"{j + 1:>2} {''.join(r)}" for j, r in enumerate(g))


def own_centroid(grid):
    return centroid(grid_cells(grid, "A"))


def run(skill: str, aimed: bool, cast: bool, t0: float = T0) -> dict:
    cb = fresh(skill, t0)
    snap = cb.snapshot()
    grid, (bx, by, bdx, bdy) = snap.grid, snap.balls[1][0]
    target = None
    if skill in ("teleport", "fire"):   # target skills always need a point; unaimed = the naive choice
        if aimed:
            target = (enemy_pocket(grid) or densest_enemy_spot(grid)[0]) if skill == "teleport" else densest_enemy_spot(grid)[0]
        else:
            target = own_centroid(grid) if skill == "teleport" else (min(31.5, max(0.5, bx)), min(31.5, max(0.5, by)))
    elif aimed:
        ex, ey = enemy_centroid(grid)
        cb.command(1, {"type": "turn", "x": ex, "y": ey})
    before = cb.snapshot()   # BEFORE the cast: lightning / shockwave paint inside the command itself
    accepted = None
    if cast:
        cmd = {"type": "cast", "slot": 1}
        if target:
            cmd["x"], cmd["y"] = target
        accepted = cb.command(1, cmd)
    for _ in range(int(INSTANT / FIXED_DT)):
        cb.step()
    instant = cb.snapshot().counts[1] - before.counts[1]
    for _ in range(int((WATCH - INSTANT) / FIXED_DT)):
        cb.step()
    after = cb.snapshot()
    return {"accepted": accepted, "target": target, "ball": (round(bx, 1), round(by, 1)),
            "before_counts": before.counts, "after_counts": after.counts,
            "before_board": mark(before.grid, before.balls), "after_board": mark(after.grid, after.balls),
            "instant": instant, "gain": after.counts[1] - before.counts[1]}


def measure(skill: str, aimed: bool) -> dict:
    """mean effect over BOARDS: instant (1 s) and over WATCH seconds, cast minus control"""
    inst, eff, runs = [], [], {}
    for t0 in BOARDS:
        c, ctl = run(skill, aimed, True, t0), run(skill, aimed, False, t0)
        inst.append(c["instant"] - ctl["instant"]); eff.append(c["gain"] - ctl["gain"])
        runs[t0] = (c, ctl)
    show, show_ctl = runs[T0]
    return {"ball": show["ball"], "target": show["target"], "accepted": show["accepted"], "instant": round(sum(inst) / len(inst)), "effect": round(sum(eff) / len(eff)),
            "per_board": {str(t0): {"instant": inst[k], "effect": eff[k]} for k, t0 in enumerate(BOARDS)},
            "gain": show["gain"], "control_gain": show_ctl["gain"], "before_board": show["before_board"], "after_board": show["after_board"],
            "before_counts": show["before_counts"], "after_counts": show["after_counts"]}


def main():
    OUT.mkdir(exist_ok=True)
    cb = fresh("fire")
    cfg = cb.config
    skills = [str(cfg.SKILL_IDS[k]) for k in range(1, len(cfg.SKILL_IDS) + 1)]
    result = {"seed": SEED, "t0": T0, "boards": BOARDS, "instant": INSTANT, "watch": WATCH, "level": LEVEL, "skills": {}}
    for sk in skills:
        d = cfg.SKILLS[sk]
        params = {}
        for key in ("radius", "mult", "dur", "count", "window", "arc", "stun", "extra", "max", "life", "steps"):
            v = d[key]
            if v is not None:
                params[key] = float(v[LEVEL])
        text = SKILL_HELP.get(sk, sk).format(r=params.get("radius", ""), m=params.get("mult", ""), d=params.get("dur", ""), c=params.get("count", ""),
                                             w=params.get("window", ""), a=params.get("arc", ""), s=params.get("stun", ""), e=params.get("extra", ""))
        a, u = measure(sk, True), measure(sk, False)
        result["skills"][sk] = {"name": str(d.name), "zh": ZH[sk], "cd": float(d.cd[LEVEL]), "target": bool(d.target), "params": params, "text": text,
                                "tip": TIPS[sk][0], "tip_zh": TIPS[sk][1], "aimed": a, "unaimed": u}
        print(f"{sk:10s} aimed: instant {a['instant']:+4d} / 6 s {a['effect']:+4d}   unaimed: instant {u['instant']:+4d} / 6 s {u['effect']:+4d}   target {a['target']}")
    (OUT / "tutorial.json").write_text(json.dumps(result, ensure_ascii=False, indent=1))
    result["strategy"] = [ln for ln in STRATEGY if ln.startswith("- ")]
    (OUT / "tutorial.json").write_text(json.dumps(result, ensure_ascii=False, indent=1))
    (OUT / "tutorial.md").write_text(render(result, "en"))   # English only: this is what the models read and what the video shows (user 2026-11-09)
    print("→", OUT / "tutorial.md")


STRATEGY = [
    "## Combos and strategy (our notes)",
    "",
    "- **Teleport + Shatter (or Split).** Teleport into a SMALL pocket enclosed by one enemy colour, then cast Shatter (or Split) at once. "
    "Inside the pocket the ball flips a cell on almost every bounce; with Shatter every flip spawns another ball (1 → 2 → 4 → …), with Split you "
    "have five balls doing it. A whole region of that colour collapses within a few seconds. This is the strongest thing in the game when it lands.",
    "- **Hit the leader, not everyone.** Look at the cell counts: aim teleports, fires, giants and shockwaves at the team that is currently first. "
    "You do not need to out-paint the whole board; knocking the leader's biggest block down is usually what makes you first.",
    "- **Shockwave grows with distance.** The arc widens as it travels, so cast it from FAR away, pointed at a big enemy block: the rays spread "
    "out and paint a wide front. Cast right next to the enemy the arc is still narrow and paints only a few cells.",
    "- **Giant and Fire are finishers.** Their paint cannot be answered in the last seconds: keep one charge for the final 5 s and put it into the "
    "leader's territory.",
    "- **Accel is a multiplier, not a plan.** It only pays when something else is happening: a ball driving into enemy ground, Shatter or Split active, "
    "a Giant run.",
    "",
]


def render(r: dict, lang: str) -> str:
    out = []
    if lang == "en":
        out += [f"# Skill study material (all skills at level {r['level']})", "",
                f"Every skill was cast once on the same real board: seed {r['seed']}, after {r['t0']:g} s of play, you are team A (your ball is '@').",
                f"'Effect' = cells you gained after the cast minus what you would have gained without casting, measured {r['instant']:g} s after the cast (instant) and {r['watch']:g} s after (lasting); each number is the average of the same cast made at three moments of the game ({', '.join(f'{b:g}' for b in r['boards'])} s).",
                "'Aimed' = the ball was first pointed at the enemy mass (FIRE: densest enemy spot; TELEPORT: a pocket enclosed by enemy cells). 'Unaimed' = cast as is.",
                "Boards: '.' neutral, A–D owner, lowercase = that team's ball, '@' = your ball.", ""]
    else:
        out += [f"# 技能教材（全部 {r['level']} 级）", "",
                f"每个技能都在同一个真实局面上放一次：种子 {r['seed']}，开局 {r['t0']:g} 秒后，我方是 A 队（球是 '@'）。",
                f"\"效果\" = 放招后多出的格子减去不放招也会多出的格子，分别在放招后 {r['instant']:g} 秒（即时）和 {r['watch']:g} 秒（持续）量；每个数字是同一招在这局 {'、'.join(f'{b:g}' for b in r['boards'])} 秒三个时刻各放一次的平均。",
                "\"瞄准\" = 先把球对准敌方大块地（火焰：对手最密处；传送：敌区内的口袋）再放；\"不瞄准\" = 原地直接放。", ""]
    if lang == "en":
        out += STRATEGY
    for sk, s in r["skills"].items():
        a, u = s["aimed"], s["unaimed"]
        if lang == "en":
            out += [f"## {s['name']} ({sk})", "", f"- Rule: {s['text']} Cooldown {s['cd']:g} s.",
                    f"- Demo, aimed: ball at {a['ball']}" + (f", target {tuple(round(v, 1) for v in a['target'])}" if a['target'] else "") + f": instant **{a['instant']:+d} cells**, after {r['watch']:g} s **{a['effect']:+d} cells**.",
                    f"- Demo, unaimed: instant **{u['instant']:+d}**, after {r['watch']:g} s **{u['effect']:+d} cells**.",
                    f"- Our tip: {s['tip']}", "",
                    "Board at the cast (aimed) → board 6 s later:", "```", a["before_board"], "", a["after_board"], "```", ""]
        else:
            out += [f"## {s['zh']}（{s['name']}）", "", f"- 规则：{s['text']} 冷却 {s['cd']:g} 秒。",
                    f"- 演示·瞄准：球在 {a['ball']}" + (f"，落点 {tuple(round(v, 1) for v in a['target'])}" if a['target'] else "") + f"：即时 **{a['instant']:+d} 格**，{r['watch']:g} 秒后 **{a['effect']:+d} 格**。",
                    f"- 演示·不瞄准：即时 **{u['instant']:+d}**，{r['watch']:g} 秒后 **{u['effect']:+d} 格**。",
                    f"- 我们的总结：{s['tip_zh']}", "",
                    "放招时的棋盘（瞄准）→ 6 秒后：", "```", a["before_board"], "", a["after_board"], "```", ""]
    return "\n".join(out)


if __name__ == "__main__":
    main()
