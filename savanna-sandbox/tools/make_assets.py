#!/usr/bin/env python3
"""Generate the 3D models for the sandbox: one reference picture per object from the
OpenAI image API, then image-to-3D with Tripo, downloaded as GLB.

Usage: python3 tools/make_assets.py <name> [<name> ...] | --all [--images-only] [--force]

Every step is recorded in assets/manifest.json (prompt, task id, seconds, Tripo credits
spent), and finished steps are skipped on the next run, so nothing is paid for twice.
Keys: OPENAI_API_KEY in the repo-root .env; TRIPO_API_KEY in the environment, the
repo-root .env, or ~/.tripo_api_key.
"""
import asyncio, base64, json, os, pathlib, sys, time, urllib.request, urllib.error, uuid

root = pathlib.Path(__file__).resolve().parent.parent
ASSETS = root / "assets"
REF, MODELS = ASSETS / "ref", ASSETS / "models"
MANIFEST = ASSETS / "manifest.json"
IMAGE_MODEL = "gpt-image-2"
TRIPO_VERSION = "v2.5-20250123"

STYLE = ("tabletop diorama miniature model, realistic proportions, hand-painted matte finish, clean readable shapes, "
         "warm natural colours, the whole object visible, three-quarter front view from slightly above, centered, "
         "plain white background, soft even studio lighting, no ground shadow, no base, no text")

# name: (what to draw, face limit)
ITEMS = {
    "person_red": ("a single East African savanna tribesman standing upright in an A-pose with arms held slightly away from the body, wearing a red cloth wrap with a yellow bead necklace and a red headband, barefoot, empty hands", 3000),
    "person_blue": ("a single East African savanna tribesman standing upright in an A-pose with arms held slightly away from the body, wearing a deep blue cloth wrap with a white bead necklace and a blue headband, barefoot, empty hands", 3000),
    "zebra": ("a single zebra standing, side-on three-quarter view, all four legs visible and apart", 3000),
    "wildebeest": ("a single blue wildebeest standing, side-on three-quarter view, all four legs visible and apart", 3000),
    "gazelle": ("a single Thomson's gazelle standing, side-on three-quarter view, all four legs visible and apart", 3000),
    "elephant": ("a single African bush elephant standing, side-on three-quarter view, all four legs visible", 4000),
    "giraffe": ("a single giraffe standing tall, side-on three-quarter view, all four legs visible and apart", 4000),
    "lion": ("a single male lion with a full mane standing, side-on three-quarter view, all four legs visible and apart", 3000),
    "vulture": ("a single vulture in flight with wings spread flat and wide, seen from above at three-quarter view", 2000),
    "acacia_a": ("a single umbrella thorn acacia tree with a wide flat-topped canopy and a slightly leaning trunk", 4000),
    "acacia_b": ("a single umbrella thorn acacia tree with a forked trunk and two flat layered canopies", 4000),
    "baobab": ("a single baobab tree with a very thick swollen trunk and short stubby branches with small leaf clusters", 4000),
    "bush": ("a single low round savanna shrub with small red berries", 1500),
    "rock_a": ("a single weathered granite boulder cluster, one large rounded rock with two small ones beside it", 1500),
    "rock_b": ("a single tall rounded granite boulder", 1200),
    "shelter": ("a single primitive lean-to shelter made of branches and dry grass thatch, open at the front", 3000),
    "hut": ("a single round African mud hut with a conical grass thatched roof and a small dark doorway, a red painted band around the wall", 4000),
    "house": ("a single flat-roofed mud-brick house with a small upper room, wooden roof beams sticking out, a wooden ladder, painted geometric band around the wall", 5000),
    "stone_house": ("a single two-storey dry-stone house with a steep tiled pyramid roof, a wooden door and small windows, a banner on a pole", 5000),
    "hall": ("a single grand stone royal hall on a stepped stone platform with a columned porch, a large tiled pyramid roof and banners, ancient African kingdom architecture", 8000),
    "granary": ("a single small round granary hut raised on wooden stilts with a conical thatched roof", 3000),
    "tower": ("a single wooden watchtower on four tall legs with a railed platform and a small thatched roof", 4000),
    "totem": ("a single tall East African carved hardwood ancestor post: a slender dark wooden pole carved with stacked geometric patterns and stylised human figures, decorated with strings of coloured beads and a few feathers, standing upright", 3000),
    "crocodile": ("a single Nile crocodile lying flat with its body straight and its mouth slightly open, seen from above at three-quarter view", 3000),
    "hyena": ("a single spotted hyena standing, side-on three-quarter view, all four legs visible and apart", 3000),
    "stump": ("a single freshly cut tree stump with a few wood chips around it", 800),
    "quarry": ("a single small open stone quarry pit cut into rock with rough stone blocks stacked beside it and a wooden crane", 4000),
    "lumber": ("a single neat stack of cut tree logs", 1200),
    "stall": ("a single wooden market stall with a striped cloth canopy and baskets of fruit and vegetables on the counter", 4000),
    "bonfire": ("a single campfire: a ring of stones around stacked logs, no flames", 1500),
    "townhouse": ("a single three-storey red brick terraced townhouse from the industrial age with a slate roof, chimneys and sash windows", 4000),
    "factory": ("a single nineteenth century red brick factory building with a saw-tooth roof and two tall smoking-style brick chimneys (no smoke), a loading yard in front", 6000),
    "apartment": ("a single modern mid-rise concrete apartment block, about nine storeys, with rows of balconies and a flat roof, standing upright", 4000),
    "tower_block": ("a single modern glass and steel office skyscraper, about thirty storeys, slim and tall, blue-tinted glass curtain wall, standing upright", 4000),
    "skyscraper": ("a single landmark supertall skyscraper with a tapering glass facade and a spire on top, about sixty storeys, on a small plaza base, standing upright", 6000),
}


def env_key(name):
    if os.environ.get(name):
        return os.environ[name]
    envf = root.parent / ".env"
    if envf.exists():
        for line in envf.read_text().splitlines():
            if line.startswith(name + "="):
                return line.split("=", 1)[1].strip().strip('"')
    return None


def load():
    return json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {}


def save(m):
    MANIFEST.write_text(json.dumps(m, indent=1, ensure_ascii=False))


def make_image(name, m, force=False):
    out = REF / f"{name}.png"
    if out.exists() and not force:
        return out
    key = env_key("OPENAI_API_KEY") or sys.exit("OPENAI_API_KEY missing")
    prompt = f"{ITEMS[name][0]}, {STYLE}"
    body = json.dumps({"model": IMAGE_MODEL, "prompt": prompt, "size": "1024x1024"}).encode()
    req = urllib.request.Request("https://api.openai.com/v1/images/generations", data=body,
                                 headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    t0 = time.time()
    try:
        r = json.load(urllib.request.urlopen(req, timeout=300))
    except urllib.error.HTTPError as e:
        sys.exit(f"OpenAI {e.code}: {e.read().decode()[:400]}")
    out.write_bytes(base64.b64decode(r["data"][0]["b64_json"]))
    m.setdefault(name, {}).update(image_model=IMAGE_MODEL, image_prompt=prompt, image_seconds=round(time.time() - t0, 1),
                                  image_usage=r.get("usage"))
    save(m)
    print("image", name, f"{time.time() - t0:.0f}s", flush=True)
    return out


async def wait(c, tid, tries=30):
    from tripo3d.exceptions import TripoAPIError
    for i in range(tries):
        try:
            return await c.wait_for_task(tid, verbose=False)
        except TripoAPIError:
            raise
        except Exception as e:      # gateway hiccups: keep polling
            print("  poll retry", str(e)[:80], flush=True)
            await asyncio.sleep(5)
    raise SystemExit("polling failed")


async def submit(c, name, m, force=False):
    """Start the image-to-3D task (the SDK's plain client handles one request at a time,
    so tasks are submitted one after another; they then run side by side on Tripo's servers)."""
    e = m.setdefault(name, {})
    if (MODELS / f"{name}.glb").exists() and not force:
        return
    if "model_task" not in e or force:
        e["model_task"] = await c.image_to_model(image=str(REF / f"{name}.png"), model_version=TRIPO_VERSION,
                                                 face_limit=ITEMS[name][1], texture=True, pbr=False,
                                                 texture_quality="standard", auto_size=False)
        e.update(tripo_version=TRIPO_VERSION, face_limit=ITEMS[name][1], model_started=time.time())
        save(m)
        print("submitted", name, flush=True)


async def collect(c, name, m, force=False):
    out = MODELS / f"{name}.glb"
    e = m.setdefault(name, {})
    if (out.exists() and not force) or "model_task" not in e:
        return
    task = await wait(c, e["model_task"])
    if task.status != "success":
        print("FAILED", name, task.status, flush=True)
        e["model_status"] = str(task.status); save(m)
        return
    tmp = MODELS / f"_{name}"
    tmp.mkdir(exist_ok=True)
    files = await c.download_task_models(task, str(tmp))
    src = next((p for p in files.values() if p and str(p).endswith(".glb")), None) or next(p for p in files.values() if p)
    pathlib.Path(src).rename(out)
    for p in tmp.iterdir(): p.unlink()
    tmp.rmdir()
    e.update(model_seconds=round(time.time() - e.get("model_started", time.time()), 1), model_bytes=out.stat().st_size, model_status="success")
    save(m)
    print("model", name, f"{e['model_seconds']:.0f}s", f"{out.stat().st_size / 1e6:.1f} MB", flush=True)


async def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    names = list(ITEMS) if "--all" in sys.argv else args
    for n in names:
        if n not in ITEMS: sys.exit(f"unknown item {n}; known: {', '.join(ITEMS)}")
    force = "--force" in sys.argv
    REF.mkdir(parents=True, exist_ok=True); MODELS.mkdir(parents=True, exist_ok=True)
    m = load()
    await asyncio.gather(*[asyncio.to_thread(make_image, n, m, force) for n in names])
    if "--images-only" in sys.argv:
        return
    if not os.environ.get("TRIPO_API_KEY"):
        k = env_key("TRIPO_API_KEY")
        kf = pathlib.Path.home() / ".tripo_api_key"
        os.environ["TRIPO_API_KEY"] = k or (kf.read_text().strip() if kf.exists() else sys.exit("TRIPO_API_KEY missing"))
    from tripo3d import TripoClient
    async with TripoClient() as c:
        before = (await c.get_balance()).balance
        # Tripo limits how many tasks may run at once, so work in batches of four.
        for i in range(0, len(names), 4):
            batch = names[i:i + 4]
            for n in batch:
                for attempt in range(8):
                    try:
                        await submit(c, n, m, force)
                        break
                    except Exception as e:
                        if "exceeded the limit" not in str(e): raise
                        print("  rate limited, waiting 30 s", flush=True)
                        await asyncio.sleep(30)
            for n in batch: await collect(c, n, m, force)
        after = (await c.get_balance()).balance
    runs = m.setdefault("_runs", [])
    runs.append({"date": time.strftime("%Y-%m-%d %H:%M"), "items": names, "tripo_credits_before": before, "tripo_credits_after": after})
    save(m)
    print(f"Tripo credits: {before} -> {after} (spent {before - after})")


asyncio.run(main())
