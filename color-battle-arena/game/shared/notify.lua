-- shared/notify.lua
-- 本地通知召回（spec docs/superpowers/specs/2026-10-02-notification-design.md，用户 2026-10-02 定案）：
-- 服务端 /api/config.notify 下发规则（时段/天数/模板），缓存本地；退后台时按本地状态（最后玩的游戏）排未来 days 天
-- 每天 slots 条；回前台全部取消。点开直达游戏并上报 notif_open。只在手机版生效。
-- extension-push 4.2.1（Defold 1.13 可用；4.3 起要 1.14）。权限：首次进大厅请求（dashboard.gui_script）。
local M = {}
M.on_open = nil   -- 点通知打开时回调(payload 表)

local function is_web() return sys.get_sys_info().system_name == "HTML5" end
local function has_push() return push ~= nil and push.schedule ~= nil end

-- 与后端 src/notify_defaults.ts 同结构；没网没缓存时用
M.DEFAULT_CFG = {
    enabled = true, slots = { "12:00", "13:00", "18:00", "21:00" }, days = 14,
    featured = { "watersort", "nutssort", "triopop", "ballsort", "hexmerge", "pupdoku" },
    game_names = { flashlinez = "Flash Linez", dropline = "Dropline", arrow = "Arrow", dicewars = "Dice Wars", watersort = "Water Sort",
        pupdoku = "Pupdoku", picfitz = "Picfitz", nutssort = "Nuts Sort", tapix = "Tapix", cattrail = "Cattrail",
        spinbound = "SpinBound", wordoz = "WorDoz", triopop = "Trio Pop", carddoz = "CardDoz", ballsort = "Ball Sort", hexmerge = "Hexa Merge" },
    templates = {
        { id = "resume_wait",   kind = "resume", title = "🧩 Level {next_level} is waiting",   body = "You stopped at {game_name} level {level} — ready to go on?" },
        { id = "resume_ask",    kind = "resume", title = "🤔 Have you finished level {level}?", body = "{game_name} is waiting — a few minutes is all it takes" },
        { id = "resume_brain",  kind = "resume", title = "🧠 A quick brain workout?",          body = "{game_name} level {next_level} is ready for you" },
        { id = "resume_quiet",  kind = "resume", title = "🌙 End the day with a puzzle",       body = "{game_name} level {next_level} — no rush, step by step" },
        { id = "resume_gentle", kind = "resume", title = "🐾 Tangled thoughts?",               body = "{game_name} level {next_level} untangles them 🧩" },
        { id = "resume_logic",  kind = "resume", title = "🔍 Not trial and error",             body = "Level {next_level} of {game_name} is pure logic — try it" },
        { id = "resume_short",  kind = "resume", title = "⏱️ Got two minutes?",                body = "That's all {game_name} level {next_level} needs" },
        { id = "resume_back",   kind = "resume", title = "👋 {game_name} missed you",          body = "Level {next_level} has been waiting since you cleared {level}" },
        { id = "away_day",      kind = "away",   title = "👀 We waited for you all day",       body = "The puzzle is ready. Are you? 🧩" },
        { id = "away_quiet",    kind = "away",   title = "🤫 You're too quiet today",          body = "Come think with me 🧠" },
        { id = "away_long",     kind = "away",   title = "😌 I heard you had a long day",      body = "A puzzle is my prescription for that 🌿" },
        { id = "away_sleepy",   kind = "away",   title = "😴 Sleepy eyes are fine",            body = "This puzzle is gentle 🧸" },
        { id = "invite_try",    kind = "invite", title = "🎮 Try {game_name} today",           body = "A gentle puzzle to untangle your thoughts 🧩" },
        { id = "invite_live",   kind = "invite", title = "☀️ Today's puzzles are live!",        body = "{game_name} is all set and waiting for you" },
        { id = "invite_brain",  kind = "invite", title = "🌸 Bloom your brain!",               body = "Start with {game_name} — let your mind blossom" },
        { id = "invite_step",   kind = "invite", title = "🐱 Step by step, no rush",           body = "{game_name} is a calm place to think" },
    },
}

--- 占位符替换：{key} → vars[key]，缺的替换为空
function M.fill(s, vars)
    return (tostring(s):gsub("{([%w_]+)}", function(k) local v = vars[k]; return v == nil and "" or tostring(v) end))
end

--- now 所在本地日起第 k 天的 "HH:MM"（秒）
function M.slot_time(now, hhmm, k)
    local h, mi = hhmm:match("^(%d+):(%d+)$")
    local t = os.date("*t", now)
    t.day = t.day + (k or 0)   -- 加天数而不是加 86400 秒：跨夏令时切换也落在当天的 HH:MM（审查 I3）
    t.hour, t.min, t.sec, t.isdst = tonumber(h) or 12, tonumber(mi) or 0, 0, nil
    return os.time(t)
end

--- 设备语言 → l10n 里的键。实现搬到 shared/i18n.lua（2026-10-10），这里只转发，签名不变。
--- 注意：i18n 不 require 任何业务模块，所以这里引用它没有循环（earn → notify → i18n 单向）。
function M.pick_lang(l10n, device_lang, lang, territory)
    return require("shared.i18n").pick_lang(l10n, device_lang, lang, territory)
end

local function pool(templates, kind) local p = {} for _, t in ipairs(templates) do if t.kind == kind then p[#p + 1] = t end end return p end
-- 轮换：起点 = 游标（每次 plan 只前进 1，审查 I1：按排的条数推进会让每天看到的前几条一样），序列内按 seq 递增
local function pick(p, cursor, seq, key) local n = #p; if n == 0 then return nil end; local i = ((cursor[key] or 0) + (seq[key] or 0)) % n + 1; seq[key] = (seq[key] or 0) + 1; return p[i] end

--- 排程纯函数：ctx.last_played = {game, level, at}|nil；cfg 规则；now 当前；cursor 轮换游标（可 nil）
--- 返回 list（按时间升序，每项 {fire_at, title, body, payload={kind,tpl,game,level}}）与新游标
--- 用户 2026-10-03 定案：当天打开过 App 就当天一条不发，只提醒没来的日子。排程发生在退后台（当天必然打开过），
--- 所以从明天起排；排到的每一天都是"没来"的（哪天来了，打开 App 就全取消再重排）。
--- 池：有最后玩的游戏 → resume；没有 → invite（{game_name} 轮换 featured）；时段 ≥ 20 点 → away，一天最多一条
function M.plan(ctx, cfg, now, cursor)
    cfg = cfg or M.DEFAULT_CFG
    if cfg.enabled == false then return {}, cursor or {} end
    local templates = (type(cfg.templates) == "table" and #cfg.templates > 0) and cfg.templates or M.DEFAULT_CFG.templates
    local slots = (type(cfg.slots) == "table" and #cfg.slots > 0) and cfg.slots or M.DEFAULT_CFG.slots
    local days = tonumber(cfg.days) or M.DEFAULT_CFG.days
    local featured = (type(cfg.featured) == "table" and #cfg.featured > 0) and cfg.featured or M.DEFAULT_CFG.featured
    local names = cfg.game_names or M.DEFAULT_CFG.game_names
    cursor = cursor or {}
    local seq = {}
    local lang = ctx and ctx.lang
    local tr = (lang and type(cfg.l10n) == "table") and cfg.l10n[lang] or nil   -- 该语言的翻译表（模板 id → {title, body}）
    local lp = ctx and ctx.last_played
    local known = lp and lp.game and names[lp.game] ~= nil
    local next_lv = known and (tonumber(lp.level) or 1) or 1          -- 存档 level 语义 = 下一关要玩的关号（审查 C1）
    local has_game = known and next_lv > 1                            -- 一关没过（或不走 set_level 的游戏）→ 邀请池邀请它（审查 I2）
    local P = { resume = pool(templates, "resume"), away = pool(templates, "away"), invite = pool(templates, "invite") }
    local out = {}
    for k = 1, days do   -- 从明天起（今天打开过，不发）
        local away_used = false
        for _, hhmm in ipairs(slots) do
            local fire = M.slot_time(now, hhmm, k)
            if fire > now then
                local hour = tonumber(hhmm:match("^(%d+)")) or 0
                local kind = has_game and "resume" or "invite"
                if hour >= 20 and not away_used and #P.away > 0 then kind = "away" end
                local t = pick(P[kind], cursor, seq, kind)
                if not t and kind == "away" then kind = has_game and "resume" or "invite"; t = pick(P[kind], cursor, seq, kind) end
                if t then
                    if kind == "away" then away_used = true end
                    local game, level = nil, nil   -- level = 刚过的关；next_lv = 等着的关
                    if kind == "resume" then game, level = lp.game, next_lv - 1
                    elseif kind == "invite" then
                        if known then game = lp.game
                        else game = featured[((cursor.featured or 0) + (seq.featured or 0)) % #featured + 1]; seq.featured = (seq.featured or 0) + 1 end
                    end
                    local vars = { game_name = game and (names[game] or game) or "", level = level or "", next_level = level and next_lv or "" }
                    local loc = tr and tr[t.id]
                    local title, body = (loc and loc.title) or t.title, (loc and loc.body) or t.body
                    out[#out + 1] = { fire_at = fire, title = M.fill(title, vars), body = M.fill(body, vars),
                        payload = { kind = kind, tpl = t.id, game = game, level = (kind == "resume") and next_lv or nil } }
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.fire_at < b.fire_at end)
    for k in pairs(seq) do cursor[k] = (cursor[k] or 0) + 1 end   -- 下次从下一条起（见 pick 注释）
    return out, cursor
end

-- ---------- 本地状态 ----------
local function path(name) return sys.get_save_file("playdoz", name) end
local function valid_cfg(c) return type(c) == "table" and type(c.templates) == "table" and #c.templates > 0 end

--- 服务端规则缓存（/api/config.notify）：非法/没模板不覆盖
function M.save_cfg(c) if valid_cfg(c) then sys.save(path("notify_cfg"), c) end end
function M.load_cfg() local c = sys.load(path("notify_cfg")); return valid_cfg(c) and c or M.DEFAULT_CFG end

--- 最后玩的游戏（进游戏/过关时记；续关模板与"今天玩过"判断用；入云存档）
function M.set_last_played(game, level)
    if not M.DEFAULT_CFG.game_names[game] then return end   -- WorDoz 子玩法等非合集键不记（审查 I2）
    sys.save(path("last_played"), { game = game, level = tonumber(level) or 1, at = os.time() })
    pcall(function() require("shared.cloud_save").mark_dirty() end)
end
function M.get_last_played() local t = sys.load(path("last_played")); return (type(t) == "table" and t.game) and t or nil end

--- 退到后台时调用：清掉旧的，按规则排未来 days 天
function M.schedule()
    if is_web() or not has_push() then return end
    M.cancel_all()
    local st = sys.load(path("notify_state")) or {}
    local cfg = M.load_cfg()
    local info = sys.get_sys_info()
    local lang = M.pick_lang(cfg.l10n, info.device_language, info.language, info.territory)
    local ok, list, cursor = pcall(M.plan, { last_played = M.get_last_played(), lang = lang }, cfg, os.time(), st.cursor)
    if not ok then   -- 服务端下发的规则有坏数据：退回内置默认，不能一条不排（审查）
        print("[notify] plan failed with server cfg, using defaults: " .. tostring(list))
        list, cursor = M.plan({ last_played = M.get_last_played(), lang = M.pick_lang(M.DEFAULT_CFG.l10n, info.device_language, info.language, info.territory) }, M.DEFAULT_CFG, os.time(), st.cursor)
    end
    local now, n = os.time(), 0
    for _, it in ipairs(list) do
        local ok, err = pcall(push.schedule, it.fire_at - now, it.title, it.body, json.encode(it.payload), { action = "Play" })
        if ok then n = n + 1 else print("[notify] schedule failed " .. tostring(err)) end
    end
    st.cursor = cursor; sys.save(path("notify_state"), st)
    print("[notify] scheduled " .. n .. "/" .. #list .. " lang=" .. tostring(lang) .. (list[1] and (" first " .. os.date("%m-%d %H:%M", list[1].fire_at) .. " " .. list[1].title) or ""))
end

local function save_path() return sys.get_save_file("playdoz", "notify") end
local function state() return sys.load(save_path()) or {} end

--- iOS：弹系统权限框（只问一次，结果存档）。Android 旧版本不需要；13+ 待接权限扩展
function M.request_permission(cb)
    if is_web() or not has_push() then if cb then cb(false) end return end
    local st = state()
    if st.asked then if cb then cb(st.granted == true) end return end
    local types = { push.NOTIFICATION_ALERT, push.NOTIFICATION_SOUND, push.NOTIFICATION_BADGE }   -- 必须是类型表
    local ok, e = pcall(push.register, types, function(_, token, err)
        st.asked = true
        -- 没有 aps-environment 权限（远程推送能力未开）只影响远程 token，本地通知不受影响：视为已问过且可用
        local msg = err and tostring(err.error or err) or ""
        st.granted = (err == nil) or msg:find("aps%-environment") ~= nil
        sys.save(save_path(), st)
        print("[notify] register -> " .. tostring(err == nil) .. " " .. tostring(err and err.error or ""))
        if cb then cb(st.granted) end
    end)
    if not ok then print("[notify] register call failed: " .. tostring(e)) end
end

function M.cancel_all()
    if has_push() and push.cancel_all_issued then pcall(push.cancel_all_issued) end
    if has_push() and push.get_all_scheduled and push.cancel then
        local ok, all = pcall(push.get_all_scheduled)
        if ok and type(all) == "table" then for id in pairs(all) do pcall(push.cancel, id) end end
    end
end

--- 通知 payload：字符串 JSON 或已是表 → 表；坏的 → nil
function M.parse_payload(payload)
    if type(payload) == "table" then return payload end
    if type(payload) ~= "string" then return nil end
    local ok, t = pcall(json.decode, payload)
    return (ok and type(t) == "table") and t or nil
end

function M.init()
    if is_web() or not has_push() then return end
    push.set_listener(function(_, payload, origin, activated)
        local p = M.parse_payload(payload)
        print("[notify] opened origin=" .. tostring(origin) .. " activated=" .. tostring(activated) .. " tpl=" .. tostring(p and p.tpl))
        if activated and p then
            pcall(function() require("shared.earn").track("notif_open", { tpl = p.tpl, game = p.game }) end)
            if M.on_open then pcall(M.on_open, p) end
        end
    end)
    M.cancel_all()   -- 回到前台/启动：今天来过了，不再提醒
end

return M
