-- games/clashdoz/cd_scores.lua — CLASHDOZ 本地最高 10 局（照 games/flashlinez/flscores.lua）。
-- 分数 = 终局自己的格子数（0..1024），cleared 字段存名次（1..4）。存档 clashdoz/scores（进 shared/cloud_save FILES）。
local M = {}
M.KEEP = 10
local list = nil
local function path() return sys.get_save_file("clashdoz", "scores") end
local function save() sys.save(path(), { v = 1, list = list }) end
local function load()
    if list then return list end
    local d = sys.load(path())
    list = (d and d.list) or {}
    return list
end

--- 按分数降序的 { {score, cleared, date}, … }（最多 KEEP 条）
function M.list() return load() end
function M.best() local l = load(); return l[1] and l[1].score or 0 end

--- 记一局：返回 { is_best = 是否破历史最高, local_rank = 本局在本地榜的名次 | nil（没进前 10） }；零分不记
function M.record(score, place, date)
    score = tonumber(score) or 0
    if score <= 0 then return nil end
    local l = load()
    local is_best = score > M.best()
    local entry = { score = score, cleared = tonumber(place) or 0, date = date or os.date("%Y-%m-%d") }
    local pos = #l + 1
    for i, e in ipairs(l) do if score > e.score then pos = i; break end end
    table.insert(l, pos, entry)
    while #l > M.KEEP do table.remove(l) end
    save()
    return { is_best = is_best, local_rank = (pos <= M.KEEP) and pos or nil }
end

return M
