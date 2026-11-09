#!/usr/bin/env python3
"""Copy Color Battle out of the PlayDoz monorepo into ./game/ as a slim, standalone Defold project.

    python3 tools/import_game.py            # reads $PLAYDOZ_DIR (default ~/Projects/PlayDoz/PlayDozDefold)

Only what a four-AI match needs (user 2026-11-09: no cover, no skill-shop / prep page, no levels, no coins, no result or
leaderboard pages, no how-to-play, one background track, English only):

  games/clashdoz/   cd_sim (rules), cd_ai (built-in bot), cd_config, cd_rng, cd_levels (layouts / loadout rolls),
                    clashdoz_game.gui + gui_script (the match screen), 3 atlases (+ particles), the match sound effects,
                    ONE background track. Cover / prep screens, cd_mini, cd_profile, cd_scores are left behind
                    (two tiny stubs keep the match screen's references satisfied).
  shared/           layout.lua + pill_btn.lua for real; everything else the match screen touches (coins, earn, result page,
                    leaderboard, haptics, cloud save, progress, i18n) is a no-op stub written by this script.
  assets/           only images / fonts / audio referenced from the files above (resource closure).
  main/, input/, web/, game.project   written here (bootstrap: load the game and start a match straight away).

Edits applied to copied files are listed in PATCHES below so a re-import reproduces the same tree. The arena mode
itself is copied from arena_game/arena.lua (kept outside game/ so a re-import cannot lose it).
"""
import os, re, shutil

PLAYDOZ = os.path.expanduser(os.environ.get("PLAYDOZ_DIR", "~/Projects/PlayDoz/PlayDozDefold"))
HERE = os.path.dirname(os.path.abspath(__file__))
DST = os.path.join(HERE, "..", "game")
G = "/games/clashdoz"

KEEP_GAME_FILES = [
    "cd_ai.lua", "cd_config.lua", "cd_levels.lua", "cd_rng.lua", "cd_sim.lua",
    "clashdoz_game.gui", "clashdoz_game.gui_script", "clashdoz.collectionproxy",
    "clashdoz.atlas", "clashdoz_fx.atlas", "clashdoz_orb.atlas",
    "boom.particlefx", "giant_trail.particlefx", "shards.particlefx",
]
# match sound effects (snd("name") in the gui_script, incl. skill casts) + one background track
KEEP_SOUNDS = ["bomb", "boost", "capture", "chain", "clone", "crush", "drop", "giant", "laser", "lose", "pick", "plasma_burst",
               "plasma_grow", "refresh", "shield", "shock", "steal", "tick", "timestop", "turn", "warp", "win", "bgm_four_color_2"]
# effect frame sequences only used by level goals (race star, suck-into-star, stage switch): not in a quad match
DROP_FX_PREFIX = ("fx_star_", "fx_suck_")

PATCHES = {
    # one background track, pick deterministic
    "clashdoz_game.gui_script": [
        (r'local BGM_TRACKS = \{[^\n]*\}', 'local BGM_TRACKS = { "#snd_bgm_four_color_2" }   -- arena: one track (user 2026-11-09)'),
        # arena hooks (games/clashdoz/arena.lua): module, seed from the setup, no bots unless the seat is a bot,
        # decision pauses in the step loop, names on the HUD, no touch input, no result page
        (r'(local game_progress = require\("shared.game_progress"\)\n)', r'\1local arena = require("games.clashdoz.arena")   -- arena mode (AIExperiments)\n'),
        (r'local seed = os\.time\(\) \+ math\.floor\(', 'local seed = opts.seed or os.time() + math.floor('),
        (r'(\tfor t = 1, m\.sim\.n do   -- 演示 / 预览[^\n]*\n\t\tif \(t ~= PLAYER or opts\.demo[^\n]*\n\tend\n)',
         r'\tif opts.arena then   -- arena: LLM seats get no bot; "bot" seats keep the game AI\n\t\tfor t = 1, m.sim.n do if opts.bots and opts.bots[t] then m.ais[#m.ais + 1] = ai.new(t, seed + t * 7919, policy) end end\n\telse\n\1\tend\n'),
        (r'(\t+)(m\.acc = m\.acc \+ math\.min\(dt, 0\.25\) \* scale\n)', r'\1\2\1if m.arena then m.acc = m.acc * arena.speed end   -- replay: optional playback speed\n'),
        (r'\t\twhile m\.acc >= C\.FIXED_DT and not s\.over do\n\t\t\tfor _, bot in ipairs\(m\.ais\) do ai\.update\(bot, s, C\.FIXED_DT\) end\n\t\t\tsim\.step\(s, C\.FIXED_DT\)\n\t\t\tm\.acc = m\.acc - C\.FIXED_DT\n\t\tend',
         '\t\twhile m.acc >= C.FIXED_DT and not s.over do\n\t\t\tif m.arena and not arena.before_step(m, s) then m.acc = 0; break end   -- models thinking: game time frozen\n\t\t\tfor _, bot in ipairs(m.ais) do ai.update(bot, s, C.FIXED_DT) end\n\t\t\tsim.step(s, C.FIXED_DT)\n\t\t\tm.tick = (m.tick or 0) + 1\n\t\t\tif m.arena then arena.after_step(m, s) end\n\t\t\tm.acc = m.acc - C.FIXED_DT\n\t\tend'),
        (r'preview = opts\.preview \}', 'preview = opts.preview, arena = opts.arena }'),
        # arena HUD: no coin counter, no back button, no skill buttons (all four seats are AIs; cooldowns live in the log)
        (r'(\tm\.cdn_t0 = nil; S\.hold = nil\n)', r'\1\tif opts.arena then gui.set_enabled(S.coin_icon, false); gui.set_enabled(S.coin_text, false); gui.set_enabled(gui.get_node("btn_back"), false) end   -- after set_showcase re-enabled them\n'),
        (r'if m\.showcase or m\.preview then for k = 1, #C\.SKILL_IDS do enable_skill_button', 'if m.showcase or m.preview or m.arena then for k = 1, #C.SKILL_IDS do enable_skill_button'),
        (r'set_text\(st\.name, t == PLAYER and T\("YOU"\) or T\(TEAMS\[t\]\.name\)\)', 'set_text(st.name, (m.arena and arena.names[t]) or (t == PLAYER and T("YOU") or T(TEAMS[t].name)))'),
        (r'(function on_input\(self, action_id, action\)\n\tif not S\.visible then return false end\n)', r'\1\tif S.match and S.match.arena then return false end   -- arena: nobody touches the board\n'),
        (r'(finish_match = function\(m\)\n\tm\.finished = true\n\tlocal s = m\.sim\n)', r'\1\tif m.arena then arena.on_finish(m, s); bgm_fade_out(1.0); snd("win"); return end   -- arena: report, no result page\n'),
        (r'loadout = message\.loadout, enemies = message\.enemies, eager = message\.eager, slots = message\.slots,',
         'loadout = message.loadout, enemies = message.enemies, eager = message.eager, slots = message.slots, arena = message.arena, seed = message.seed, bots = message.bots,'),
    ],
    # the match screen's static nodes only use the clashdoz atlases; result / scoreboard atlases belonged to the pages we dropped
    "clashdoz_game.gui": [
        (r'textures \{\n  name: "[^"]*"\n  texture: "/shared/result.atlas"\n\}\n', ""),
        (r'textures \{\n  name: "[^"]*"\n  texture: "/shared/scoreboard.atlas"\n\}\n', ""),
    ],
}

STUBS = {
    "shared/i18n.lua": '''-- arena stub: English only (user 2026-11-09). t() returns the English key unchanged.
local M = { lang = "en", LANGS = {} }
function M.t(s) return s end
function M.init() end
function M.fit(node, max_w) if gui and gui.set_scale then end end
function M.set_lang() end
return M
''',
    "shared/result_ui.lua": "-- arena stub: no result page\nlocal M = {}\nfunction M.update() end\nfunction M.show() end\nfunction M.hide() end\nfunction M.on_input() return false end\nreturn M\n",
    "shared/scoreboard_ui.lua": "-- arena stub: no leaderboard\nlocal M = {}\nfunction M.open() end\nfunction M.close() end\nfunction M.is_open() return false end\nfunction M.on_input() return false end\nreturn M\n",
    "shared/scores.lua": "-- arena stub\nlocal M = {}\nfunction M.submit() end\nreturn M\n",
    "shared/coin.lua": "-- arena stub: no coins\nlocal M = {}\nfunction M.get_balance() return 0 end\nfunction M.add() end\nfunction M.spend() return false end\nreturn M\n",
    "shared/earn.lua": "-- arena stub: no rewards\nlocal M = {}\nfunction M.expected() return 0 end\nfunction M.report() end\nreturn M\n",
    "shared/haptic.lua": "-- arena stub: web has no haptics\nlocal M = {}\nfor _, k in ipairs({ \"tap\", \"light\", \"medium\", \"heavy\", \"success\", \"warning\", \"error\", \"init\" }) do M[k] = function() end end\nreturn M\n",
    "shared/game_progress.lua": "-- arena stub: no level progress\nlocal M = {}\nfunction M.get_level() return 1 end\nfunction M.set_level() end\nfunction M.load() return { level = 1 } end\nfunction M.save() end\nfunction M.reset() end\nreturn M\n",
    "shared/cloud_save.lua": "-- arena stub\nlocal M = {}\nfunction M.mark_dirty() end\nreturn M\n",
    "games/clashdoz/cd_profile.lua": "-- arena stub: no skill cards / shop. Loadouts come from the arena draft.\nlocal M = { PRICES = { point = 100, slot = 500 } }\nfunction M.on_win() return 0 end\nfunction M.loadout() return {} end\nfunction M.slots() return 3 end\nreturn M\n",
    "games/clashdoz/cd_scores.lua": "-- arena stub: no local high scores\nlocal M = {}\nfunction M.record() end\nfunction M.list() return {} end\nreturn M\n",
}

MAIN_SCRIPT = '''-- game/main/main.script — arena bootstrap: load the Color Battle collection and start a match at once.
-- No cover, no prep page (user 2026-11-09). The controller decides what kind of match from the URL (see arena.lua).
local PROXY = "#clashdoz_proxy"

function init(self)
    msg.post(".", "acquire_input_focus")
    msg.post(PROXY, "load")
end

function on_message(self, message_id, message, sender)
    if message_id == hash("proxy_loaded") then
        msg.post(PROXY, "init")
        msg.post(PROXY, "enable")
        msg.post("clashdoz:/clashdoz#controller", "start_game", {})   -- the proxy collection's socket is its name
    end
end
'''

CONTROLLER = '''-- games/clashdoz/clashdoz_controller.script — arena version (replaces the PlayDoz controller: no cover / prep / levels).
-- start_game → with ?arena=live|replay in the URL the match comes from arena.lua (four LLM seats, or the log being
-- replayed); otherwise a quad match of the game's own bots with random level-1 skills (free smoke test, loops forever).
local levels = require("games.clashdoz.cd_levels")
local arena = require("games.clashdoz.arena")

local function start_bots(self)
    local seed = os.time()
    local loadout, enemies = levels.roll(4, levels.TRIAL_PLAN, seed, 3)
    msg.post("#game", "start_match", { layout = "quad", loadout = loadout, enemies = enemies, autopilot = true, eager = 0.7, seed = seed })
end

function init(self) end

function on_message(self, message_id, message, sender)
    if message_id == hash("start_game") then
        if arena.init() then
            arena.start(function(opts) msg.post("#game", "start_match", opts) end)
        else
            start_bots(self)
        end
    elseif message_id == hash("back_to_cover") or message_id == hash("next_level") or message_id == hash("retry_level") then
        if not arena.mode then start_bots(self) end
    end
end
'''

GAME_PROJECT = '''[project]
title = Color Battle Arena
version = 1.0.0

[bootstrap]
main_collection = /main/main.collectionc

[display]
width = 1080
height = 1920
high_dpi = 1
dynamic_orientation = 0
update_frequency = 60
display_profiles = /builtins/render/default.display_profilesc

[physics]
type = 2D
gravity_y = -9.8

[graphics]
texture_profiles = /game.texture_profiles
default_texture_min_filter = linear
default_texture_mag_filter = linear
max_draw_calls = 1024
max_characters = 8192
max_font_batches = 128

[input]
game_binding = /input/game.input_bindingc
gamepads = /builtins/input/default.gamepadsc

[sprite]
max_count = 2048
subpixels = 1

[gui]
max_count = 4096
max_animation_count = 4096
max_particlefx_count = 128

[collection_proxy]
max_count = 8

[sound]
max_sound_data = 128
max_sound_buffers = 32
max_sound_sources = 16
max_sound_instances = 256
max_component_count = 64

[resource]
max_resources = 2048

[script]
shared_state = 1

[label]
max_count = 256
subpixels = 1

[particle_fx]
max_count = 64
max_particle_count = 1024

[engine]
run_while_iconified = 0

[playdoz]
mode = standalone

[html5]
htmlfile = /web/engine_template.html
show_made_with_defold = 0
scale_mode = stretch
'''

TEXT_EXT = (".collection", ".go", ".gui", ".atlas", ".font", ".particlefx", ".sound", ".collectionproxy", ".script", ".gui_script", ".lua", ".material", ".input_binding", ".texture_profiles")
REF = re.compile(r'"(/(?:assets|shared|games|web|main|input)/[^"\s]+)"')
copied = set()


def src(res):
    return os.path.join(PLAYDOZ, res.lstrip("/"))


def dst(res):
    return os.path.join(DST, res.lstrip("/"))


def put(res, text):
    os.makedirs(os.path.dirname(dst(res)), exist_ok=True)
    open(dst(res), "w", encoding="utf-8").write(text)
    copied.add(res)


def copy(res, follow=True):
    """copy one resource; text resources pull in what they reference (atlases → images, fonts → ttf, sounds → audio)"""
    if res in copied:
        return
    s = src(res)
    if not os.path.exists(s):
        print("  missing:", res)
        return
    os.makedirs(os.path.dirname(dst(res)), exist_ok=True)
    name = os.path.basename(res)
    if name in PATCHES:
        txt = open(s, encoding="utf-8").read()
        for pat, rep in PATCHES[name]:
            txt, n = re.subn(pat, rep, txt, count=1)
            if n == 0:
                print("  patch did not match:", name, pat[:50])
        open(dst(res), "w", encoding="utf-8").write(txt)
    else:
        shutil.copy2(s, dst(res))
        txt = open(s, encoding="utf-8", errors="ignore").read() if res.endswith(TEXT_EXT) else ""
    copied.add(res)
    if follow and res.endswith(TEXT_EXT):
        for r in REF.findall(txt):
            if "*" not in r:
                copy(r)


def prune_atlas(res, drop_prefixes):
    """remove image entries whose file name starts with one of the prefixes, before the closure copies them"""
    txt = open(src(res), encoding="utf-8").read()
    kept = []
    for block in re.split(r"(?=^images \{)", txt, flags=re.M):
        m = re.search(r'image: "([^"]+)"', block)
        if m and os.path.basename(m.group(1)).startswith(drop_prefixes):
            continue
        kept.append(block)
    put(res, "".join(kept))
    for r in REF.findall("".join(kept)):
        copy(r)


def main():
    if os.path.isdir(DST):
        print("cleaning", os.path.abspath(DST))
        for name in os.listdir(DST):
            if name in ("build", "build_web", ".internal", ".gitignore"):
                continue
            p = os.path.join(DST, name)
            shutil.rmtree(p) if os.path.isdir(p) else os.remove(p)
    os.makedirs(DST, exist_ok=True)
    # generated game object / collection FIRST (the proxy references them; the originals would drag cover / prep / all sounds in)
    comps = ['components {\n  id: "controller"\n  component: "/games/clashdoz/clashdoz_controller.script"\n}\n',
             'components {\n  id: "game"\n  component: "/games/clashdoz/clashdoz_game.gui"\n}\n']
    comps += [f'components {{\n  id: "snd_{s}"\n  component: "/games/clashdoz/snd_{s}.sound"\n}}\n' for s in KEEP_SOUNDS]
    put(f"{G}/clashdoz.go", "".join(comps))
    put(f"{G}/clashdoz_controller.script", CONTROLLER)
    put(f"{G}/clashdoz.collection", 'name: "clashdoz"\ninstances {\n  id: "clashdoz"\n  prototype: "/games/clashdoz/clashdoz.go"\n  position {\n    x: 0.0\n    y: 0.0\n    z: 0.0\n  }\n  rotation {\n    x: 0.0\n    y: 0.0\n    z: 0.0\n    w: 1.0\n  }\n  scale3 {\n    x: 1.0\n    y: 1.0\n    z: 1.0\n  }\n}\nscale_along_z: 0\n')
    # the game
    for f in KEEP_GAME_FILES:
        if f == "clashdoz_fx.atlas":
            prune_atlas(f"{G}/{f}", DROP_FX_PREFIX)
        else:
            copy(f"{G}/{f}")
    for s in KEEP_SOUNDS:
        copy(f"{G}/snd_{s}.sound")
    # shared: two real modules, the rest stubs
    copy("/shared/layout.lua")
    copy("/shared/pill_btn.lua")
    copy("/shared/safe_area.lua")   # layout.lua needs it (web: no notch, returns 0)
    for res, text in STUBS.items():
        put("/" + res, text)
    # every require() in the copied Lua must resolve: report anything still missing
    for r, _, fs in os.walk(DST):
        for f in fs:
            if f.endswith((".lua", ".script", ".gui_script")) and "/build" not in r:
                for mod in re.findall(r'require\("([^"]+)"\)', open(os.path.join(r, f), encoding="utf-8", errors="ignore").read()):
                    if not os.path.exists(dst("/" + mod.replace(".", "/") + ".lua")):
                        print("  unresolved require:", mod, "in", f)
    # bootstrap, input, web template, texture profiles
    put("/main/main.script", MAIN_SCRIPT)
    put("/main/main.go", 'components {\n  id: "script"\n  component: "/main/main.script"\n}\ncomponents {\n  id: "clashdoz_proxy"\n  component: "/games/clashdoz/clashdoz.collectionproxy"\n}\n')
    put("/main/main.collection", 'name: "main"\ninstances {\n  id: "main"\n  prototype: "/main/main.go"\n  position {\n    x: 0.0\n    y: 0.0\n    z: 0.0\n  }\n  rotation {\n    x: 0.0\n    y: 0.0\n    z: 0.0\n    w: 1.0\n  }\n  scale3 {\n    x: 1.0\n    y: 1.0\n    z: 1.0\n  }\n}\nscale_along_z: 0\n')
    # the arena mode itself (source of truth lives outside game/ so a re-import cannot lose it)
    shutil.copy2(os.path.join(HERE, "..", "arena_game", "arena.lua"), dst(f"{G}/arena.lua")); copied.add(f"{G}/arena.lua")
    copy("/input/game.input_binding")
    copy("/web/engine_template.html")
    copy("/game.texture_profiles")
    open(os.path.join(DST, "game.project"), "w", encoding="utf-8").write(GAME_PROJECT)
    open(os.path.join(DST, ".gitignore"), "w").write("build/\nbuild_web/\n.internal/\n")
    files = [os.path.join(r, f) for r, _, fs in os.walk(DST) if "/build" not in r and "/.internal" not in r for f in fs]
    n, total = len(files), sum(os.path.getsize(f) for f in files)
    print(f"{n} files, {total / 1e6:.1f} MB → {os.path.relpath(DST)}")


if __name__ == "__main__":
    main()
