-- shared/review.lua
-- 应用内评分弹窗（2026-09-07 用户定案：先只做 iOS）。依赖 defold/extension-review
-- （iOS 走 SKStoreReviewController，系统自己限频：每 App 每年最多弹 3 次，且不保证一定弹出）。
-- 策略：全合集累计通关数到 3 次首弹，之后每 20 次通关再试一次，两次之间至少隔 30 天。
-- 计数落盘 playdoz/review。Android/HTML5 一律不弹（Play In-App Review 以后再接）。
local M = {}

local FIRST_AT = 3
local EVERY = 20
local MIN_GAP_DAYS = 30

local function path() return sys.get_save_file("playdoz", "review") end

local function load()
    local ok, t = pcall(sys.load, path())
    if ok and type(t) == "table" then return t end
    return {}
end

local function is_ios()
    local info = sys.get_sys_info()
    return info.system_name == "iPhone OS"
end

-- 每次通关调用一次（各游戏的通关落档处）；内部决定是否真的请求弹窗
function M.on_level_cleared()
    local d = load()
    d.clears = (d.clears or 0) + 1
    local due = false
    if d.clears == FIRST_AT then
        due = true
    elseif d.clears > FIRST_AT and (d.clears - FIRST_AT) % EVERY == 0 then
        due = true
    end
    if due and d.last_at and (os.time() - d.last_at) < MIN_GAP_DAYS * 86400 then
        due = false
    end
    if due and is_ios() and review and review.request_review then
        local ok = pcall(review.request_review)
        if ok then d.last_at = os.time() end
    end
    pcall(sys.save, path(), d)
end

return M
