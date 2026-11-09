-- shared/checkin_ui.lua
-- 大厅"Daily Check-in"卡片（spec 3.2，效果图 2026-10-01）：7 格连续打卡；当天打完一局后今天格可点领奖，
-- 固定奖励日飞币入顶栏余额，倍数日（第 4/7 天）只提示 ×2/×3 已生效。状态全部来自 shared/earn.lua 的 state。
-- 纯动态建节点，挂在大厅 cards_root 顶部随卡片滚动；开关关着时大厅不建它。美术为占位，用户正式图同名替换。
local earn = require("shared.earn")
local T = require("shared.i18n").t
local M = {}

M.REWARDS = { 10, 20, 30, 0, 50, 75, 0 }
M.HEIGHT, M.GAP = 400, 36
local W = 1000
local WHITE = vmath.vector4(1, 1, 1, 1)
local NAVY = vmath.vector4(0.16, 0.2, 0.45, 1)
local GOLD = vmath.vector4(1, 0.82, 0.2, 1)

--- 7 格状态（纯函数，可单测）：streak_day = 今天是连续第几天（服务端算）；checked_today 已领 → 1..streak 全 done；
--- 未领 → 1..streak-1 done，streak 为 today；其余 future
function M.cells(s)
    s = s or {}
    local streak = tonumber(s.streak_day) or 1
    local out = {}
    for i = 1, 7 do
        local r = M.REWARDS[i]
        local status
        if s.checked_today and i <= streak then status = "done"
        elseif i < streak then status = "done"
        elseif i == streak then status = "today"
        else status = "future" end
        out[i] = { day = i, label = (i == 4 and "×2") or (i == 7 and "×3") or ("+" .. r), status = status, today = (i == streak) }
    end
    return out
end

function M.can_claim(s)
    s = s or {}
    return s.played_today == true and not s.checked_today
end

--- 卡片底部提示（打卡由服务端在当天首局自动完成，用户 2026-10-01）
function M.hint_text(s)
    s = s or {}
    if s.checked_today then return T("Day %d checked in! Come back tomorrow"):format(s.streak_day or 1) end
    if s.played_today then return T("Checking in...") end
    return T("Play one game today to check in")
end

local function box(parent, x, y, w, h, tex, atlas, slice)
    local n = gui.new_box_node(vmath.vector3(x, y, 0), vmath.vector3(w, h, 0))
    if tex then gui.set_texture(n, atlas); gui.play_flipbook(n, hash(tex)) end
    if slice then gui.set_slice9(n, vmath.vector4(slice, slice, slice, slice)) end
    if parent then gui.set_parent(n, parent) end
    return n
end
local function label(parent, s, x, y, sc, font, col)
    local t = gui.new_text_node(vmath.vector3(x, y, 0), s)
    gui.set_font(t, font); gui.set_scale(t, vmath.vector3(sc, sc, 1)); gui.set_color(t, col or WHITE)
    gui.set_parent(t, parent)
    return t
end

function M.new(o)
    local ui = {}
    local atlas, font = o.atlas, o.font or "system_font"
    local root = box(o.parent, 0, 0, W, M.HEIGHT, "checkin_panel", atlas, 40)
    ui.root = root

    -- 标题行（用户美术 sheet_v2：日历 + "Daily Check-in" 美术字 + (i)，tools/checkin_art_cut.py 切出）
    local tw = o.title_w or 465   -- 日历+标题整条，宽度 = 切图实际宽（96 高）
    box(root, -452 + tw / 2, 146, tw, 96, "title_checkin", atlas)
    local info = box(root, 440, 146, 63, 64, "icon_info", atlas)
    local hint = label(root, "", 0, 0, 0.55, font, vmath.vector4(1, 1, 1, 0.92)); gui.set_enabled(hint, false)   -- 提示行已去掉（用户 2026-10-01）

    -- 7 格：蓝格 + 星星金币 + 金额；第 4 天红格 2x 徽章、第 7 天红格 3x 宝箱（不写文字）；
    -- 右上角：未打卡空圈 / 已打卡绿勾；今天 = 后面垫金色描边环
    local cells = {}
    -- 7 格均分：白框内沿 ±486，格宽 128，8 个间隔（两边 + 6 个中间）各 9.5（用户 2026-10-01：间距要一样）
    local x0, dx = -412.5, 137.5
    local RED = vmath.vector4(0.85, 0.15, 0.2, 1)
    for i = 1, 7 do
        local c = {}
        local x = x0 + (i - 1) * dx
        local red = (i == 4 or i == 7)
        c.ring = box(root, x, 30, 144, 156, "day_cell_ring", atlas)   -- 今天：不同颜色的外框
        c.bg = box(root, x, 30, 128, 140, red and "day_cell_red" or "day_cell_blue", atlas)
        c.day = label(c.bg, T("Day %d"):format(i), -8, 44, 0.5, font, red and RED or NAVY)
        if i == 4 then c.icon = box(c.bg, 0, -16, 77, 76, "badge_2x", atlas)
        elseif i == 7 then c.icon = box(c.bg, 0, -18, 100, 92, "chest_3x", atlas)
        else
            c.icon = box(c.bg, 0, -4, 59, 60, "coin_star", atlas)
            c.amt = label(c.bg, "+" .. M.REWARDS[i], 0, -50, 0.55, font, NAVY)
        end
        c.mark = box(c.bg, 46, 50, 43, 44, "icon_check", atlas)   -- 只在已打卡时显示绿勾；没打卡无标志（用户 2026-10-01）
        cells[i] = c
    end

    -- 榜单入口（奖杯 / 地球 图标；enabled_ranking 为 false 时隐藏）
    local b1 = box(root, -240, -122, 440, 92, "btn_purple", atlas, 28); box(b1, -170, 0, 78, 76, "icon_trophy", atlas)
    label(b1, T("Weekly Ranking"), 30, 10, 0.66, font); label(b1, T("Top 20 win $5 Gift Card!"), 30, -22, 0.4, font)
    local b2 = box(root, 240, -122, 440, 92, "btn_blue", atlas, 28); box(b2, -170, 0, 75, 76, "icon_globe", atlas)
    label(b2, T("Country Ranking"), 30, 10, 0.66, font); label(b2, T("See which country is #1!"), 30, -22, 0.4, font)

    local function set_alpha(n, a) local c = gui.get_color(n); c.w = a; gui.set_color(n, c) end

    -- 飞币：从今天格飞 n 枚到顶栏余额（o.coin_target() 给屏幕坐标），每枚落袋 o.on_claim(1)。
    -- 飞币节点不挂父节点（顶层），用屏幕坐标换算，才能飞出卡片区的裁剪框、盖在顶栏上
    local function fly(from_node, n)
        local src = gui.get_screen_position(from_node)
        local dst = o.coin_target and o.coin_target() or src
        for k = 1, n do
            local fc = box(nil, 0, 0, 64, 64, "coin_gold", atlas)
            gui.set_screen_position(fc, vmath.vector3(src.x + math.random(-40, 40), src.y + math.random(-30, 30), 0))
            local target = gui.screen_to_local(fc, vmath.vector3(dst.x, dst.y, 0))
            local delay = (k - 1) * 0.08
            gui.animate(fc, gui.PROP_SCALE, vmath.vector3(0.6, 0.6, 1), gui.EASING_INQUAD, 0.5, delay)
            gui.animate(fc, gui.PROP_POSITION, target, gui.EASING_INQUAD, 0.5, delay, function()
                pcall(gui.delete_node, fc)
                if o.on_claim then o.on_claim(1) end
            end)
        end
    end


    function ui.refresh()
        local s = earn.state
        local cs = M.cells(s)
        for i, c in ipairs(cs) do
            local n = cells[i]
            gui.set_enabled(n.mark, c.status == "done")   -- 绿勾 = 已打卡
            gui.set_enabled(n.ring, c.today)               -- 金边 = 今天（打卡前后都在，用户 2026-10-02）
            set_alpha(n.bg, c.status == "future" and 0.8 or 1)
        end
        gui.set_text(hint, M.hint_text(s))
        gui.set_enabled(b1, s.enabled_ranking == true); gui.set_enabled(b2, s.enabled_ranking == true)
        gui.set_enabled(info, s.enabled_ranking == true)
        -- 当天首局在游戏里自动打了卡：回到大厅演一次（固定奖励飞币 / 倍数日弹字）
        if s.checkin_pending_celebrate and gui.is_enabled(root) then
            s.checkin_pending_celebrate = nil
            local today = cells[math.max(1, math.min(7, s.streak_day or 1))]
            local reward = s.checkin_reward_today or 0
            if reward > 0 then
                if o.on_claim_start then o.on_claim_start(reward) end
                fly(today.bg, reward)   -- 枚数 = 服务端实发
            else
                local t = label(root, ((s.streak_day == 7) and "×3" or "×2") .. " ACTIVE TODAY!", 0, 20, 1.2, font, GOLD)
                gui.animate(t, gui.PROP_POSITION, vmath.vector3(0, 120, 0), gui.EASING_OUTQUAD, 1.2, 0, function() pcall(gui.delete_node, t) end)
                gui.animate(t, "color.w", 0, gui.EASING_INQUAD, 0.6, 0.7)
            end
        end
    end

    --- 抬起且未滚动时由大厅调用；返回 true = 吃掉
    function ui.on_tap(action)
        if not gui.is_enabled(root) then return false end
        if earn.state.enabled_ranking and gui.pick_node(info, action.x, action.y) then
            if o.on_info then o.on_info() end
            return true
        end
        if earn.state.enabled_ranking then
            if gui.pick_node(b1, action.x, action.y) then if o.on_ranking then o.on_ranking() end return true end
            if gui.pick_node(b2, action.x, action.y) then if o.on_country then o.on_country() end return true end
        end
        for _, c in ipairs(cells) do   -- 格子不再是按钮（打卡自动完成）；点一下只刷新提示
            if gui.pick_node(c.bg, action.x, action.y) then gui.set_text(hint, M.hint_text(earn.state)); return true end
        end
        return gui.pick_node(root, action.x, action.y)
    end

    function ui.destroy() pcall(gui.delete_node, root) end

    ui.refresh()
    return ui
end

return M
