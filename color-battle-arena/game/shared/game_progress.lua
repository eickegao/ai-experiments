-- shared/game_progress.lua
-- Per-game persistence for level and difficulty.
-- Each game stores its data in its own file via sys.save / sys.load.

local earn = require("shared.earn")
local save_file = require("shared.save_file")

local M = {}

local DIFFICULTIES = { easy = true, medium = true, hard = true }
local DEFAULTS = { level = 1, difficulty = "medium" }

local function save_path(game_key)
    return save_file.path("PlayDoz", game_key .. "_progress")   -- 模拟器大小写撞目录时退回小写（shared/save_file）
end

local function merge_defaults(data)
    if type(data) ~= "table" then data = {} end
    if type(data.level) ~= "number" or data.level < 1 then
        data.level = DEFAULTS.level
    end
    if not DIFFICULTIES[data.difficulty] then
        data.difficulty = DEFAULTS.difficulty
    end
    return data
end

function M.load(game_key)
    local loaded = sys.load(save_path(game_key))
    return merge_defaults(loaded)
end

function M.save(game_key, data)
    sys.save(save_path(game_key), merge_defaults(data))
    -- 云存档：进度一变就（防抖）推一份快照上去（2026-09-22）
    pcall(function() require("shared.cloud_save").mark_dirty() end)
end

function M.get_level(game_key)
    return M.load(game_key).level
end

--- 过关推进进度。只接受"比已存进度正好多一关"（n == level + 1）：深链/分享链接打开的低关或高关过关
--- 都不会改写存档（2026-10-01 用户 Water Sort 54 关被测试深链 ?level=3 过关覆盖成 4）。
--- force = true 才允许任意改写（GAME OVER 清回第 1 关用）。
function M.set_level(game_key, n, force)
    local data = M.load(game_key)
    if not force and n ~= data.level + 1 then return end
    -- 每次推进关卡都奖励 5 金币（2026-08-12 用户定案：GAME OVER 清回第 1 关后
    -- 重爬也照发——失败代价是进度，金币收益保留，为将来"看广告复活保进度"留出
    -- 价值差；同关反复 set_level 不加币）
    if n > data.level then
        -- 2026-10-01：改服务端签名发币（参赛积分），本地先按预估金额加；演出层读 M.last_reward 显示
        M.last_reward = earn.report(game_key, "level_clear", n, 5)
        -- 全合集通关计数 → 应用内评分弹窗（iOS，见 shared/review.lua）
        pcall(function() require("shared.review").on_level_cleared() end)
    end
    data.level = n
    M.save(game_key, data)
    pcall(function() require("shared.notify").set_last_played(game_key, n) end)   -- 通知续关用（2026-10-02）
end

--- 进入某个游戏时记"最后玩的游戏"，通知续关用（2026-10-02）
function M.touch(game_key)
    pcall(function() require("shared.notify").set_last_played(game_key, M.get_level(game_key)) end)
end

function M.get_difficulty(game_key)
    return M.load(game_key).difficulty
end

function M.set_difficulty(game_key, d)
    local data = M.load(game_key)
    if DIFFICULTIES[d] then
        data.difficulty = d
        M.save(game_key, data)
    end
end

function M.reset(game_key)
    M.save(game_key, { level = DEFAULTS.level, difficulty = DEFAULTS.difficulty })
end

M.last_reward = 5   -- 最近一次过关的预估奖励（倍数日 10/15），演出文案用

return M
