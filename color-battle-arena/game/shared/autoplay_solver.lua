-- shared/autoplay_solver.lua
-- 商店预览录像用的小型解法器（2026-10-22）：Water Sort / Nuts Sort 共用 games.nutssort.nutssort_logic 的局面模型，
-- DFS + 规范键去重找一条通关步序，自动演示按它像玩家一样点选再倒/移。只在 debug 引擎 + 深链 autoplay=1 时被调用。
local M = {}

--- logic = nutssort_logic；level = 开局局面；max_states = 搜索上限（默认 20 万）。返回 { {from=,to=}, ... } 或 nil
function M.solve(logic, level, max_states)
    max_states = max_states or 200000
    local seen, n, path = {}, 0, {}
    local function dfs(lv)
        if logic.is_won(lv) then return true end
        local key = logic.canonical_key(lv)
        if seen[key] then return false end
        seen[key] = true
        n = n + 1
        if n > max_states then return false end
        local moves = logic.legal_moves(lv)
        -- 先试倒进非空管（同色叠上去），再试倒进空管：演示看起来更像人在玩，也更快收敛
        table.sort(moves, function(a, b)
            local ea, eb = #lv.bolts[a.to] == 0, #lv.bolts[b.to] == 0
            if ea ~= eb then return eb end
            if a.from ~= b.from then return a.from < b.from end
            return a.to < b.to
        end)
        for _, m in ipairs(moves) do
            local nxt = logic.clone(lv)
            logic.move(nxt, m.from, m.to)
            path[#path + 1] = m
            if dfs(nxt) then return true end
            path[#path] = nil
        end
        return false
    end
    if dfs(logic.clone(level)) then return path end
    return nil
end

return M
