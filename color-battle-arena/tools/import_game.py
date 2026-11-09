#!/usr/bin/env python3
"""Copy the Color Battle Defold game out of the PlayDoz monorepo into ./game/ as a standalone project.

    python3 tools/import_game.py            # reads $PLAYDOZ_DIR (default ~/Projects/PlayDoz/PlayDozDefold)

What it copies (resource closure, so the bundle contains only what Color Battle needs):
  - games/clashdoz/            the whole game (sim, bot, GUI, atlases, sounds, particles)
  - shared/                    every shared Lua module (required lazily at runtime) + the shared atlases / sounds / gui it references
  - assets/                    only the images, fonts and custom resources referenced from the files above
  - main/, input/, web/, game.texture_profiles   taken from the PlayDoz standalone web project (SoloGames/clashdoz)
  - game.project               same as the standalone project minus the native extensions (GameKit, drawpixels, taptic:
                               all guarded in code and irrelevant for the web build)
Files under game/arena/ (the arena mode added for this experiment) are never touched.
"""
import os, re, shutil, sys

PLAYDOZ = os.path.expanduser(os.environ.get("PLAYDOZ_DIR", "~/Projects/PlayDoz/PlayDozDefold"))
SOLO = os.path.join(PLAYDOZ, "..", "SoloGames", "clashdoz")
HERE = os.path.dirname(os.path.abspath(__file__))
DST = os.path.join(HERE, "..", "game")
TEXT_EXT = (".collection", ".go", ".gui", ".atlas", ".font", ".particlefx", ".sound", ".collectionproxy", ".script", ".gui_script", ".lua", ".project", ".material", ".render", ".input_binding", ".texture_profiles", ".tilesource", ".display_profiles")
REF = re.compile(r'"(/(?:assets|shared|games|web|main|input)/[^"\s]+)"')


def src_of(res: str) -> str:
    """resource path (/x/y) → file in PlayDoz, following the standalone project's symlinks for main/ and input/"""
    for base in (SOLO, PLAYDOZ):
        p = os.path.join(base, res.lstrip("/"))
        if os.path.exists(p):
            return os.path.realpath(p)
    return ""


copied = set()


def copy(res: str):
    if res in copied:
        return
    s = src_of(res)
    if not s:
        print("  missing:", res)
        return
    d = os.path.join(DST, res.lstrip("/"))
    os.makedirs(os.path.dirname(d), exist_ok=True)
    shutil.copy2(s, d)
    copied.add(res)
    if res.endswith(TEXT_EXT):
        try:
            txt = open(s, encoding="utf-8", errors="ignore").read()
        except OSError:
            return
        for r in REF.findall(txt):
            copy(r)


def copy_tree(res_dir: str):
    s = src_of(res_dir)
    for root, _, files in os.walk(s):
        for f in files:
            if f.startswith(".") or f.endswith((".pyc",)):
                continue
            rel = "/" + os.path.relpath(os.path.join(root, f), os.path.realpath(src_of("/" + res_dir.strip("/")).rsplit("/", 1)[0] + "/")).replace(os.sep, "/")
            full = os.path.join(root, f)
            # rel must be the resource path: compute from PLAYDOZ root
            r = "/" + os.path.relpath(full, os.path.realpath(PLAYDOZ)).replace(os.sep, "/")
            copy(r)


def main():
    if os.path.isdir(DST):
        for name in os.listdir(DST):
            if name in ("arena", "build", "build_web", ".gitignore"):
                continue
            p = os.path.join(DST, name)
            shutil.rmtree(p) if os.path.isdir(p) else os.remove(p)
    os.makedirs(DST, exist_ok=True)
    copy_tree("/games/clashdoz")
    copy_tree("/shared")
    for r in ("/main/main.collection", "/main/main.go", "/main/main.script", "/input/game.input_binding", "/web/engine_template.html", "/game.texture_profiles"):
        copy(r)
    # custom resources (bigtex) if the standalone project declares them
    proj = open(os.path.join(SOLO, "game.project"), encoding="utf-8").read()
    m = re.search(r"custom_resources = (.+)", proj)
    if m:
        for cr in m.group(1).split(","):
            cr = cr.strip()
            if src_of(cr):
                copy_tree(cr)
    # game.project without native extensions
    lines = [ln for ln in proj.splitlines() if not ln.startswith("dependencies#")]
    out = "\n".join(lines) + "\n"
    out = out.replace("title = Color Battle", "title = Color Battle Arena")
    open(os.path.join(DST, "game.project"), "w", encoding="utf-8").write(out)
    total = sum(os.path.getsize(os.path.join(r, f)) for r, _, fs in os.walk(DST) for f in fs)
    print(f"copied {len(copied)} files, {total / 1e6:.1f} MB → {os.path.relpath(DST)}")


if __name__ == "__main__":
    main()
