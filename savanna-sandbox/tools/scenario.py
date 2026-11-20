#!/usr/bin/env python3
"""Run a scripted scenario and save screenshots: a list of steps, each
(wait_seconds, js_or_None, shot_name_or_None).

Usage: python3 tools/scenario.py <name> [--portrait]
Scenarios live in SCENARIOS below; screenshots go to out/<name>-<shot>.png.
"""
import functools, http.server, pathlib, sys, threading
from playwright.sync_api import sync_playwright

root = pathlib.Path(__file__).resolve().parent.parent
CAM = "Object.assign(G.stage.cam,{%s});"
SCENARIOS = {
    "war": [
        (0, "G.setSpeed(16)", None),
        (17, "G.setSpeed(2);G.time=Math.floor(G.time/G.DAY)*G.DAY+G.DAY*0.4;G.power('war');" + CAM % "tx:48,tz:48,ty:0,dist:150,yaw:0.72,pitch:0.6", None),
        (3, CAM % "tx:33,tz:33,ty:1,dist:45,yaw:0.9,pitch:0.5", "rally"),
        (5, CAM % "tx:47,tz:46,ty:0,dist:70,yaw:0.5,pitch:0.5", "march"),
        (3, None, "clash"),
        (3, None, "clash2"),
        (4, None, "clash3"),
        (8, None, "after"),
    ],
    "powers": [
        (0, "G.setSpeed(16)", None),
        (9, "G.setSpeed(1);G.time=Math.floor(G.time/G.DAY)*G.DAY+G.DAY*0.42;" + CAM % "tx:60,tz:40,ty:0,dist:110,yaw:0.6,pitch:0.55" + "G.power('lightning',66,44);G.power('lightning',58,30);", None),
        (0.25, None, "bolt"),
        (5, None, "fire"),
        (8, "G.power('rain',62,38)", "fire2"),
        (5, None, "rain"),
        (8, "G.power('meteor',70,52)", None),
        (1.2, None, "meteor"),
        (0.7, None, "impact"),
        (3, None, "crater"),
        (2, "G.power('herd',40,30);G.power('storm');" + CAM % "tx:48,tz:48,ty:0,dist:235,yaw:0.72,pitch:0.66", None),
        (6, None, "storm"),
        (14, "G.power('drought');G.setSpeed(8)", None),
        (8, None, "drought"),
    ],
    "wide": [
        (0, "G.setSpeed(4)", None),
        (4, None, "day"),
        (0, CAM % "tx:60,tz:60,ty:0,dist:70,yaw:1.2,pitch:0.42", "low"),
        (0, CAM % "tx:47,tz:44,ty:0,dist:55,yaw:0.2,pitch:0.5", "lake"),
    ],
}

name = sys.argv[1]
portrait = "--portrait" in sys.argv
out = root / "out"; out.mkdir(exist_ok=True)

class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a): pass

server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Quiet, directory=str(root)))
threading.Thread(target=server.serve_forever, daemon=True).start()
with sync_playwright() as p:
    browser = p.chromium.launch(channel="chrome", headless=True, args=["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist"])
    page = browser.new_page(viewport={"width": 720, "height": 1280} if portrait else {"width": 1600, "height": 900})
    problems = []
    page.on("console", lambda m: problems.append(f"console.{m.type}: {m.text}") if m.type in ("error", "warning") else None)
    page.on("pageerror", lambda e: problems.append(f"pageerror: {e}"))
    page.goto(f"http://127.0.0.1:{server.server_address[1]}/?lang=zh")
    page.wait_for_function("window.G && window.G.ready", timeout=20000)
    for wait, js, shot in SCENARIOS[name]:
        page.wait_for_timeout(int(wait * 1000))
        if js: page.evaluate(js)
        if shot:
            page.wait_for_timeout(60)
            path = out / f"{name}-{shot}{'-portrait' if portrait else ''}.png"
            page.screenshot(path=str(path))
            print("saved", path.name, page.evaluate("JSON.stringify(G.stats())"))
    for line in dict.fromkeys(problems): print("PROBLEM", line)
    browser.close()
