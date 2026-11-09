#!/usr/bin/env python3
"""Open the web bundle headless (system Chrome via Playwright), print console output, save a screenshot.

    python3 tools/web_smoke.py game/build_web/<title> "?arena=live&server=http://127.0.0.1:8787" out.png --wait 6
Serves the bundle dir on 127.0.0.1:8932 with COOP/COEP headers (wasm threads), like PlayDoz tools/render_replay.py.
"""
import http.server, os, socketserver, sys, threading, time
from playwright.sync_api import sync_playwright

PORT = 8932


class H(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, ".wasm": "application/wasm"}

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()

    def log_message(self, *a):
        pass


def main():
    bundle, query, out = sys.argv[1], sys.argv[2], sys.argv[3]
    wait = float(sys.argv[sys.argv.index("--wait") + 1]) if "--wait" in sys.argv else 6.0
    handler = lambda *a, **k: H(*a, directory=os.path.abspath(bundle), **k)
    socketserver.TCPServer.allow_reuse_address = True
    httpd = socketserver.TCPServer(("127.0.0.1", PORT), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    with sync_playwright() as p:
        b = p.chromium.launch(channel="chrome", headless=True, args=["--use-gl=angle", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist", "--autoplay-policy=no-user-gesture-required"])
        pg = b.new_context(viewport={"width": 1080, "height": 1920}, device_scale_factor=1).new_page()
        pg.on("console", lambda m: print("[console]", m.text[:300]))
        pg.on("pageerror", lambda e: print("[pageerror]", str(e)[:300]))
        pg.goto(f"http://127.0.0.1:{PORT}/index.html{query}")
        time.sleep(wait)
        pg.screenshot(path=out)
        b.close()
    httpd.shutdown()
    print("saved", out)


if __name__ == "__main__":
    main()
