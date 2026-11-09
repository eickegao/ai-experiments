#!/usr/bin/env python3
"""Local server behind the in-game arena mode (game/games/clashdoz/arena.lua, docs/2026-11-09-arena-mode-design.md).

It serves the web bundle (same origin, so the game can call it without CORS) and answers three calls from the game:

  POST /draft    {game, catalog, n_decisions, decision_dt}  → each seat picks its skills (LLMs are asked; bots / random roll)
  POST /decide   {game, tick, t, time_left, counts, grid, balls, skills, turn_cd, frozen, last}
                 → the four models are asked in parallel; replies parsed into commands → {cmds: {A: [...], ...}, note: {...}}
  POST /finish   {game, commands, timeline, final}  → results/<run>/game_N.json + game_N.md + summary.md

Everything an LLM sees and says is recorded per call (prompt, raw reply, seconds, tokens, USD), as in the headless harness.

  python3 arena_server.py --players random,random,bot,bot --out results/dry --port 8787
  python3 arena_server.py --players claude,openai,gemini,deepseek --out results/2026-11-10_live
  then open  http://127.0.0.1:8787/index.html?arena=live&game=1   (record_match.py does this headless and records the replay)

Seat rotation: in game g player k sits at team (k + g - 1) mod 4, so every player starts in every corner once over 4 games.
"""
from __future__ import annotations

import argparse
import json
import os
import random
import re
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from arena.players import make_player, Player, Reply  # noqa: E402
from arena.prices import call_cost  # noqa: E402
from arena.prompt import SKILL_HELP, fmt_cmd, observation, parse, system_prompt  # noqa: E402
from arena.sim import LETTERS, Snapshot  # noqa: E402

HERE = Path(__file__).resolve().parent
DEFAULT_SKILLS = ["fire", "lightning", "teleport"]


def load_env():
    p = HERE.parent / ".env"
    if p.exists():
        for line in p.read_text().splitlines():
            if "=" in line and not line.strip().startswith("#"):
                k, _, v = line.partition("=")
                os.environ.setdefault(k.strip(), v.strip())


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


# ---------------------------------------------------------------- draft
def skill_text(sk: dict) -> str:
    p = sk.get("params", {})
    return SKILL_HELP.get(sk["id"], sk["id"]).format(r=p.get("radius", ""), m=p.get("mult", ""), d=p.get("dur", ""), c=p.get("count", ""),
                                                      w=p.get("window", ""), a=p.get("arc", ""), s=p.get("stun", ""), e=p.get("extra", ""))


def draft_prompts(catalog: list[dict], slots: int, n_decisions: int, decision_dt: float) -> tuple[str, str]:
    system = "\n".join([
        "You are one of four AI players about to play Color Battle, a 60-second territory game on a 32x32 board.",
        "Each team has one ball that moves at 22 cells/s. It passes freely over its own colour; when it touches a cell of any",
        "other colour it paints that cell your colour and bounces back. Balls bounce off the board edges. Most cells wins.",
        f"During the game you decide every {decision_dt:g} s of game time ({n_decisions} decisions): point the ball somewhere (1 s cooldown)",
        "and cast your skills (each has its own cooldown). Before the game starts, every team picks its skills from the same list.",
    ])
    lines = [f"Pick exactly {slots} different skills from this list (all level 1). Your opponents pick independently.", ""]
    for sk in catalog:
        lines.append(f"- {sk['id']}: {skill_text(sk)} Cooldown {sk['cd']:g} s.")
    lines += ["", "Reply with brief reasoning (under 80 words), then one last line exactly like:", f"PICK: {', '.join(['<id>'] * slots)}"]
    return system, "\n".join(lines)


PICK_RE = re.compile(r"PICK\s*[:：]\s*(.+)", re.IGNORECASE)


def parse_pick(text: str, valid: list[str], slots: int, rng: random.Random) -> tuple[list[str], str]:
    """Return the chosen ids (padded to `slots` with defaults, then random) and a note on what was fixed."""
    m = None
    for m in PICK_RE.finditer(text or ""):
        pass
    found = []
    if m:
        for tok in re.split(r"[,\s]+", m.group(1).lower()):
            tok = tok.strip(".*`'\"")
            if tok in valid and tok not in found:
                found.append(tok)
    found = found[:slots]
    note = ""
    if len(found) < slots:
        pool = [i for i in DEFAULT_SKILLS if i in valid and i not in found] + [i for i in valid if i not in found and i not in DEFAULT_SKILLS]
        rng.shuffle(pool[len(DEFAULT_SKILLS):])
        fill = pool[: slots - len(found)]
        note = f"only {len(found)} valid pick(s) found; filled with {', '.join(fill)}"
        found += fill
    return found, note


# ---------------------------------------------------------------- per-game state
class Game:
    def __init__(self, no: int, seed: int, players: dict[int, Player], slots: int, effort: str):
        self.no, self.seed, self.players, self.slots = no, seed, players, slots
        self.lock = threading.Lock()
        self.setup: dict | None = None
        self.catalog: list[dict] = []
        self.systems: dict[int, str] = {}
        self.n_decisions = 30
        self.decision_dt = 2.0
        self.record: dict = {
            "seed": seed, "game": no, "started": now(), "effort": effort,
            "players": {LETTERS[t - 1]: {"name": p.name, "model": p.model, "vendor": p.vendor, "llm": p.is_llm} for t, p in players.items()},
            "draft": {}, "decisions": [], "commands": [], "timeline": [], "final": None,
        }
        self.done = False

    # ---- draft -----------------------------------------------------------------------------------------------------
    def draft(self, catalog: list[dict], n_decisions: int, decision_dt: float, log) -> dict:
        self.catalog, self.n_decisions, self.decision_dt = catalog, n_decisions, decision_dt
        valid = [sk["id"] for sk in catalog]
        system, user = draft_prompts(catalog, self.slots, n_decisions, decision_dt)
        rng = random.Random(self.seed)
        teams = {}

        def ask(t: int):
            p = self.players[t]
            if not p.is_llm or p.vendor == "random":
                picks = rng.sample(valid, self.slots)
                return t, picks, None, ""
            r = p.decide(system, user)
            picks, note = parse_pick(r.text, valid, self.slots, rng) if not r.error else (rng.sample(valid, self.slots), f"reply failed: {r.error}")
            return t, picks, r, note

        with ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(ask, sorted(self.players)))
        for t, picks, r, note in results:
            p = self.players[t]
            L = LETTERS[t - 1]
            teams[L] = {"name": p.name, "model": p.model, "bot": not p.is_llm, "skills": [{"id": i, "level": 1} for i in picks]}
            self.record["draft"][L] = {
                "picks": picks, "note": note, "prompt": user if r else "", "reply": r.text if r else "", "seconds": round(r.seconds, 2) if r else 0,
                "usage": r.usage if r else {}, "error": r.error if r else None, "at": r.at if r else "",
                "cost_usd": round(call_cost(p.model, r.usage, datetime.fromisoformat(r.at) if r and r.at else None) or 0, 5) if r else 0,
            }
            by_id = {sk["id"]: sk for sk in catalog}
            info = [{**by_id[i], "level": 1, "slot": k + 1} for k, i in enumerate(picks)]
            self.systems[t] = system_prompt(n_decisions, decision_dt, info)
            log(f"game {self.no} draft {L} {p.name}: {', '.join(picks)}" + (f"  ({note})" if note else ""))
        self.record["draft_system_prompt"], self.record["draft_user_prompt"] = system, user
        self.setup = {"seed": self.seed, "teams": teams}
        return self.setup

    # ---- one decision ----------------------------------------------------------------------------------------------
    def decide(self, req: dict, log) -> dict:
        n = 4
        counts = {0: int(req["counts"].get("neutral", 0))}
        balls, skills, turn_cd, frozen = {}, {}, {}, {}
        for t in range(1, n + 1):
            L = LETTERS[t - 1]
            counts[t] = int(req["counts"].get(L, 0))
            balls[t] = [tuple(float(v) for v in b) for b in req["balls"].get(L, [])] or [(16.0, 16.0, 1.0, 0.0)]
            skills[t] = req["skills"].get(L, [])
            turn_cd[t] = float(req["turn_cd"].get(L, 0))
            frozen[t] = bool(req["frozen"].get(L, False))
        snap = Snapshot(t=float(req["t"]), time_left=float(req["time_left"]), counts=counts, grid=req["grid"], balls=balls, skills=skills,
                        turn_cd=turn_cd, frozen=frozen)
        dec_no = int(req.get("decision", 0)) or len(self.record["decisions"]) + 1
        last = req.get("last") or {}
        llm = [t for t, p in self.players.items() if p.is_llm]
        obs = {t: observation(snap, t, dec_no, self.n_decisions, last.get(LETTERS[t - 1])) for t in llm}

        def ask(t):
            return t, self.players[t].decide(self.systems[t], obs[t])

        t0 = time.time()
        with ThreadPoolExecutor(max_workers=max(1, len(llm))) as pool:
            replies = dict(pool.map(ask, llm))
        entry = {"no": dec_no, "tick": req.get("tick"), "t": snap.t, "counts": {LETTERS[t - 1]: counts[t] for t in range(1, 5)}, "neutral": counts[0],
                 "grid": snap.grid, "balls": {LETTERS[t - 1]: b for t, b in balls.items()}, "teams": {}}
        out_cmds, notes = {}, {}
        for t in llm:
            r: Reply = replies[t]
            L = LETTERS[t - 1]
            cmds = parse(r.text) if not r.error else []
            for c in cmds:
                c["text"] = fmt_cmd(c)
            out_cmds[L] = cmds
            if r.error:
                notes[L] = f"(your reply failed: {r.error})"
            elif not cmds:
                notes[L] = "(no valid CMD line found in your reply, nothing was done)"
            cost = call_cost(self.players[t].model, r.usage, datetime.fromisoformat(r.at) if r.at else None)
            entry["teams"][L] = {"prompt": r.prompt, "reply": r.text, "seconds": round(r.seconds, 2), "usage": r.usage,
                                 "cost_usd": round(cost, 5) if cost is not None else None, "error": r.error, "commands": [c["text"] for c in cmds], "at": r.at}
        with self.lock:
            self.record["decisions"].append(entry)
        lead = max(range(1, 5), key=lambda t: counts[t])
        log(f"game {self.no} decision {dec_no}/{self.n_decisions} t={snap.t:4.0f}s  " + "  ".join(f"{LETTERS[t-1]}:{counts[t]:3d}" for t in range(1, 5)) +
            f"  lead {LETTERS[lead-1]}  wall {time.time() - t0:.1f}s  " + " | ".join(f"{LETTERS[t-1]} {entry['teams'][LETTERS[t-1]]['seconds']:.0f}s" for t in llm))
        return {"cmds": out_cmds, "note": notes}

    # ---- end ---------------------------------------------------------------------------------------------------------
    def finish(self, req: dict, out_dir: Path, log) -> dict:
        rec = self.record
        rec["setup"] = self.setup
        rec["commands"] = req.get("commands", [])
        rec["timeline"] = req.get("timeline", [])
        rec["final"] = req.get("final")
        rec["n_decisions"], rec["decision_dt"] = self.n_decisions, self.decision_dt
        # the engine's verdicts, merged back into the per-decision exchanges
        by_tick_team: dict[tuple, list] = {}
        for c in rec["commands"]:
            by_tick_team.setdefault((c["tick"], c["team"]), []).append(c)
        for d in rec["decisions"]:
            for L, e in d["teams"].items():
                e["verdicts"] = [{"cmd": c["cmd"].get("text") or c["cmd"]["type"], "accepted": c["accepted"]} for c in by_tick_team.get((d["tick"], L), [])]
        rec["totals"] = {}
        for t, p in self.players.items():
            L = LETTERS[t - 1]
            ex = [d["teams"][L] for d in rec["decisions"] if L in d["teams"]]
            dr = rec["draft"].get(L, {})
            cmds = [c for c in rec["commands"] if c["team"] == L]
            rec["totals"][L] = {
                "name": p.name, "model": p.model, "llm": p.is_llm, "skills": [s["id"] for s in self.setup["teams"][L]["skills"]],
                "decisions": len(ex), "seconds": round(sum(e["seconds"] for e in ex) + dr.get("seconds", 0), 1),
                "input_tokens": sum(e["usage"].get("input", 0) for e in ex) + dr.get("usage", {}).get("input", 0),
                "output_tokens": sum(e["usage"].get("output", 0) for e in ex) + dr.get("usage", {}).get("output", 0),
                "cost_usd": round(sum(e["cost_usd"] or 0 for e in ex) + (dr.get("cost_usd") or 0), 4),
                "errors": sum(1 for e in ex if e["error"]), "no_command": sum(1 for e in ex if not e["error"] and not e["commands"]),
                "commands": len(cmds), "rejected": sum(1 for c in cmds if not c["accepted"]),
                "casts": sum(1 for c in cmds if c["cmd"]["type"] == "cast" and c["accepted"]),
                "final_cells": rec["final"]["counts"].get(L) if rec["final"] else None,
                "place": (rec["final"]["ranking"].index(L) + 1) if rec["final"] else None,
            }
        rec["finished"] = now()
        out_dir.mkdir(parents=True, exist_ok=True)
        (out_dir / f"game_{self.no}.json").write_text(json.dumps(rec, ensure_ascii=False, indent=1))
        (out_dir / f"game_{self.no}.md").write_text(transcript_md(rec))
        self.done = True
        log(f"game {self.no} finished: {' > '.join(rec['final']['ranking'])}  cells " + " ".join(f"{L} {rec['final']['counts'][L]}" for L in LETTERS))
        write_summary(out_dir)
        return {"ok": True}


def transcript_md(rec: dict) -> str:
    out = [f"# Game {rec['game']} (seed {rec['seed']})", ""]
    out.append("Seats: " + ", ".join(f"**{L}** {t['name']} [{', '.join(t['skills'])}]" for L, t in rec["totals"].items()))
    out.append("")
    out.append(f"Result: {' > '.join(rec['final']['ranking'])}  (cells " + ", ".join(f"{L} {rec['final']['counts'][L]}" for L in LETTERS) + ")")
    out.append("")
    out.append("## Draft")
    for L, d in rec["draft"].items():
        out.append(f"**{L}** picked {', '.join(d['picks'])}" + (f" ({d['note']})" if d.get("note") else ""))
        if d.get("reply"):
            out.append("")
            out.append("> " + d["reply"].strip().replace("\n", "\n> "))
        out.append("")
    for d in rec["decisions"]:
        out.append(f"## Decision {d['no']} — t = {d['t']:.0f} s — cells " + " ".join(f"{L} {d['counts'][L]}" for L in LETTERS))
        for L, e in d["teams"].items():
            verdict = "; ".join(f"`{v['cmd']}` {'✓' if v['accepted'] else '✗ rejected'}" for v in e.get("verdicts", [])) or ("error: " + e["error"] if e["error"] else "no valid command")
            out.append(f"**{L}** ({e['seconds']:.1f} s): {verdict}")
            if e["reply"]:
                out.append("")
                out.append("> " + e["reply"].strip().replace("\n", "\n> "))
            out.append("")
    return "\n".join(out)


def write_summary(out_dir: Path):
    games = sorted(out_dir.glob("game_*.json"), key=lambda p: int(p.stem.split("_")[1]))
    recs = [json.loads(p.read_text()) for p in games]
    agg: dict[str, dict] = {}
    for rec in recs:
        for L, t in rec["totals"].items():
            a = agg.setdefault(t["name"], {"name": t["name"], "model": t["model"], "games": 0, "wins": 0, "places": [], "cells": [], "seconds": 0.0, "cost_usd": 0.0,
                                           "input_tokens": 0, "output_tokens": 0, "commands": 0, "rejected": 0, "casts": 0, "errors": 0, "no_command": 0, "decisions": 0, "skills": []})
            a["games"] += 1
            a["wins"] += 1 if t["place"] == 1 else 0
            a["places"].append(t["place"]); a["cells"].append(t["final_cells"])
            for k in ("seconds", "cost_usd", "input_tokens", "output_tokens", "commands", "rejected", "casts", "errors", "no_command", "decisions"):
                a[k] += t[k] or 0
            a["skills"].append(", ".join(t["skills"]))
    rows = []
    for a in sorted(agg.values(), key=lambda a: (-a["wins"], sum(a["places"]) / max(1, len(a["places"])))):
        n = max(1, a["games"])
        rows.append(f"| {a['name']} | {a['games']} | {a['wins']} | {sum(a['places']) / n:.2f} | {sum(a['cells']) / n:.0f} | {a['seconds'] / max(1, a['decisions']):.1f} | "
                    f"{a['rejected']} / {a['commands']} | {a['casts']} | {a['errors']} + {a['no_command']} | {a['input_tokens']:,} / {a['output_tokens']:,} | ${a['cost_usd']:.2f} | {'; '.join(a['skills'])} |")
    md = ["# Summary", "", f"{len(recs)} game(s): " + ", ".join(f"game {r['game']} → {' > '.join(r['final']['ranking'])}" for r in recs), "",
          "| player | games | wins | avg place | avg cells | s / decision | rejected / cmds | casts | errors + silent | tokens in / out | cost | skills per game |",
          "|---|---|---|---|---|---|---|---|---|---|---|---|"] + rows
    (out_dir / "summary.md").write_text("\n".join(md) + "\n")
    (out_dir / "summary.json").write_text(json.dumps(agg, ensure_ascii=False, indent=1))


# ---------------------------------------------------------------- http
class Server:
    def __init__(self, specs: list[str], seeds: list[int], out: Path, bundle: Path, slots: int, effort: str):
        self.specs, self.seeds, self.out, self.bundle, self.slots, self.effort = specs, seeds, out, bundle, slots, effort
        self.games: dict[int, Game] = {}
        self.players_cache = [make_player(s, effort, seed=100 + k, slots=slots) for k, s in enumerate(specs)]
        self.lock = threading.Lock()
        self.log_path = out / "server.log"
        out.mkdir(parents=True, exist_ok=True)

    def log(self, msg: str):
        line = f"{datetime.now().strftime('%H:%M:%S')} {msg}"
        print(line, flush=True)
        with open(self.log_path, "a") as f:
            f.write(line + "\n")

    def game(self, no: int) -> Game:
        with self.lock:
            if no not in self.games:
                seed = self.seeds[(no - 1) % len(self.seeds)] if self.seeds else 1000 + no
                # seat rotation: player k → team (k + no - 1) mod 4
                players = {((k + no - 1) % 4) + 1: p for k, p in enumerate(self.players_cache)}
                self.games[no] = Game(no, seed, players, self.slots, self.effort)
            return self.games[no]


def make_handler(srv: Server):
    class H(SimpleHTTPRequestHandler):
        extensions_map = {**SimpleHTTPRequestHandler.extensions_map, ".wasm": "application/wasm", ".json": "application/json"}

        def __init__(self, *a, **k):
            super().__init__(*a, directory=str(srv.bundle), **k)

        def log_message(self, *a):
            pass

        def end_headers(self):
            self.send_header("Cross-Origin-Opener-Policy", "same-origin")
            self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
            self.send_header("Cache-Control", "no-store")
            super().end_headers()

        def _json(self, obj, code=200):
            data = json.dumps(obj).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            path = self.path.split("?")[0]
            if path.startswith("/results/"):
                p = (HERE / path.lstrip("/")).resolve()
                if not str(p).startswith(str((HERE / "results").resolve())) or not p.is_file():
                    return self._json({"error": "not found"}, 404)
                data = p.read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return
            if path == "/status":
                q = dict(x.split("=") for x in self.path.split("?")[1].split("&")) if "?" in self.path else {}
                g = srv.games.get(int(q.get("game", 1)))
                return self._json({"exists": g is not None, "done": g.done if g else False, "decisions": len(g.record["decisions"]) if g else 0})
            return super().do_GET()

        def do_POST(self):
            n = int(self.headers.get("Content-Length", 0))
            req = json.loads(self.rfile.read(n) or b"{}")
            path = self.path.split("?")[0]
            try:
                if path == "/draft":
                    g = srv.game(int(req.get("game", 1)))
                    if g.setup is None:
                        g.draft(req["catalog"], int(req.get("n_decisions", 30)), float(req.get("decision_dt", 2.0)), srv.log)
                    return self._json(g.setup)
                if path == "/decide":
                    g = srv.game(int(req.get("game", 1)))
                    return self._json(g.decide(req, srv.log))
                if path == "/finish":
                    g = srv.game(int(req.get("game", 1)))
                    return self._json(g.finish(req, srv.out, srv.log))
            except Exception as e:  # keep the game informed instead of hanging
                import traceback
                traceback.print_exc()
                return self._json({"error": f"{type(e).__name__}: {e}"}, 500)
            return self._json({"error": "unknown route"}, 404)

    return H


def main():
    load_env()
    ap = argparse.ArgumentParser()
    ap.add_argument("--players", default="claude,openai,gemini,deepseek", help="four comma-separated specs (arena/players.py); player k sits at team (k+g-1) mod 4 in game g")
    ap.add_argument("--seeds", default="1001,1002,1003,1004", help="comma-separated, one per game number")
    ap.add_argument("--out", default="results/arena")
    ap.add_argument("--bundle", default="game/build_web/Color Battle Arena")
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--slots", type=int, default=3, help="skills each team drafts")
    ap.add_argument("--effort", default="high")
    a = ap.parse_args()
    specs = a.players.split(",")
    assert len(specs) == 4, "need four players"
    srv = Server(specs, [int(s) for s in a.seeds.split(",") if s], (HERE / a.out), (HERE / a.bundle) if not os.path.isabs(a.bundle) else Path(a.bundle), a.slots, a.effort)
    httpd = ThreadingHTTPServer(("127.0.0.1", a.port), make_handler(srv))
    srv.log(f"arena server on http://127.0.0.1:{a.port}  players={specs}  out={a.out}  bundle={srv.bundle}")
    srv.log(f"open http://127.0.0.1:{a.port}/index.html?arena=live&game=1")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
