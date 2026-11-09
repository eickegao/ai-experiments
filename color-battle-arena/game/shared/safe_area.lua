-- shared/safe_area.lua
-- 全局安全区单例，启动时计算一次，所有游戏共用

local M = {}

-- 设计尺寸
M.DESIGN_W = 1080
M.DESIGN_H = 1920

-- 安全区偏移（设计坐标系下的像素值）
M.top = 0
M.bottom = 0

-- 是否已初始化
M.initialized = false

function M.init()
    if M.initialized then return end

    local sysinfo = sys.get_sys_info()
    if sysinfo.system_name ~= "iPhone OS" then
        M.initialized = true
        return
    end

    -- 窗口尺寸未就绪时不标记 initialized，让调用方下一帧重试
    -- （否则首个调用者拿到 0 会把 top 永久毒化成 0）
    local win_w, win_h = window.get_size()
    if win_w == 0 or win_h == 0 then return end
    M.initialized = true

    local ratio = win_h / win_w
    if ratio <= 2.0 then
        return  -- 传统 iPhone (SE 等)，无刘海
    end

    local scale = M.DESIGN_H / win_h
    if ratio > 2.15 then
        -- 灵动岛设备 (iPhone 14 Pro, 15, 16 等)，safe area top ≈ 59pt
        M.top = 59 * 3 * scale
        M.bottom = 34 * 3 * scale
    else
        -- 刘海设备 (iPhone X ~ 13)，safe area top ≈ 47pt
        M.top = 47 * 3 * scale
        M.bottom = 34 * 3 * scale
    end

    print("Safe area initialized: top=" .. M.top .. " bottom=" .. M.bottom)
end

return M
