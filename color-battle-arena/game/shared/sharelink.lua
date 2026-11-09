-- shared/sharelink.lua
-- 自包含关卡分享链接的二进制外壳（spec: docs/superpowers/specs/2026-09-23-share-link-replay-design.md §2.1）
-- 外壳: shell_ver(1) game_id(1) game_ver(1) flags(1) seed(4 BE) level_num(2) state_len(2) state
--       [moves_count(2) moves]（flags bit0）  checksum(1, 前面全部字节异或)
-- 兼容: 低版本链接高版本永远可开; shell_ver 高于本 App → "shell_too_new"。新字段只能加在 moves 之后、checksum 之前。
-- 编码 base64url（A-Za-z0-9-_ 无 padding）；LuaJIT/Defold 均无内置 base64，自写一份保证各平台一致。
local M = {}
local bxor = bit.bxor

M.SHELL_VER = 1
M.FLAG_REPLAY = 1
-- 游戏编号：只增不改
M.GAME_IDS = {
    nutssort = 1, watersort = 2, pupdoku = 3, cattrail = 4, triopop = 5, arrow = 6,
    tapix = 7, flashlinez = 8, dicewars = 9, carddoz = 10, wordoz = 11, ballsort = 12,
    hexmerge = 13,
}
-- 一个游戏有多个 slug 时链接用哪个（deeplink.SLUGS 是 slug→key，pairs 顺序不定）
M.PREFER_SLUG = { hexmerge = "hexa-merge" }
M.ID_TO_KEY = {}
for k, v in pairs(M.GAME_IDS) do M.ID_TO_KEY[v] = k end

-- ---------- base64url ----------
local ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local DEC = {}
for i = 1, 64 do DEC[ALPHA:byte(i)] = i - 1 end
local function ch(i) return ALPHA:sub(i + 1, i + 1) end

function M.b64encode(s)
    local out = {}
    for i = 1, #s, 3 do
        local a, b, c = s:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        out[#out + 1] = ch(math.floor(n / 262144) % 64) .. ch(math.floor(n / 4096) % 64)
        if b then out[#out + 1] = ch(math.floor(n / 64) % 64) end
        if c then out[#out + 1] = ch(n % 64) end
    end
    return table.concat(out)
end

function M.b64decode(s)
    if type(s) ~= "string" or #s % 4 == 1 then return nil end
    local out = {}
    for i = 1, #s, 4 do
        local v = {}
        for k = 0, 3 do
            local c = s:byte(i + k)
            if c then
                local d = DEC[c]
                if not d then return nil end
                v[#v + 1] = d
            end
        end
        local num = (v[1] or 0) * 262144 + (v[2] or 0) * 4096 + (v[3] or 0) * 64 + (v[4] or 0)
        out[#out + 1] = string.char(math.floor(num / 65536) % 256)
        if #v >= 3 then out[#out + 1] = string.char(math.floor(num / 256) % 256) end
        if #v >= 4 then out[#out + 1] = string.char(num % 256) end
    end
    return table.concat(out)
end

-- ---------- 位打包（MSB 先） ----------
local Writer = {}
Writer.__index = Writer
function M.bitwriter() return setmetatable({ parts = {}, cur = 0, nb = 0 }, Writer) end
function Writer:write(value, nbits)
    for i = nbits - 1, 0, -1 do
        self.cur = self.cur * 2 + (math.floor(value / 2 ^ i) % 2)
        self.nb = self.nb + 1
        if self.nb == 8 then
            self.parts[#self.parts + 1] = string.char(self.cur)
            self.cur, self.nb = 0, 0
        end
    end
end
function Writer:bytes()
    local tail = self.nb > 0 and string.char(self.cur * 2 ^ (8 - self.nb)) or ""
    return table.concat(self.parts) .. tail
end

local Reader = {}
Reader.__index = Reader
function M.bitreader(bytes) return setmetatable({ s = bytes, pos = 0 }, Reader) end
function Reader:read(nbits)
    if self.pos + nbits > #self.s * 8 then return nil end
    local v = 0
    for _ = 1, nbits do
        local byte = self.s:byte(math.floor(self.pos / 8) + 1)
        v = v * 2 + (math.floor(byte / 2 ^ (7 - self.pos % 8)) % 2)
        self.pos = self.pos + 1
    end
    return v
end

-- ---------- 外壳 ----------
local function u8(n) return string.char(n % 256) end
local function u16(n) return string.char(math.floor(n / 256) % 256, n % 256) end
local function u32(n)
    return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256,
        math.floor(n / 256) % 256, n % 256)
end
local function xor_all(s)
    local x = 0
    for i = 1, #s do x = bxor(x, s:byte(i)) end
    return x
end

--- p = { game=key, game_ver=n, seed=n, level_num=n, state=bytes, moves=bytes|nil, moves_count=n|nil }
function M.encode(p)
    local gid = assert(M.GAME_IDS[p.game], "unknown game " .. tostring(p.game))
    local flags = p.moves and M.FLAG_REPLAY or 0
    local body = u8(M.SHELL_VER) .. u8(gid) .. u8(p.game_ver or 1) .. u8(flags)
        .. u32(p.seed or 0) .. u16(p.level_num or 0) .. u16(#p.state) .. p.state
    if p.moves then body = body .. u16(p.moves_count or 0) .. p.moves end
    return M.b64encode(body .. u8(xor_all(body)))
end

--- → { game, game_ver, flags, seed, level_num, state, moves_count|nil, moves|nil } | nil, err
--- err ∈ bad_base64 / truncated / bad_checksum / shell_too_new / unknown_game
function M.decode(blob)
    local raw = M.b64decode(blob)
    if not raw then return nil, "bad_base64" end
    if #raw < 13 then return nil, "truncated" end
    local body = raw:sub(1, #raw - 1)
    if xor_all(body) ~= raw:byte(#raw) then return nil, "bad_checksum" end
    if raw:byte(1) > M.SHELL_VER then return nil, "shell_too_new" end
    local game = M.ID_TO_KEY[raw:byte(2)]
    if not game then return nil, "unknown_game" end
    local t = { game = game, game_ver = raw:byte(3), flags = raw:byte(4) }
    t.seed = raw:byte(5) * 16777216 + raw:byte(6) * 65536 + raw:byte(7) * 256 + raw:byte(8)
    t.level_num = raw:byte(9) * 256 + raw:byte(10)
    local slen = raw:byte(11) * 256 + raw:byte(12)
    local pos = 13
    if #body < pos + slen - 1 then return nil, "truncated" end
    t.state = body:sub(pos, pos + slen - 1)
    pos = pos + slen
    if bit.band(t.flags, M.FLAG_REPLAY) ~= 0 then
        if #body < pos + 1 then return nil, "truncated" end
        t.moves_count = body:byte(pos) * 256 + body:byte(pos + 1)
        t.moves = body:sub(pos + 2)
    end
    return t
end

local function slug_of(game_key)
    local deeplink = require("shared.deeplink")
    local slug = M.PREFER_SLUG[game_key] or game_key
    if not M.PREFER_SLUG[game_key] then
        for s, k in pairs(deeplink.SLUGS) do if k == game_key then slug = s end end
    end
    return slug
end

--- ref = 分享者短哈希（shared/referral.lua），可空
function M.build_url(game_key, blob, ref)
    -- /games/<slug> 网站有页面（没装 App 的人在网页玩）且在 AASA/Android 清单里；/p/ 只作短链（网站 _redirects 转过去）
    local url = "https://playdoz.com/games/" .. slug_of(game_key) .. "?d=" .. blob
    if ref and #ref > 0 then url = url .. "&r=" .. ref end
    return url
end

--- 短链（2026-10-07）：blob 存服务端，链接只带 8 位 id。目前只有 Flash Linez 用（长局）；其他游戏几十步直接走 build_url
function M.build_short_url(game_key, id, ref)
    local url = "https://playdoz.com/games/" .. slug_of(game_key) .. "?s=" .. id
    if ref and #ref > 0 then url = url .. "&r=" .. ref end
    return url
end

--- 上传 blob 换短链：cb(url | nil, reason)。没网/被限流/服务端出错都回 nil，调用方提示"分享需要联网"
function M.publish(game_key, blob, ref, cb)
    local coin = require("shared.coin")
    local body = json.encode({ device_id = coin.get_device_id(), game = game_key, blob = blob })
    local ok = pcall(http.request, coin._api_url .. "/api/share", "POST", function(_, _, r)
        local parsed, d = false, nil
        if r.status == 200 then parsed, d = pcall(json.decode, r.response) end
        if parsed and type(d) == "table" and d.ok and type(d.id) == "string" then
            cb(M.build_short_url(game_key, d.id, ref))
        else
            cb(nil, (parsed and d and d.reason) or ("http_" .. tostring(r.status)))
        end
    end, { ["Content-Type"] = "application/json" }, body, { timeout = 10 })
    if not ok then cb(nil, "request_failed") end
end

--- 短链取回：cb(blob | nil, reason)
function M.fetch(id, cb)
    local coin = require("shared.coin")
    local ok = pcall(http.request, coin._api_url .. "/api/share/" .. id, "GET", function(_, _, r)
        local parsed, d = false, nil
        if r.status == 200 then parsed, d = pcall(json.decode, r.response) end
        if parsed and type(d) == "table" and d.ok and type(d.blob) == "string" then cb(d.blob) else cb(nil, (parsed and d and d.reason) or ("http_" .. tostring(r.status))) end
    end, {}, nil, { timeout = 10 })
    if not ok then cb(nil, "request_failed") end
end

return M
