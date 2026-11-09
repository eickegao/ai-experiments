-- shared/scores.lua — 单游戏分数榜客户端接口（2026-10-07，Flash Linez 经典模式先用）
--   submit(game, score, cleared, blob, cb)   每局结束上报一行（blob = 回放录制，可 nil）；cb(d|nil)，
--       d = { recorded, share_id, rank_week, entries_week, rank_all, entries_all, best_week, best_all, is_best_week, is_best_all }（名次超过前 10000 为 nil）
--   fetch_board(game, period, cb)      period = "week" | "all"；cb(d|nil)，d = { entries, top = {{rank, nickname, avatar, country, score, cleared, share_id, mine, date}}, me = {rank|nil, score|nil} }
-- 榜是"分数条目"的榜（2026-10-08 用户定案）：一局一条，一个人可多条，前 10000 条进榜；本周榜按周轮换，历史榜不清。
-- 网页版没有账号体系：一律回 nil。
local coin = require("shared.coin")
local M = {}

local function is_web() return sys.get_sys_info().system_name == "HTML5" end

local function parse(r)
    local ok, d = false, nil
    if r.status == 200 then ok, d = pcall(json.decode, r.response) end
    return (ok and type(d) == "table" and d.ok) and d or nil
end

function M.submit(game, score, cleared, blob, cb)
    if is_web() then if cb then cb(nil) end return end
    local body = json.encode({ device_id = coin.get_device_id(), game = game, score = math.floor(score or 0), cleared = math.floor(cleared or 0), blob = blob })
    local ok = pcall(http.request, coin._api_url .. "/api/score", "POST", function(_, _, r)
        if cb then cb(parse(r)) end
    end, { ["Content-Type"] = "application/json" }, body, { timeout = 10 })
    if not ok and cb then cb(nil) end
end

function M.fetch_board(game, period, cb)
    if is_web() then cb(nil) return end
    local url = coin._api_url .. "/api/score/board?device_id=" .. coin.get_device_id() .. "&game=" .. game .. "&period=" .. (period or "all")
    local ok = pcall(http.request, url, "GET", function(_, _, r) cb(parse(r)) end, {}, nil, { timeout = 10 })
    if not ok then cb(nil) end
end

return M
