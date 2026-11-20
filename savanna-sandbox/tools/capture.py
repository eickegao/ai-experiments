#!/usr/bin/env python3
"""Record the sandbox frame by frame into an mp4. The page clock is replaced by a
fake one that we advance 1/30 s per frame, so the recording never drops frames and
the same query always gives the same video.

Usage: python3 tools/capture.py <out.mp4> [seconds=50] [--portrait] [--query "demo=1&ui=0&lang=zh"]
"""
import argparse, functools, http.server, pathlib, subprocess, threading
from playwright.sync_api import sync_playwright

root = pathlib.Path(__file__).resolve().parent.parent
ap = argparse.ArgumentParser()
ap.add_argument("out")
ap.add_argument("seconds", nargs="?", type=float, default=50)
ap.add_argument("--portrait", action="store_true")
ap.add_argument("--query", default="demo=1&ui=0&lang=zh&hold=1")
ap.add_argument("--fps", type=int, default=30)
a = ap.parse_args()
W, H = (1080, 1920) if a.portrait else (1920, 1080)

CLOCK = """(() => {
  let now = 0, id = 0; const rafs = new Map(), timers = new Map();
  performance.now = () => now;
  Date.now = () => 1763500000000 + now;
  window.requestAnimationFrame = cb => { rafs.set(++id, cb); return id; };
  window.cancelAnimationFrame = i => rafs.delete(i);
  window.setTimeout = (cb, ms = 0, ...x) => { timers.set(++id, { cb, at: now + (+ms || 0), x }); return id; };
  window.setInterval = (cb, ms = 0, ...x) => { timers.set(++id, { cb, at: now + (+ms || 0), every: Math.max(1, +ms || 0), x }); return id; };
  window.clearTimeout = window.clearInterval = i => timers.delete(i);
  window.__step = dt => {
    const end = now + dt;
    for (let guard = 0; guard < 5000; guard++) {
      let pick = null, pid = 0;
      for (const [i, t] of timers) if (t.at <= end && (!pick || t.at < pick.at)) { pick = t; pid = i; }
      if (!pick) break;
      now = Math.max(now, pick.at);
      if (pick.every) pick.at += pick.every; else timers.delete(pid);
      try { typeof pick.cb === 'function' && pick.cb(...pick.x); } catch (e) { console.error(e); }
    }
    now = end;
    const cbs = [...rafs.values()]; rafs.clear();
    for (const cb of cbs) { try { cb(now); } catch (e) { console.error(e); } }
  };
})();"""


class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *x): pass

server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Quiet, directory=str(root)))
threading.Thread(target=server.serve_forever, daemon=True).start()
out = pathlib.Path(a.out); out.parent.mkdir(parents=True, exist_ok=True)
ff = subprocess.Popen(["ffmpeg", "-y", "-loglevel", "error", "-f", "image2pipe", "-framerate", str(a.fps), "-i", "-",
                       "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "17", "-preset", "medium", str(out)], stdin=subprocess.PIPE)
with sync_playwright() as p:
    b = p.chromium.launch(channel="chrome", headless=True, args=["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist"])
    pg = b.new_page(viewport={"width": W, "height": H}, device_scale_factor=1)
    pg.on("pageerror", lambda e: print("PAGEERROR", str(e)[:300]))
    pg.add_init_script(CLOCK)
    pg.goto(f"http://127.0.0.1:{server.server_address[1]}/?{a.query}", wait_until="networkidle")
    pg.wait_for_function("window.G && window.G.ready")
    n = int(a.seconds * a.fps)
    for i in range(n):
        pg.evaluate(f"window.__step({1000 / a.fps})")
        ff.stdin.write(pg.screenshot(type="jpeg", quality=95))
        if i % 150 == 0: print(f"frame {i}/{n}", pg.evaluate("JSON.stringify(G.tribes.info())"), flush=True)
    events = pg.evaluate("JSON.stringify(G.events)")
    out.with_suffix(".events.json").write_text(events)
    b.close()
ff.stdin.close(); ff.wait()
print("wrote", out)
