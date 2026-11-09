-- shared/replay.lua
-- 与游戏无关的逐步回放驱动：apply(move, done) 执行一步，游戏在动画结束时 done(true)，
-- 驱动隔 gap 秒推进下一步；apply 返回 false 或 done(false) → on_end("failed", idx)；
-- 全部播完 → on_end("finished")。stop() 之后迟到的 done 一律忽略。只有一个模块级实例。
local M = {}
local cur = nil   -- { moves, apply, opts, i, done_idx }

local function default_delay(sec, fn)
    if timer and timer.delay then timer.delay(sec, false, fn) else fn() end
end

local function finish(c, why, idx)
    if cur ~= c then return end
    cur = nil
    if c.opts.on_end then c.opts.on_end(why, idx) end
end

local function step(c)
    if cur ~= c then return end
    c.i = c.i + 1
    if c.i > #c.moves then return finish(c, "finished") end
    local idx = c.i
    local function done(ok)
        if cur ~= c or c.done_idx >= idx then return end
        c.done_idx = idx
        if ok == false then return finish(c, "failed", idx) end
        c.opts.delay(c.opts.gap, function() step(c) end)
    end
    if c.apply(c.moves[idx], done) == false then
        finish(c, "failed", idx)
    end
end

function M.start(moves, apply, opts)
    M.stop()
    opts = opts or {}
    opts.gap = opts.gap or 0.35
    opts.delay = opts.delay or default_delay
    cur = { moves = moves, apply = apply, opts = opts, i = 0, done_idx = 0 }
    step(cur)
end

function M.stop() cur = nil end
function M.is_playing() return cur ~= nil end
function M.progress()
    if not cur then return 0, 0 end
    return cur.i, #cur.moves
end

return M
