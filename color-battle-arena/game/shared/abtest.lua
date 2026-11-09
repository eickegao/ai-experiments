-- shared/abtest.lua
-- GameAnalytics 薄壳：A/B Remote Config 读取 + 自定义事件上报的唯一对接面。
-- 游戏代码不得直接调用 gameanalytics.*。
-- key 未配置或扩展缺失（本地桌面构建等）时全部降级为空操作。

local M = {}

M._enabled = nil -- 惰性计算，nil = 未判定

local PLATFORM_KEY = {
    ["iPhone OS"] = "gameanalytics.game_key_ios",
    ["Android"] = "gameanalytics.game_key_android",
    ["HTML5"] = "gameanalytics.game_key_html5",
    ["Darwin"] = "gameanalytics.game_key_osx",
    ["Windows"] = "gameanalytics.game_key_windows",
    ["Linux"] = "gameanalytics.game_key_linux",
}

function M.enabled()
    if M._enabled == nil then
        local cfg = PLATFORM_KEY[sys.get_sys_info().system_name]
        M._enabled = (gameanalytics ~= nil)
            and cfg ~= nil
            and sys.get_config_string(cfg, "") ~= ""
    end
    return M._enabled
end

--- 入口 init 时调用一次（幂等）。SDK 为自动初始化模式，这里只做启用判定与日志。
function M.init()
    if M.enabled() then
        print("abtest: GameAnalytics enabled")
    else
        print("abtest: GameAnalytics disabled (no key or extension missing)")
    end
end

--- 读 A/B / Remote Config 开关；未启用/未就绪/无该 key 时返回 default。
--- 规范：default 必须等于对照组行为。
function M.get(key, default)
    if not M.enabled() then return default end
    local ok, v = pcall(gameanalytics.getRemoteConfigsValueAsString,
        { key = key, defaultValue = default })
    if ok and v ~= nil and v ~= "" then return v end
    return default
end

--- 发自定义 design 事件；value 可选（number）。
function M.design(event_id, value)
    if not M.enabled() then return end
    local opts = { eventId = event_id }
    if value ~= nil then opts.value = value end
    pcall(gameanalytics.addDesignEvent, opts)
end

return M
