#!/usr/bin/env python3
"""Open the sandbox in headless Chrome, report console errors, save screenshots.

Usage: python3 tools/shot.py [seconds ...] [--query "a=b&c=d"] [--portrait] [--eval "js"] [--name tag]
Screenshots go to out/t<seconds>[-tag].png (out/ is not committed).
--eval runs a JS expression once the page is ready (before the first wait), e.g.
  --eval "G.setSpeed(16)".
"""
import argparse
import functools
import http.server
import pathlib
import threading

from playwright.sync_api import sync_playwright

root = pathlib.Path(__file__).resolve().parent.parent
ap = argparse.ArgumentParser()
ap.add_argument("times", nargs="*", type=float)
ap.add_argument("--query", default="")
ap.add_argument("--portrait", action="store_true")
ap.add_argument("--eval", default="")
ap.add_argument("--name", default="")
ap.add_argument("--each", default="", help="JS run before every screenshot")
args = ap.parse_args()
times = args.times or [2]
out = root / "out"
out.mkdir(exist_ok=True)


class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a):
        pass


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Quiet, directory=str(root)))
threading.Thread(target=server.serve_forever, daemon=True).start()
url = f"http://127.0.0.1:{server.server_address[1]}/" + (f"?{args.query}" if args.query else "")

with sync_playwright() as p:
    browser = p.chromium.launch(channel="chrome", headless=True,
                                args=["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist"])
    size = {"width": 720, "height": 1280} if args.portrait else {"width": 1600, "height": 900}
    page = browser.new_page(viewport=size, device_scale_factor=1)
    problems = []
    page.on("console", lambda m: problems.append(f"console.{m.type}: {m.text}") if m.type in ("error", "warning") else None)
    page.on("pageerror", lambda e: problems.append(f"pageerror: {e}"))
    page.on("requestfailed", lambda r: problems.append(f"requestfailed: {r.url}"))
    page.goto(url)
    page.wait_for_function("window.G && window.G.ready", timeout=20000)
    if args.eval:
        page.evaluate(args.eval)
    elapsed = 0.0
    tag = ("-" + args.name if args.name else "") + ("-portrait" if args.portrait else "")
    for t in times:
        page.wait_for_timeout(max(0, (t - elapsed) * 1000))
        elapsed = t
        if args.each:
            print(' ', page.evaluate(args.each))
            page.wait_for_timeout(120)
        path = out / f"t{int(t)}{tag}.png"
        page.screenshot(path=str(path))
        print("saved", path)
    stats = page.evaluate("() => window.G.stats ? window.G.stats() : null")
    print("stats:", stats)
    for line in dict.fromkeys(problems):
        print("PROBLEM", line)
    browser.close()
