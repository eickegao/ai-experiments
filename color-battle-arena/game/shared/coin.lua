-- shared/coin.lua
-- Global coin system: local cache + cloud sync
-- Usage:
--   local coin = require("shared.coin")
--   coin.init()             -- call once at startup
--   coin.get_balance()      -- returns current coins
--   coin.add(amount, reason)    -- add coins (syncs to cloud)；游戏奖励不要用它，走 shared/earn.lua（2026-10-01）
--   coin.add_local(n) / coin.set_balance(n)   -- earn.lua 用：本地预加 / 服务端余额覆盖
--   coin.deduct(amount, reason) -- deduct coins (syncs to cloud)

local M = {}

-- Local state
M._balance = 0
M._device_id = ""
M._initialized = false
M._api_url = "https://playdoz-api.eickegao.workers.dev"

-- Save file path
local SAVE_FILE = "playdoz_coins"

-- 网页版（HTML5）：无账号体系，金币只存内存——不落本地存档、不调云端，刷新即归零
-- （用户 2026-09-02 定案；以后接登录后再放开）
M._web_session = false

local function is_web()
    local info = sys.get_sys_info()
    return info.system_name == "HTML5"
end

----------------------------------------------------------------------
-- DEVICE ID
----------------------------------------------------------------------
local function generate_device_id()
    local sysinfo = sys.get_sys_info()
    -- Use platform device identifier if available (persists across reinstall on Android)
    local platform_id = sysinfo.device_identifier or ""
    if platform_id ~= "" then
        return "pdz_" .. platform_id
    end
    -- Fallback: generate random ID (web or platforms without device_identifier)
    local seed = (sysinfo.device_model or "") .. (sysinfo.system_name or "") ..
                 tostring(os.time()) .. tostring(math.random(100000, 999999))
    local hash = 0
    for i = 1, #seed do
        hash = (hash * 31 + string.byte(seed, i)) % 2147483647
    end
    return "pdz_" .. string.format("%x", hash) .. string.format("%x", math.random(0, 0xFFFFFF))
end

----------------------------------------------------------------------
-- LOCAL PERSISTENCE
----------------------------------------------------------------------
local function save_local()
    if M._web_session then return end
    -- authoritative：已完成一次"服务端权威"对账的标记（2026-10-01，见 cloud_reconcile）
    sys.save(sys.get_save_file("playdoz", SAVE_FILE), { device_id = M._device_id, balance = M._balance, authoritative = M._authoritative or nil })
end

local function load_local()
    if M._web_session then return false end
    local path = sys.get_save_file("playdoz", SAVE_FILE)
    local data = sys.load(path)
    if data and data.device_id then
        M._device_id = data.device_id
        M._balance = data.balance or 0
        M._authoritative = data.authoritative == true
        return true
    end
    return false
end

----------------------------------------------------------------------
-- CLOUD SYNC (fire and forget)
----------------------------------------------------------------------
local function cloud_get_balance(callback)
    if M._web_session then if callback then callback(M._balance) end return end
    local url = M._api_url .. "/api/coins?device_id=" .. M._device_id
    http.request(url, "GET", function(self, id, response)
        if response.status == 200 then
            local ok, data = pcall(json.decode, response.response)
            if ok and data and type(data.coins) == "number" then
                -- 全新安装恢复：服务端余额就是真相（2026-10-01 服务端权威）
                M._balance = data.coins
                M._authoritative = true
                save_local()
                if callback then callback(M._balance) end
            end
        end
    end)
end

local function cloud_add(amount, reason, on_done)
    if M._web_session then return end
    local url = M._api_url .. "/api/coins/add"
    local body = json.encode({
        device_id = M._device_id,
        amount = amount,
        reason = reason,
    })
    local headers = { ["Content-Type"] = "application/json" }
    -- 回包不覆盖本地（余额由 /api/earn 回包与启动对账维护）
    http.request(url, "POST", function(self, id, response)
        if on_done then on_done(response.status == 200) end
    end, headers, body)
end

local function cloud_deduct(amount, reason)
    if M._web_session then return end
    local url = M._api_url .. "/api/coins/deduct"
    local body = json.encode({
        device_id = M._device_id,
        amount = amount,
        reason = reason,
    })
    local headers = { ["Content-Type"] = "application/json" }
    http.request(url, "POST", function(self, id, response) end, headers, body)
end

-- 启动对账（2026-10-01 改服务端权威，见 spec docs/superpowers/specs/2026-10-01-checkin-ranking-design.md 3.1）：
-- 游戏奖励都在服务端发（shared/earn.lua → /api/earn），本地只是缓存。
-- 升级后首次启动：老存档本地可能高于服务端（旧"本地权威"时期的差额），推一次差额后打标记；
-- 之后一律服务端覆盖本地（花费仍本地先扣 + deduct 同步，扣款请求丢失会在下次启动被服务端纠正）。
local function cloud_reconcile()
    if M._web_session then return end
    local url = M._api_url .. "/api/coins?device_id=" .. M._device_id
    http.request(url, "GET", function(self, id, response)
        if response.status ~= 200 then return end
        local ok, data = pcall(json.decode, response.response)
        if not (ok and data and type(data.coins) == "number") then return end
        if not M._authoritative then
            -- 差额推成功（200）才打标记；失败下次启动再推，避免差额丢失（审查 I2a）
            if M._balance > data.coins then
                cloud_add(M._balance - data.coins, "reconcile_legacy", function(ok)
                    if ok then M._authoritative = true; save_local() end
                end)
            else
                M._authoritative = true
                save_local()
            end
        else
            M._balance = data.coins
            save_local()
        end
    end)
end

----------------------------------------------------------------------
-- DEVICE ID MIGRATION (for Game Center / account binding)
----------------------------------------------------------------------
local function migrate_device_id(old_id, new_id, callback)
    if M._web_session then if callback then callback(M._balance) end return end
    -- Transfer coins from old device_id to new one on the server
    local url = M._api_url .. "/api/coins/migrate"
    local body = json.encode({ old_device_id = old_id, new_device_id = new_id })
    local headers = { ["Content-Type"] = "application/json" }
    http.request(url, "POST", function(self, id, response)
        if response.status == 200 then
            local ok, data = pcall(json.decode, response.response)
            if ok and data and type(data.coins) == "number" then
                -- 本地余额是权威：迁移回包只能上调、绝不能抹低
                -- （2026-08-17 用户抓虫：Game Center 首次绑定后余额 1068→0——
                -- 新 gc_ ID 在服务端是空账户，回包 coins=0 把本地存档冲成 0）
                if data.coins > M._balance then
                    M._balance = data.coins
                end
                save_local()
            end
        end
        if callback then callback() end
    end, headers, body)
end

----------------------------------------------------------------------
-- PUBLIC API
----------------------------------------------------------------------

function M.init()
    if M._initialized then return end
    M._initialized = true

    math.randomseed(os.time())

    if is_web() then
        M._web_session = true
        M._device_id = "web_session"
        M._balance = 0
        print("Coin system initialized (web session only, no persistence)")
        return
    end

    -- Load local data or create new device ID
    local had_save = load_local()
    if not had_save then
        M._device_id = generate_device_id()
        M._balance = 0
        save_local()
        -- 全新安装：从云端恢复（重装找回余额）
        cloud_get_balance()
    else
        -- 有本地档：本地权威，对账推平云端
        cloud_reconcile()
    end

    print("Coin system initialized: device=" .. M._device_id .. " balance=" .. M._balance)
end

-- Called when Game Center (iOS) or other auth provides a persistent user ID
-- Migrates coins from temporary device_id to persistent ID
function M.bind_account(persistent_id)
    if M._web_session then return end
    local new_id = "gc_" .. persistent_id
    if M._device_id == new_id then return end  -- already bound

    local old_id = M._device_id
    M._device_id = new_id
    save_local()

    -- Migrate coins on server from old ID to new ID
    migrate_device_id(old_id, new_id, function()
        cloud_reconcile()
        -- 云存档跟着新身份再拉一次（服务端 migrate 已把老身份的快照复制到新身份）。
        -- 用回调而不是 require：bob 会把 require 字符串当静态依赖，coin↔cloud_save 判循环
        if M.on_identity_changed then pcall(M.on_identity_changed) end
    end)

    print("Coin system bound to account: " .. new_id)
end

function M.get_balance()
    return M._balance
end

function M.get_device_id()
    return M._device_id
end

function M.add(amount, reason)
    if amount <= 0 then return end
    reason = reason or "unknown"
    M._balance = M._balance + amount
    save_local()
    cloud_add(amount, reason)
end

function M.deduct(amount, reason)
    if amount <= 0 then return false end
    if M._balance < amount then return false end
    reason = reason or "unknown"
    M._balance = M._balance - amount
    save_local()
    cloud_deduct(amount, reason)
    return true
end

--- 是否已完成一次服务端权威对账（false = 老存档差额尚未推上去，earn 回包只能加差值，见 shared/earn.lua）
function M.is_authoritative()
    return M._authoritative == true
end

--- 只改本地缓存（earn.report 的预估金额），不发请求；回包后由 set_balance 校正
function M.add_local(amount)
    if amount <= 0 then return end
    M._balance = M._balance + amount
    save_local()
end

--- 服务端余额覆盖本地（/api/earn、/api/me 回包）
function M.set_balance(n)
    if type(n) ~= "number" then return end
    M._balance = n
    save_local()
end

function M.sync(callback)
    cloud_get_balance(callback)
end

function M.set_api_url(url)
    M._api_url = url
end

return M
