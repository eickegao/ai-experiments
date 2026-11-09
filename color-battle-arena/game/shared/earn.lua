-- shared/earn.lua
-- 游戏奖励金币的服务端发币（参赛积分）：每局带 HMAC 签名上报 /api/earn，服务端核验（关卡连号、间隔、日上限、
-- 连续打卡倍数）后发币并返回实发数与余额。本地先按预估金额加（动画照常），回包后以服务端余额为准。
-- 只在手机版生效；HTML5 走旧的 coin.add。设计见 docs/superpowers/specs/2026-10-01-checkin-ranking-design.md
local coin = require("shared.coin")
local sha = require("shared.sha256")
local M = {}

M.SECRET = "e1e0687a117798493fbbe751fe047a11595d40e737f1a46f4e70bf73f49fe463"   -- 与服务端 EARN_SECRET_V1 相同
M.state = { enabled_checkin = false, enabled_ranking = false, mult = 1, streak_day = 1, played_today = false,
            checked_today = false, week_points = 0, week_end_epoch = 0, contact_email = "", prize_text = "" }

local function is_web() return sys.get_sys_info().system_name == "HTML5" end
-- nonce：不能依赖全局 math.random（各游戏会用固定种子 randomseed，重复概率不可控，审查 I5）。
-- 时间（8 hex）+ 本进程单调计数（4 hex）+ 启动时随机盐（4 hex）= 16 hex，本机不重复
local counter, salt = 0, nil
function M.new_nonce()
    if not salt then salt = (os.clock() * 1000003 + os.time()) % 65536 end
    counter = (counter + 1) % 65536
    return string.format("%08x%04x%04x", os.time() % 4294967296, counter, salt)
end
local nonce = M.new_nonce

-- 不带手机时间：手机时钟不可信，服务端只按请求到达时间判间隔（用户 2026-10-01 定）
function M.build_body(game, event, level, base, nc)
    local b = { device_id = coin.get_device_id(), game = game, event = event, level = level, base = base, nonce = nc }
    b.sig = sha.hmac_hex(M.SECRET, table.concat({ b.device_id, game, event, tostring(level), tostring(base), nc }, "|"))
    b.kv = "v1"   -- 密钥版本（轮换时客户端换新 kv，服务端按版本取密钥）
    b.app_version = sys.get_config_string and sys.get_config_string("project.version", "") or ""
    return b
end

function M.expected(base) return base * (M.state.mult or 1) end

--- 图片类游戏的图名 → 稳定整数 id（服务端按 level 对同一图只发一次）；数字原样返回
function M.key_id(key)
    if type(key) == "number" then return key end
    local h = 7
    for i = 1, #tostring(key) do h = (h * 31 + string.byte(key, i)) % 1000000007 end
    return h
end

local function apply_me(d)
    if type(d) ~= "table" then return end
    local s = M.state
    s.mult = d.mult_today or s.mult; s.streak_day = d.streak_day or s.streak_day
    if d.today then s.played_today = d.today.played and true or false; s.checked_today = d.today.checked and true or false end
    s.week_points = d.week_points or s.week_points; s.week_end_epoch = d.week_end_epoch or s.week_end_epoch
    s.nickname = d.nickname; s.avatar = d.avatar; s.country = d.country
    s.rank = d.rank; s.country_rank = d.country_rank; s.last_week = d.last_week
    s.server_balance = d.balance   -- 只记录不覆盖：余额只由 /api/earn 回包更新（启动对账竞态，2026-10-01 真机踩到）
    if M.on_change then pcall(M.on_change) end
end

--- 回大厅时重拉个人状态（倍数/今日已玩已打卡/本周积分）
function M.refresh(cb)
    if is_web() then if cb then cb(false) end return end
    local plat = M.platform_of(sys.get_sys_info())
    http.request(coin._api_url .. "/api/me?device_id=" .. coin.get_device_id() .. (plat and ("&platform=" .. plat) or ""), "GET", function(_, _, r)
        local ok, d = false, nil
        if r.status == 200 then ok, d = pcall(json.decode, r.response) end
        if ok then apply_me(d) end
        if cb then cb(ok) end
    end)
end

--- 拉开关与文案（启动一次 + 每次回大厅再拉，便于服务端随时开关）
--- 事件上报（2026-10-02）：只记录不发币，失败不管（通知点开等）→ POST /api/event
function M.track(kind, extra)
    if is_web() then return end
    local b = { device_id = coin.get_device_id(), type = kind, app_version = sys.get_config_string("project.version", "") }
    for k, v in pairs(extra or {}) do b[k] = v end
    pcall(http.request, coin._api_url .. "/api/event", "POST", function() end, { ["Content-Type"] = "application/json" }, json.encode(b))
end

M.on_notify_cfg = nil   -- 由 main.script 设为 notify.save_cfg（2026-10-02）

--- 平台标注（用户 2026-10-05，后台按平台看注册/活跃）：ios_iphone / ios_ipad / android；网页、桌面 → nil
function M.platform_of(info)
    local sn, model = tostring(info.system_name or ""), tostring(info.device_model or "")
    if sn == "iPhone OS" or sn == "iOS" then return model:match("^iPad") and "ios_ipad" or "ios_iphone" end
    if sn == "Android" then return "android" end
    return nil
end

function M.fetch_config()
    if is_web() then return end
    http.request(coin._api_url .. "/api/config", "GET", function(_, _, r)
        if r.status ~= 200 then return end
        local ok, d = pcall(json.decode, r.response)
        if not ok or type(d) ~= "table" then return end
        M.state.enabled_checkin = d.checkin_enabled and true or false
        M.state.enabled_ranking = d.ranking_enabled and true or false
        M.state.contact_email = d.contact_email or ""; M.state.prize_text = d.prize_text or ""
        if type(d.notify) == "table" and M.on_notify_cfg then pcall(M.on_notify_cfg, d.notify) end   -- 通知规则 → notify.save_cfg（main.script 接线；不能直接 require notify：bob 判循环依赖）
        if M.on_change then pcall(M.on_change) end
    end)
end
M.init_config_if_needed = M.fetch_config

function M.init()
    if is_web() then return end
    M.fetch_config()
    M.refresh()
end

--- 一局结束上报。返回本地预估金额（供演出显示）；on_done(amount|nil, resp|nil) 在回包后调用
function M.report(game, event, level, base, on_done)
    if is_web() then coin.add(base, game .. "_" .. event); if on_done then on_done(base) end; return base end
    local exp = M.expected(base)
    coin.add_local(exp)
    local body = M.build_body(game, event, level or 0, base, nonce())
    http.request(coin._api_url .. "/api/earn", "POST", function(_, _, r)
        local ok, d = false, nil
        if r.status == 200 then ok, d = pcall(json.decode, r.response) end
        if ok and type(d) == "table" and d.ok then
            if coin.is_authoritative() then
                coin.set_balance(d.balance)
            else
                -- 老存档还没完成对账：整体覆盖会把本地差额抹掉，只修正这一笔的差值（审查 I2b）
                coin.add_local((d.amount or exp) - exp)
            end
            M.state.mult = d.mult or M.state.mult; M.state.streak_day = d.streak_day or M.state.streak_day
            M.state.played_today = true; M.state.checked_today = not d.checkin_ready   -- 打卡改为大厅点宝箱（用户 2026-10-05），不再随首局自动
            if M.on_change then pcall(M.on_change) end
            if on_done then on_done(d.amount, d) end
        else
            print("[earn] rejected " .. game .. ":" .. event .. " " .. tostring(ok and d and d.reason or r.status))
            if on_done then on_done(nil, ok and d or nil) end
        end
    end, { ["Content-Type"] = "application/json" }, json.encode(body))
    return exp
end

local function post_json(path, body, cb)
    http.request(coin._api_url .. path, "POST", function(_, _, r)
        local ok, d = false, nil
        if r.status == 200 then ok, d = pcall(json.decode, r.response) end
        cb(ok and type(d) == "table" and d or nil)
    end, { ["Content-Type"] = "application/json" }, json.encode(body))
end

--- 领今天的打卡奖励（前提：今天已玩过一局）。cb(ok, resp|nil)；resp.reason ∈ not_played | already
function M.checkin(cb)
    if is_web() then if cb then cb(false, nil) end return end
    post_json("/api/checkin", { device_id = coin.get_device_id() }, function(d)
        if d and d.ok then
            if coin.is_authoritative() then coin.set_balance(d.balance) else coin.add_local(d.reward or 0) end
            M.state.checked_today = true
            M.state.streak_day = d.streak_day or M.state.streak_day
            M.state.checkin_reward_today = d.reward
            if M.on_change then pcall(M.on_change) end
            if cb then cb(true, d) end
        else
            if cb then cb(false, d) end
        end
    end)
end

--- 昵称/头像。cb(ok, resp|nil)；resp.reason == "nickname_blocked" 时提示换名
function M.set_profile(nickname, avatar, cb)
    if is_web() then if cb then cb(false, nil) end return end
    post_json("/api/profile", { device_id = coin.get_device_id(), nickname = nickname, avatar = avatar }, function(d)
        if d and d.ok then
            M.state.nickname, M.state.avatar = d.nickname, d.avatar
            if M.on_change then pcall(M.on_change) end
            if cb then cb(true, d) end
        else
            if cb then cb(false, d) end
        end
    end)
end

local function get_json(path, cb)
    http.request(coin._api_url .. path, "GET", function(_, _, r)
        local ok, d = false, nil
        if r.status == 200 then ok, d = pcall(json.decode, r.response) end
        cb(ok and type(d) == "table" and d or nil)
    end)
end

--- 周榜：scope = "global" | "country"，country 国家码（scope=country 时）。cb(data|nil)
function M.fetch_ranking(scope, country, cb)
    if is_web() then cb(nil) return end
    local q = "/api/ranking?device_id=" .. coin.get_device_id() .. "&scope=" .. (scope or "global")
    if scope == "country" and country then q = q .. "&country=" .. country end
    get_json(q, cb)
end

--- 国家榜。cb(data|nil)
function M.fetch_countries(cb)
    if is_web() then cb(nil) return end
    get_json("/api/ranking/countries?device_id=" .. coin.get_device_id(), cb)
end

--- 状态有变化时（refresh / report / checkin / set_profile）调用；大厅用它刷新卡片
M.on_change = nil

return M
