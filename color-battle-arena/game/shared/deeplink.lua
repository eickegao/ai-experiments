-- shared/deeplink.lua
-- Universal Link / App Link（2026-09-22 用户拍板）：一个网站链接，装了 App 的人点开直接进 App 的对应游戏/关卡，
-- 没装的在网页玩。本模块只负责"链接 ↔ 游戏+关卡"的解析，收链接的原生部分在 extension-iac（main.script 注册监听）。
-- 支持的链接形态（合集 App 与 SoloGames 网页壳共用）：
--   https://playdoz.com/games/<slug>            → 进该游戏封面
--   https://playdoz.com/games/<slug>?level=57   → 直接开第 57 关
--   https://playdoz.com/p/<slug|key>/57         → 同上（短链，二维码用）
--   网页壳：index.html?game=<key>&level=57
--   https://playdoz.com/p/<slug>?d=<blob>       → 自包含局面/回放（shared/sharelink.lua），可加 &video=1
local M = {}

-- 网站 slug（lib/game-service.ts）→ 游戏 key（main.script game_proxies）
M.SLUGS = {
    ["flashlinez"] = "flashlinez", ["dice-wars"] = "dicewars", ["pupdoku"] = "pupdoku",
    ["water-sort"] = "watersort", ["ball-sort"] = "ballsort", ["hex-merge"] = "hexmerge", ["hexa-merge"] = "hexmerge", ["nuts-sort"] = "nutssort", ["arrow"] = "arrow",
    ["tapix"] = "tapix", ["cattrail"] = "cattrail", ["wordoz"] = "wordoz",
    ["trio-pop"] = "triopop", ["carddoz"] = "carddoz", ["picfitz"] = "picfitz",   -- 2026-10-06 上架
    ["mahjong"] = "mahjong",   -- 2026-10-10 第 15 款
    ["clashdoz"] = "clashdoz",   -- 2026-10-26 第 16 款
    ["beat-the-line"] = "ponon", ["ponon"] = "ponon",   -- 2026-11-08 第 17 款
}
local KEYS = {}
for _, k in pairs(M.SLUGS) do KEYS[k] = true end

-- 各游戏 collection 里的实例 id（<key>.collection 的 instances.id），缺省 = key
local INSTANCE = { dicewars = "game" }

function M.controller_url(key)
    return key .. ":/" .. (INSTANCE[key] or key) .. "#controller"
end

--- 解析链接 → { game = key|nil, level = n|nil, blob = str|nil, video = bool, ref = sid|nil }；不认识的链接返回 nil

-- 真机排错用：把收到的链接追加写到存档目录（release 包 print 被剥离，devicectl 拉目录能看到）
function M.log(line)
    pcall(function()
        local f = io.open(sys.get_save_file("playdoz", "deeplink.log"), "a")
        if f then f:write(os.date("%Y-%m-%d %H:%M:%S") .. " " .. tostring(line) .. "\n"); f:close() end
    end)
end
function M.parse(url)
    if type(url) ~= "string" then return nil end
    local path = url:match("^%a[%w+.%-]*://[^/?#]*(/[^?#]*)") or url:match("^(/[^?#]*)") or ""
    local query = url:match("%?([^#]*)") or ""
    local level = tonumber(query:match("^level=(%d+)") or query:match("&level=(%d+)"))
    -- 自包含分享 blob（spec 2026-09-23 share-link-replay）：base64url 字符集；与 level 互斥，带 d 时忽略 level
    local blob = query:match("^d=([%w%-_]+)&") or query:match("^d=([%w%-_]+)$")
        or query:match("&d=([%w%-_]+)&") or query:match("&d=([%w%-_]+)$")   -- 必须整段合法，否则视为无 d
    if blob then level = nil end
    -- 短链 s=<8 位 id>（2026-10-07，Flash Linez 长局录制存服务端）：main.script 先 GET /api/share/<id> 换成 blob 再开局；与 d 互斥
    local sid = query:match("^s=(%w%w%w%w%w%w%w%w)&") or query:match("^s=(%w%w%w%w%w%w%w%w)$")
        or query:match("&s=(%w%w%w%w%w%w%w%w)&") or query:match("&s=(%w%w%w%w%w%w%w%w)$")
    if blob then sid = nil end
    if sid then level = nil end
    -- 回放视频模式（HTML5 无人值守录屏用）：不显示横幅、不弹结算
    local video = (query:match("^video=1") or query:match("&video=1")) ~= nil
    local demo = (query:match("^demo=1") or query:match("&demo=1")) ~= nil   -- 测试用：按烘焙解法自动打一遍（ballsort）
    local autoplay = (query:match("^autoplay=1") or query:match("&autoplay=1")) ~= nil   -- 商店预览录像（2026-10-22，只 debug 引擎）：麻将/Water Sort/Nuts Sort 自动演示
    -- 结算页预览（2026-10-13，只在 debug 引擎生效，main.script 判）：result=win|fail → 开局后直接演结算页
    local result = query:match("^result=(%a+)") or query:match("&result=(%a+)")
    if result ~= "win" and result ~= "fail" then result = nil end
    -- 固定剧本直达 scenario=<key>（Dice Wars 三国，2026-10-23）：开局走 controller 的 start_game{scenario}
    local scenario = query:match("^scenario=([%w_]+)") or query:match("&scenario=([%w_]+)")
    -- reset=1（2026-11-03，网页测试用）：进游戏前把这款游戏的关卡进度清回第 1 关（网页存档在浏览器里，没别的办法拨回）
    local reset = (query:match("^reset=1") or query:match("&reset=1")) ~= nil
    -- 预览奖励倍数 mult=N（只配合 result 用，看两位数 +N 排版；正式局倍数由服务端下发）
    local mult = result and tonumber(query:match("^mult=(%d+)") or query:match("&mult=(%d+)")) or nil
    -- 分享者短哈希 r=<sid>（shared/referral.lua）：只解析、本地记日志，上报/发奖待做
    local ref = query:match("^r=([%w%-_]+)&") or query:match("^r=([%w%-_]+)$")
        or query:match("&r=([%w%-_]+)&") or query:match("&r=([%w%-_]+)$")
    local slug = path:match("^/games/([%w%-]+)")
    if not slug then
        local s, n = path:match("^/p/([%w%-]+)/?(%d*)")
        slug = s
        if n and #n > 0 then level = tonumber(n) end
    end
    if not slug then
        -- 网页壳 ?game=<key>
        slug = query:match("^game=([%w%-]+)") or query:match("&game=([%w%-]+)")
    end
    if not slug then
        -- 只带 level（网页壳 iframe 的 index.html?level=N）：游戏由壳本身决定
        if level or blob or sid or reset then return { game = nil, level = level, blob = blob, sid = sid, video = video, ref = ref, demo = demo, result = result, mult = mult, autoplay = autoplay, scenario = scenario, reset = reset } end
        return nil
    end
    local key = M.SLUGS[slug] or (KEYS[slug] and slug) or nil
    if not key then return nil end
    return { game = key, level = level, blob = blob, sid = sid, video = video, ref = ref, demo = demo, result = result, mult = mult, autoplay = autoplay, scenario = scenario, reset = reset }
end

--- HTML5：从当前页面 URL 读 game / level
function M.web_link()
    if not html5 then return nil end
    local ok, q = pcall(html5.run, "window.location.search || ''")
    if not ok or type(q) ~= "string" or #q == 0 then return nil end
    return M.parse("/x" .. q)
end

return M
