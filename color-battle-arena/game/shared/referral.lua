-- shared/referral.lua
-- 分享者短哈希（用户 2026-09-23：链接先带上分享者标识 r=<sid>，点开时知道是谁分享的；
-- 上报/发奖以后再做，见 docs/superpowers/specs/2026-09-23-share-referral-design.md）。
-- sid = 身份字符串（coin 的 device_id / gc_<playerId>）做两轮 FNV-1a 32 位 → 8 字节 → base64url 前 12 位。
-- 纯 Lua 实现，LuaJIT 单测与各平台结果一致；不可逆推出身份。
local M = {}
local bxor = bit.bxor

local function fnv1a32(s, basis)
    local h = basis
    for i = 1, #s do
        h = bxor(h, s:byte(i))
        -- h * 16777619 mod 2^32，拆成两段避免超出 2^53
        local lo = h % 65536
        local hi = math.floor(h / 65536)
        h = (lo * 16777619 + ((hi * 16777619) % 65536) * 65536) % 4294967296
    end
    return h
end

local function u32be(n)
    return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
end

--- 身份字符串 → 12 位 base64url；空/nil → nil
function M.sid_of(identity)
    if type(identity) ~= "string" or #identity == 0 then return nil end
    -- 网页版没有账号，coin 身份是固定的 "web_session"，所有网页用户会算出同一个值：不当分享者
    if identity == "web_session" then return nil end
    local sharelink = require("shared.sharelink")
    local h1 = fnv1a32(identity, 2166136261)
    local h2 = fnv1a32(identity .. "#playdoz", 0x811C9DC5 + 0x1F3D)
    return sharelink.b64encode(u32be(h1) .. u32be(h2) .. u32be(bxor(h1, h2))):sub(1, 12)
end

--- 当前玩家的分享者标识（coin 身份未就绪时 nil）
function M.sid()
    local ok, coin = pcall(require, "shared.coin")
    if not ok or not coin then return nil end
    return M.sid_of(coin._device_id)
end

--- 上报分享链路事件（2026-09-25 用户："打开链接 / 开始挑战 / 通关三个事件在 hash 生成之后上报"）。
--- event ∈ open | start | clear；fields = { ref, blob, game, level_num, moves }；失败静默，不阻塞游戏
function M.report(event, fields)
    local ok, coin = pcall(require, "shared.coin")
    if not ok or not coin or not coin._api_url then return end
    local opener = coin._device_id
    if not opener or opener == "" then opener = "web" end
    if opener == "web_session" then opener = "web" end
    local body = {
        event = event,
        ref = fields.ref,
        opener = opener,
        challenge = fields.blob and M.sid_of(fields.blob) or nil,   -- 同一局面的所有打开归到一个短哈希下
        game = fields.game,
        level_num = fields.level_num,
        moves = fields.moves,
        app_version = sys.get_config_string("project.version", ""),
    }
    local payload = json.encode(body)   -- Defold 全局 json（cloud_save 同用）
    pcall(http.request, coin._api_url .. "/api/referral/event", "POST", function() end,
        { ["Content-Type"] = "application/json" }, payload)
end

return M
