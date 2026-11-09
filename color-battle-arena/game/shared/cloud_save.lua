-- shared/cloud_save.lua
-- 云存档（2026-09-22 用户拍板"第一步"：不做注册页面，身份沿用金币系统的 device_id / gc_<playerId>）。
-- 把本地所有存档文件（各游戏关卡进度、道具/体力、设置、CardDoz 统计…）打成一份快照推到
-- /api/progress；启动时拉回来合并。合并铁律（金币被清零的教训）：**只往高合、绝不抹低**——
--   * 本地没有这个文件（全新安装/重装）→ 直接用云端的；
--   * 本地有：*_progress 取 level 较大者（难度用本地），其它文件一律以本地为准。
-- 快照里每个文件存成 Lua 字面量字符串（不用 JSON 存表：JSON 会把数字键变成字符串键，
-- scenes_done[12] 这类存档解回来就对不上）。金币不在此列（coin.lua 自己同步）。
-- 推送时机：game_progress.save 后（防抖 1.5s）、回大厅时、拉取合并后本地有更高进度时。
local coin = require("shared.coin")

local M = {}

M._dirty = false
M._timer = nil
M._pulled_for = nil     -- 已为哪个身份拉过（换绑 Game Center 后要再拉一次）

-- 需要上云的存档文件：{ 目录, 文件名 }（与各处 sys.get_save_file 调用一一对应）
local PROGRESS_KEYS = {
    "flashlinez", "pupdoku", "nutssort", "arrow", "watersort", "dicewars", "picfitz", "tapix",
    "spinbound", "wordoz", "cattrail", "triopop", "carddoz", "ballsort", "hexmerge", "mahjong", "clashdoz", "ponon",
    "wordoz_five", "wordoz_hive", "wordoz_square", "wordoz_sudoku", "wordoz_quads",
}
local FILES = {
    { "playdoz", "prize_seen" },   -- 上周领奖提示已弹过的周（2026-10-01）
    { "playdoz", "last_played" },  -- 最后玩的游戏（通知续关，2026-10-02）
    { "flashlinez", "flashlinez_progress" }, { "flashlinez", "level_rewards" },
    { "flashlinez", "flashlinez_level_hint_done" }, { "flashlinez", "flgames_classic" },
    { "flashlinez", "flgames_levels" }, { "flashlinez", "flgames_data" },
    { "flashlinez", "items" },   -- 商店买的特殊球（2026-10-07）
    { "flashlinez", "scores" },  -- 本地最高 10 局（2026-10-07）
    { "pupdoku", "lives" }, { "pupdoku", "items_v2" }, { "pupdoku", "settings" },
    { "cattrail", "hearts" }, { "cattrail", "lives" }, { "cattrail", "settings" },
    { "arrow", "scenes_done" }, { "tapix", "scenes_done" }, { "tapix", "settings" },
    { "carddoz", "stats" }, { "nutssort", "settings" }, { "watersort", "settings" }, { "ballsort", "settings" }, { "triopop", "settings" },
    { "mahjong", "settings" }, { "mahjong", "items" }, { "mahjong", "state" },   -- state = 本关中途局面（2026-10-10 第 15 款）
    { "ponon", "settings" }, { "ponon", "stats" },   -- 第 17 款 BEAT THE LINE（2026-11-08）：声音开关 / 每关星级+最佳用时
    { "clashdoz", "settings" }, { "clashdoz", "scores" }, { "clashdoz", "profile" },   -- 第 16 款（2026-10-26）：声音开关 / 本地最高 10 局 / 技能点+卡库（2026-10-27）
    { "playdoz", "review" }, { "playdoz", "spinbound_settings" },
    { "playdoz", "wordoz_five_state" }, { "playdoz", "wordoz_hive_state" }, { "playdoz", "wordoz_square_state" },
    { "playdoz", "wordoz_sudoku_state" }, { "playdoz", "wordoz_quads_state" },
}
for _, k in ipairs(PROGRESS_KEYS) do FILES[#FILES + 1] = { "PlayDoz", k .. "_progress" } end

local function is_web()
    local info = sys.get_sys_info()
    return info.system_name == "HTML5"
end

-- ---------------------------------------------------------------- Lua 字面量序列化（保留键类型）
local function serialize(v, depth)
    depth = depth or 0
    if depth > 12 then return "nil" end
    local t = type(v)
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "0" end
        return string.format("%.17g", v)
    elseif t == "string" then
        return string.format("%q", v)
    elseif t == "boolean" then
        return v and "true" or "false"
    elseif t == "table" then
        local parts = {}
        for k, x in pairs(v) do
            local kt = type(k)
            if (kt == "string" or kt == "number" or kt == "boolean") then
                local sx = serialize(x, depth + 1)
                if sx ~= "nil" then
                    parts[#parts + 1] = "[" .. serialize(k, depth + 1) .. "]=" .. sx
                end
            end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "nil"
end

local function deserialize(str)
    if type(str) ~= "string" or #str == 0 then return nil end
    local fn = loadstring("return " .. str)
    if not fn then return nil end
    setfenv(fn, {})
    local ok, v = pcall(fn)
    if ok and type(v) == "table" then return v end
    return nil
end

-- ---------------------------------------------------------------- 快照
local function path_of(f) return require("shared.save_file").path(f[1], f[2]) end   -- 云端 key 仍用 f[1] 原名（file_key）
local function file_key(f) return f[1] .. "/" .. f[2] end

local function load_file(f)
    local ok, data = pcall(sys.load, path_of(f))
    if ok and type(data) == "table" and next(data) ~= nil then return data end
    return nil
end

function M.snapshot()
    local files = {}
    local n = 0
    for _, f in ipairs(FILES) do
        local data = load_file(f)
        if data then files[file_key(f)] = serialize(data); n = n + 1 end
    end
    return { v = 1, files = files, saved_at = os.time() }, n
end

-- ---------------------------------------------------------------- 推
local function app_version()
    return sys.get_config_string("project.version", "")
end

function M.push_now()
    if is_web() then return end
    local id = coin.get_device_id()
    if not id or id == "" then return end
    local snap, n = M.snapshot()
    if n == 0 then return end
    local body = json.encode({ device_id = id, app_version = app_version(), data = snap })
    local headers = { ["Content-Type"] = "application/json" }
    http.request(coin._api_url .. "/api/progress", "POST", function(self, _, response)
        if response.status ~= 200 then
            print("[cloud_save] push failed: " .. tostring(response.status))
        end
    end, headers, body)
    M._dirty = false
end

-- 有改动：防抖 1.5s 后推一次
function M.mark_dirty()
    if is_web() then return end
    M._dirty = true
    if M._timer then return end
    M._timer = timer.delay(1.5, false, function()
        M._timer = nil
        if M._dirty then M.push_now() end
    end)
end

-- ---------------------------------------------------------------- 拉 + 合并
local function merge_one(f, remote)
    local path = path_of(f)
    local localdata = load_file(f)
    if not localdata then
        pcall(sys.save, path, remote)
        return "restored"
    end
    if string.find(f[2], "_progress$") then
        local rl, ll = tonumber(remote.level) or 0, tonumber(localdata.level) or 0
        if rl > ll then
            localdata.level = rl
            pcall(sys.save, path, localdata)
            return "raised"
        elseif ll > rl then
            return "local_ahead"
        end
    end
    return "kept"
end

function M.pull(callback)
    if is_web() then if callback then callback(false) end return end
    local id = coin.get_device_id()
    if not id or id == "" then if callback then callback(false) end return end
    M._pulled_for = id
    local url = coin._api_url .. "/api/progress?device_id=" .. id
    http.request(url, "GET", function(self, _, response)
        if response.status ~= 200 then
            print("[cloud_save] pull failed: " .. tostring(response.status))
            if callback then callback(false) end
            return
        end
        local ok, body = pcall(json.decode, response.response)
        if not ok or type(body) ~= "table" then if callback then callback(false) end return end
        if not body.found or type(body.data) ~= "table" or type(body.data.files) ~= "table" then
            -- 云端还没有：把本地推上去
            M.push_now()
            if callback then callback(true) end
            return
        end
        local restored, raised, local_ahead = 0, 0, 0
        for _, f in ipairs(FILES) do
            local str = body.data.files[file_key(f)]
            if str then
                local remote = deserialize(str)
                if remote then
                    local r = merge_one(f, remote)
                    if r == "restored" then restored = restored + 1
                    elseif r == "raised" then raised = raised + 1
                    elseif r == "local_ahead" then local_ahead = local_ahead + 1 end
                end
            end
        end
        print(string.format("[cloud_save] pulled: restored %d, raised %d, local ahead %d", restored, raised, local_ahead))
        -- 本地有比云端更新的（或云端缺文件）：推一份上去
        M.push_now()
        if callback then callback(true) end
    end)
end

-- 身份变化（Game Center 绑定完成）：用新身份再拉一次
function M.on_identity_changed()
    if is_web() then return end
    if M._pulled_for ~= coin.get_device_id() then M.pull() end
end

function M.init()
    if is_web() then return end
    coin.on_identity_changed = M.on_identity_changed   -- Game Center 绑定完成后的钩子（见 coin.bind_account）
    M.pull()
end

return M
