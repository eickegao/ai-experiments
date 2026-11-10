#!/usr/bin/env python3
"""Drive one arena game end to end against a running arena_server.py, then record its replay as a 1080×1920 mp4.

  python3 record_match.py --game 1 --out results/<run>            # live (models think) + replay recording
  python3 record_match.py --game 1 --out results/<run> --replay-only   # only re-record from results/<run>/game_1.json

Live: headless Chrome opens  <server>/index.html?arena=live&game=N  and waits for window.__arena_done (the game itself talks
to the server; this script only watches). Replay: opens ?arena=replay&log=/results/<run>/game_N.json with Playwright's
video recording on (same recipe as PlayDoz tools/render_replay.py), waits for __arena_done, converts the webm to a 30 fps
mp4 at results/<run>/game_N.mp4 and checks the console for ARENA_REPLAY_OK.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
ARGS = ["--disable-background-timer-throttling", "--disable-renderer-backgrounding", "--disable-backgrounding-occluded-windows",
        "--autoplay-policy=no-user-gesture-required", "--use-gl=angle", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"]


def wait_done(page, timeout: float, label: str) -> str | None:
    t0 = time.time()
    while time.time() - t0 < timeout:
        try:
            if page.evaluate("window.__arena_done === 1"):
                return None
            err = page.evaluate("window.__arena_error || null")
            if err:
                return str(err)
        except Exception:
            pass
        time.sleep(0.5)
    return f"{label}: timeout after {timeout:.0f} s"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--server", default="http://127.0.0.1:8787")
    ap.add_argument("--game", type=int, default=1)
    ap.add_argument("--out", required=True, help="results/<run> (must match the server's --out)")
    ap.add_argument("--replay-only", action="store_true")
    ap.add_argument("--speed", type=float, default=1.0, help="replay playback speed (1 = real time)")
    ap.add_argument("--live-timeout", type=float, default=3 * 3600)
    ap.add_argument("--headed", action="store_true", help="record with a visible Chrome window (real GPU) instead of headless SwiftShader")
    ap.add_argument("--suffix", default="", help="output name suffix, e.g. _headed (default overwrites game_N.mp4)")
    a = ap.parse_args()
    out = HERE / a.out
    rel = os.path.relpath(out, HERE)
    logs = []
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=not a.headed, args=ARGS)
        if not a.replay_only:
            ctx = browser.new_context(viewport={"width": 1080, "height": 1920}, device_scale_factor=1)
            page = ctx.new_page()
            page.on("console", lambda m: logs.append(m.text) or (print("[game]", m.text[:200], flush=True) if "[arena]" in m.text else None))
            page.goto(f"{a.server}/index.html?arena=live&game={a.game}")
            t0 = time.time()
            err = wait_done(page, a.live_timeout, "live")
            ctx.close()
            if err:
                sys.exit("live game failed: " + err)
            print(f"live game {a.game} done in {time.time() - t0:.0f} s wall-clock")
        # replay with video
        rec_dir = out / f"rec_{a.game}"
        rec_dir.mkdir(parents=True, exist_ok=True)
        ctx = browser.new_context(viewport={"width": 1080, "height": 1920}, device_scale_factor=1,
                                  record_video_dir=str(rec_dir), record_video_size={"width": 1080, "height": 1920})
        page = ctx.new_page()
        replay_logs = []
        page.on("console", lambda m: replay_logs.append(m.text))
        page.goto(f"{a.server}/index.html?arena=replay&log=/{rel}/game_{a.game}.json&speed={a.speed:g}")
        err = wait_done(page, 60 / a.speed + 120, "replay")
        try:
            verdict = page.evaluate("window.__arena_replay || null")
        except Exception:
            verdict = None
        time.sleep(2.0)
        video = page.video
        ctx.close()
        webm = video.path()
        browser.close()
    ok = bool(verdict and verdict.get("ok"))
    mism = [json.dumps(verdict)] if verdict and not verdict.get("ok") else []
    mp4 = out / f"game_{a.game}{a.suffix}.mp4"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", webm, "-r", "30", "-vf", "scale=1080:1920", "-c:v", "libx264", "-crf", "18",
                    "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(mp4)], check=True)
    for f in Path(rec_dir).glob("*.webm"):
        f.unlink()
    Path(rec_dir).rmdir()
    print("replay recorded →", mp4, "| determinism:", "OK" if ok else (mism[0] if mism else "unknown"))
    if err:
        sys.exit("replay: " + err)


if __name__ == "__main__":
    main()
