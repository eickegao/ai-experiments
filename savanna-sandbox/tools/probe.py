#!/usr/bin/env python3
"""Run JS snippets against the sandbox at given moments and print the results.
Usage: python3 tools/probe.py "<setup js>" "<probe js>" <seconds> [<seconds> ...]"""
import functools, http.server, pathlib, sys, threading
from playwright.sync_api import sync_playwright
root = pathlib.Path(__file__).resolve().parent.parent
class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a): pass
server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Quiet, directory=str(root)))
threading.Thread(target=server.serve_forever, daemon=True).start()
setup, probe, times = sys.argv[1], sys.argv[2], [float(t) for t in sys.argv[3:]]
with sync_playwright() as p:
    b = p.chromium.launch(channel="chrome", headless=True, args=["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist"])
    page = b.new_page(viewport={"width": 800, "height": 600})
    page.on("pageerror", lambda e: print("PAGEERROR", e))
    page.goto(f"http://127.0.0.1:{server.server_address[1]}/?demo=1&ui=0")
    page.wait_for_function("window.G && window.G.ready")
    page.evaluate(setup)
    el = 0
    for t in times:
        page.wait_for_timeout(int((t - el) * 1000)); el = t
        print(t, page.evaluate(probe))
    b.close()
