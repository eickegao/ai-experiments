-- games/clashdoz/arena.lua — four LLMs play Color Battle inside the real game (docs/2026-11-09-arena-mode-design.md).
-- Source of truth: color-battle-arena/arena_game/arena.lua (tools/import_game.py copies it into game/games/clashdoz/).
--
-- The game is the only simulation. In LIVE mode the match screen pauses every DEC_STEPS fixed steps (2 s of game time),
-- POSTs a snapshot to the local arena server (arena_server.py), which asks the four models in parallel and answers with
-- commands; the game applies them through cd_sim.command (the engine decides legality), logs them with the tick, and
-- resumes. Game time never advances while models think. In REPLAY mode the game loads a finished game's JSON and
-- re-applies the logged commands at the same ticks → identical frames (same wasm build, same seed, same commands).
--
-- URL (HTML5 only):  ?arena=live&game=1[&server=http://host:port]      ?arena=replay&log=/results/<run>/game_1.json[&speed=1]
-- The page and the server are normally the same origin (arena_server.py serves the bundle), so paths are relative.
-- When done: window.__arena_done = 1 (window.__arena_error = "…" on failure).
local sim = require("games.clashdoz.cd_sim")
local C = require("games.clashdoz.cd_config")

local M = { mode = nil, params = {}, names = {}, bots = {}, log = {}, timeline = {}, asked = {}, last = {}, waiting = false,
            decision = 0, done = false, replay = nil, by_tick = nil, mismatch = 0, speed = 1 }
local DEC_STEPS = 120                       -- 2 s of game time at FIXED_DT = 1/60
local LETTERS = { "A", "B", "C", "D" }
local TEAM_OF = { A = 1, B = 2, C = 3, D = 4 }
local N_DECISIONS = math.floor(C.ROUND_TIME / (DEC_STEPS * C.FIXED_DT) + 0.5)

local function url_params()
    if not html5 then return {} end
    local ok, q = pcall(html5.run, "window.location.search || ''")
    if not ok or type(q) ~= "string" then return {} end
    local t = {}
    for k, v in q:gmatch("[?&]([^=&]+)=([^&]*)") do
        t[k] = (v:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
    end
    return t
end

local function js(code) if html5 then pcall(html5.run, code) end end

local function request(method, path, body, cb)
    local url = ((M.params.server and M.params.server ~= "") and M.params.server or "") .. path
    http.request(url, method, function(_, _, resp)
        if resp.status >= 200 and resp.status < 300 then
            local ok, data = pcall(json.decode, resp.response or "")
            if ok then cb(data, nil) else cb(nil, "bad json from " .. path) end
        else
            cb(nil, "http " .. tostring(resp.status) .. " " .. path)
        end
    end, { ["Content-Type"] = "application/json" }, body and json.encode(body) or nil, { timeout = 900 })
end

--- skill catalogue for the draft prompt: every skill at level 1 (ids in cd_config order)
local function catalog()
    local out = {}
    for _, id in ipairs(C.SKILL_IDS) do
        local d = C.SKILLS[id]
        if d then
            local p = {}   -- every number per level {l1, l2, l3}; the server picks the level the match is played at
            for _, key in ipairs({ "radius", "mult", "dur", "count", "window", "arc", "stun", "extra", "max", "life", "steps" }) do
                if type(d[key]) == "table" then p[key] = { d[key][1], d[key][2], d[key][3] } end
            end
            out[#out + 1] = { id = id, name = d.name, cd = { d.cd[1], d.cd[2], d.cd[3] }, target = d.target and true or false, params = p }
        end
    end
    return out
end

function M.init()
    M.params = url_params()
    M.mode = M.params.arena
    M.game = tonumber(M.params.game or "1") or 1
    M.speed = tonumber(M.params.speed or "1") or 1
    if M.mode then print("[arena] mode=" .. M.mode .. " game=" .. M.game) end
    return M.mode
end

--- setup = { seed, teams = { A = { name, model, bot, skills = { {id, level}, … } }, … } } → start_match opts
local function apply_setup(setup)
    M.seed = setup.seed
    local opts = { layout = "quad", arena = true, seed = setup.seed, enemies = {}, bots = {}, eager = 0.7 }
    for t = 1, 4 do
        local team = setup.teams[LETTERS[t]] or {}
        M.names[t] = team.name or LETTERS[t]
        M.bots[t] = team.bot and true or false
        opts.bots[t] = M.bots[t]
        local skills = {}
        for k, sk in ipairs(team.skills or {}) do skills[k] = { id = sk.id, level = sk.level or 1 } end
        if t == 1 then opts.loadout = skills else opts.enemies[t] = { skills = skills } end
    end
    return opts
end

--- live: ask the server for the draft; replay: load the log. cb(opts) when ready.
function M.start(cb)
    if M.mode == "live" then
        request("POST", "/draft", { game = M.game, catalog = catalog(), n_decisions = N_DECISIONS, decision_dt = DEC_STEPS * C.FIXED_DT },
            function(d, err)
                if not d then print("[arena] draft failed: " .. tostring(err)); js("window.__arena_error = " .. json.encode(tostring(err))); return end
                cb(apply_setup(d))
            end)
    elseif M.mode == "replay" then
        request("GET", M.params.log or "", nil, function(d, err)
            if not d then print("[arena] log load failed: " .. tostring(err)); js("window.__arena_error = " .. json.encode(tostring(err))); return end
            M.replay = d
            M.by_tick = {}
            for _, c in ipairs(d.commands or {}) do
                M.by_tick[c.tick] = M.by_tick[c.tick] or {}
                table.insert(M.by_tick[c.tick], c)
            end
            cb(apply_setup(d.setup))
        end)
    end
end

local function counts_of(s)
    local out = { neutral = s.counts[0] or 0 }
    for t = 1, 4 do out[LETTERS[t]] = s.counts[t] or 0 end
    return out
end

local function snapshot(m, s)
    local grid = {}
    for j = 1, 32 do
        local row = {}
        for i = 1, 32 do
            local v = s.grid[i][j]
            row[i] = (v == 0 or v == false or v == nil) and "." or LETTERS[v]
        end
        grid[j] = table.concat(row)
    end
    local balls, skills, turn_cd, frozen = {}, {}, {}, {}
    for t = 1, 4 do
        local tm = s.teams[t]
        local L = LETTERS[t]
        balls[L] = {}
        for k, b in ipairs(tm.balls) do balls[L][k] = { b.x, b.y, b.dx, b.dy } end
        skills[L] = {}
        for k, e in ipairs(tm.skills) do
            skills[L][k] = { slot = k, id = e.id, level = e.level, cd = math.floor((tm.cd[e.id] or 0) * 10 + 0.5) / 10, ready = sim.can_cast(s, tm, k) and true or false }
        end
        turn_cd[L] = math.floor((tm.turn_cd or 0) * 100 + 0.5) / 100
        frozen[L] = sim.is_frozen(s, tm) and true or false
    end
    return { game = M.game, decision = M.decision, tick = m.tick or 0, t = s.elapsed, time_left = s.time_left, counts = counts_of(s),
             grid = grid, balls = balls, skills = skills, turn_cd = turn_cd, frozen = frozen, last = M.last }
end

local function apply(m, s, letter, cmd)
    local t = TEAM_OF[letter]
    if cmd.type == "wait" then return true end
    return sim.command(s, t, { type = cmd.type, x = cmd.x, y = cmd.y, slot = cmd.slot }) and true or false
end

--- called before every fixed step. Returns false while the models are still thinking (the caller then skips stepping).
function M.before_step(m, s)
    if M.done then return true end
    local tick = m.tick or 0
    if M.mode == "replay" then
        local list = M.by_tick and M.by_tick[tick]
        if list then
            for _, c in ipairs(list) do
                local ok = apply(m, s, c.team, c.cmd)
                if ok ~= (c.accepted and true or false) then M.mismatch = M.mismatch + 1 end
            end
        end
        return true
    end
    if M.waiting then return false end
    if tick % DEC_STEPS == 0 and M.decision < N_DECISIONS and not M.asked[tick] then
        M.asked[tick] = true
        M.waiting = true
        M.decision = M.decision + 1
        local snap = snapshot(m, s)
        local t0 = socket and socket.gettime and socket.gettime() or os.time()
        request("POST", "/decide", snap, function(d, err)
            if not d then
                print("[arena] decide failed at tick " .. tick .. ": " .. tostring(err))
                M.waiting = false
                return
            end
            -- rotating order so no team is always first inside a decision
            local first = (M.decision - 1) % 4
            M.last = {}
            for k = 0, 3 do
                local L = LETTERS[(first + k) % 4 + 1]
                local verdicts = {}
                for _, cmd in ipairs((d.cmds and d.cmds[L]) or {}) do
                    local ok = apply(m, s, L, cmd)
                    M.log[#M.log + 1] = { tick = tick, team = L, cmd = cmd, accepted = ok }
                    verdicts[#verdicts + 1] = (cmd.text or cmd.type) .. (ok and " -> accepted" or " -> REJECTED")
                end
                M.last[L] = #verdicts > 0 and table.concat(verdicts, "; ") or (d.note and d.note[L]) or "(no valid CMD line found, nothing was done)"
            end
            local dt = (socket and socket.gettime and socket.gettime() or os.time()) - t0
            print(string.format("[arena] decision %d/%d at t=%.0fs took %.1fs", M.decision, N_DECISIONS, s.elapsed, dt))
            M.waiting = false
        end)
        return false
    end
    return true
end

--- after every fixed step: cell counts at 10 Hz for the charts
function M.after_step(m, s)
    if (m.tick or 0) % 6 == 0 then
        local row = { math.floor((m.tick or 0) * C.FIXED_DT * 10 + 0.5) / 10 }
        for t = 1, 4 do row[t + 1] = s.counts[t] or 0 end
        M.timeline[#M.timeline + 1] = row
    end
end

local function final_of(s)
    local rank = sim.ranking(s)
    local ranking = {}
    for k = 1, 4 do ranking[k] = LETTERS[rank[k]] end
    return { counts = counts_of(s), ranking = ranking, winner = ranking[1] }
end

function M.on_finish(m, s)
    if M.done then return end
    M.done = true
    local final = final_of(s)
    if M.mode == "live" then
        request("POST", "/finish", { game = M.game, commands = M.log, timeline = M.timeline, final = final }, function(d, err)
            if err then print("[arena] finish failed: " .. tostring(err)); js("window.__arena_error = " .. json.encode(tostring(err))) end
            js("window.__arena_done = 1")
            print("[arena] game over: " .. final.winner .. " wins; " .. #M.log .. " commands logged")
        end)
    else
        local want = (M.replay and M.replay.final and M.replay.final.counts) or {}
        local same = true
        for _, L in ipairs(LETTERS) do if want[L] ~= nil and want[L] ~= final.counts[L] then same = false end end
        local ok = same and M.mismatch == 0
        print(ok and "ARENA_REPLAY_OK" or ("ARENA_REPLAY_MISMATCH verdicts=" .. M.mismatch .. " counts=" .. json.encode(final.counts) .. " want=" .. json.encode(want)))
        -- release builds do not forward print() to the browser console, so the recorder reads this instead
        js("window.__arena_replay = " .. json.encode({ ok = ok, mismatch = M.mismatch, counts = final.counts, want = want }))
        js("window.__arena_done = 1")
    end
end

return M
