-- shared/haptic.lua
-- 震动反馈薄壳：iOS 走 def_taptic_engine 扩展（依赖仅配在单机 game.project），
-- 扩展缺失（合集、Android、桌面冒烟）时全部空操作。
-- 游戏代码不得直接调用 taptic_engine.*。

local M = {}

M._supported = nil -- 惰性判定

local function supported()
    if M._supported == nil then
        M._supported = (taptic_engine ~= nil) and taptic_engine.isSupported()
    end
    return M._supported
end

--- 轻触反馈：球移动落定等常规操作
function M.tap()
    if supported() then
        taptic_engine.impact(taptic_engine.IMPACT_LIGHT)
    end
end

--- 成功反馈：单次正向事件
function M.success()
    if supported() then
        taptic_engine.notification(taptic_engine.NOTIFICATION_SUCCESS)
    end
end

--- 重击反馈：n 次重脉冲，70ms 间隔（Trio Pop! 三消爆炸用；中等脉冲用户嫌不明显）
function M.heavy(n)
    if not supported() then return end
    n = math.min(n or 1, 6)
    for i = 0, n - 1 do
        timer.delay(i * 0.07, false, function()
            taptic_engine.impact(taptic_engine.IMPACT_HEAVY)
        end)
    end
end

--- 连环反馈：消除 n 个球 = n 次中等脉冲，60ms 间隔（上限 10 次）
function M.burst(n)
    if not supported() then return end
    n = math.min(n or 1, 10)
    for i = 0, n - 1 do
        timer.delay(i * 0.06, false, function()
            taptic_engine.impact(taptic_engine.IMPACT_MEDIUM)
        end)
    end
end

return M
