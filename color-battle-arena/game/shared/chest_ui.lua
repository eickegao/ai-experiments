-- shared/chest_ui.lua — 大厅每日宝箱（用户 2026-10-05：7 天打卡卡片太占地，改成顶栏右侧一个小宝箱）
-- 两态（用户 2026-10-05：打开 App 点宝箱就算打卡，不要求先玩一局）：ready = 今天还没点（发光上下晃，点一下 → 服务端打卡 → 飞币）；
--       open = 今天已点（打勾）。奖励数额来自服务端回包，这里不写死任何金币数。
-- 美术先用打卡卡片里的 chest_3x 占位，用户后补"发光的箱子 / 打开的箱子"两张图。
local earn = require("shared.earn")
local M = {}


--- 纯函数：s = earn.state。今天没打卡 → ready（点宝箱打卡）；打过 → open
function M.state(s)
    return s.checked_today and "open" or "ready"
end

local function box(parent, x, y, w, h, tex, atlas)
    local n = gui.new_box_node(vmath.vector3(x, y, 0), vmath.vector3(w, h, 0))
    if tex then gui.set_texture(n, atlas); gui.play_flipbook(n, hash(tex)) end
    if parent then gui.set_parent(n, parent) end
    return n
end

--- o = { parent, x, y, atlas, font, coin_target(), on_claim_start(reward), on_claim(1) }
function M.new(o)
    local ui = {}
    local atlas = o.atlas
    local base_pos = vmath.vector3(o.x, o.y, 0)
    local chest = box(o.parent, o.x, o.y, 150, 150, "chest_closed", atlas)   -- 用户宝箱图（合/开两张，tools/chest_art_cut.py）
    local glow = box(o.parent, o.x, o.y, 190, 190, "coin_star", atlas)   -- 占位光晕（星星金币放大淡化）
    gui.set_color(glow, vmath.vector4(1, 0.9, 0.3, 0.35)); gui.move_below(glow, chest)
    local mark = box(chest, 44, -40, 48, 48, "icon_check", atlas)
    local hint = gui.new_text_node(vmath.vector3(o.x, o.y - 78, 0), "")
    gui.set_font(hint, o.font or "system_font"); gui.set_scale(hint, vmath.vector3(0.38, 0.38, 1)); gui.set_color(hint, vmath.vector4(1, 1, 1, 0.9)); gui.set_parent(hint, o.parent)
    ui.root = chest
    local cur = nil
    local opening = false   -- 正在播"开箱 → 飞币 → 淡出"

    local function stop_anims()
        gui.cancel_animations(chest, gui.PROP_POSITION); gui.cancel_animations(glow, gui.PROP_SCALE)
        gui.set_position(chest, base_pos); gui.set_scale(glow, vmath.vector3(1, 1, 1))
    end

    local function fly(n, on_done)   -- on_done：最后一枚落袋时调用
        local src = gui.get_screen_position(chest)
        local dst = o.coin_target and o.coin_target() or src
        local landed = 0
        for k = 1, n do
            local fc = box(nil, 0, 0, 64, 64, "coin_gold", atlas)
            gui.set_screen_position(fc, vmath.vector3(src.x + math.random(-30, 30), src.y + math.random(-20, 20), 0))
            local target = gui.screen_to_local(fc, vmath.vector3(dst.x, dst.y, 0))
            local delay = (k - 1) * 0.07
            gui.animate(fc, gui.PROP_SCALE, vmath.vector3(0.6, 0.6, 1), gui.EASING_INQUAD, 0.5, delay)
            gui.animate(fc, gui.PROP_POSITION, target, gui.EASING_INQUAD, 0.5, delay, function()
                pcall(gui.delete_node, fc)
                if o.on_claim then o.on_claim(1) end
                landed = landed + 1
                if landed == n and on_done then on_done() end
            end)
        end
    end

    function ui.refresh()
        local s = earn.state
        local st = M.state(s)
        if st == cur then return end
        cur = st
        stop_anims()
        gui.set_enabled(glow, st == "ready"); gui.set_enabled(mark, false)
        -- 已打卡：宝箱不显示（用户 2026-10-05：开箱、金币飞完就消失）；刚点开时由 on_tap 播完动画再隐藏
        gui.set_enabled(chest, st == "ready" or opening)
        gui.set_color(chest, vmath.vector4(1, 1, 1, 1))
        gui.play_flipbook(chest, hash(st == "ready" and "chest_closed" or "chest_open"))
        local img = (st == "ready") and { 181, 150 } or { 149, 150 }   -- 两张图原尺寸（高 150）
        gui.set_size(chest, vmath.vector3(img[1], img[2], 0))
        gui.set_text(hint, "")   -- 宝箱下不写字（用户 2026-10-05：去掉 "Day N"）；闪光即"可点"
        if st == "ready" then
            gui.animate(chest, gui.PROP_POSITION, vmath.vector3(o.x, o.y + 12, 0), gui.EASING_INOUTSINE, 0.55, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
            gui.animate(glow, gui.PROP_SCALE, vmath.vector3(1.25, 1.25, 1), gui.EASING_INOUTSINE, 0.8, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
        end
    end

    --- 抬起且未滚动时由大厅调用；返回 true = 吃掉
    local busy = false
    function ui.on_tap(action)
        if not gui.pick_node(chest, action.x, action.y) then return false end
        gui.set_scale(chest, vmath.vector3(0.92, 0.92, 1)); gui.animate(chest, gui.PROP_SCALE, vmath.vector3(1, 1, 1), gui.EASING_OUTBACK, 0.25)
        if cur ~= "ready" or busy then return true end
        busy = true
        earn.checkin(function(ok, d)
            busy = false
            if not ok then
                if d and d.reason == "already" then earn.state.checked_today = true; ui.refresh() end   -- 别的设备/重复点：直接变已打卡
                return
            end
            -- 服务端已把奖励记进余额（earn.checkin 里 set_balance）：先藏起来，飞到位再逐枚加回
            local reward = tonumber(d.reward) or 0
            -- 注意：earn.checkin 在回调我们之前已经 set state.checked_today 并触发 on_change → 大厅 refresh 了一次，
            -- 那时 opening 还是 false，宝箱已被 refresh 隐藏。这里置 opening 后强制重算一遍，把开箱图显示回来
            opening = true
            cur = nil
            -- 开箱图停留到金币全部落袋（或倍数字飘完），再停 LINGER 秒才淡出（用户 2026-10-05）
            local LINGER = 2.0
            local function fade_out()
                gui.animate(chest, "color.w", 0, gui.EASING_INQUAD, 0.5, LINGER, function()
                    opening = false
                    gui.set_enabled(chest, false)
                end)
            end
            if reward > 0 then
                if o.on_claim_start then o.on_claim_start(reward) end
                fly(reward, fade_out)
            else   -- 倍数日：服务端不单发打卡币，弹字提示
                local t = gui.new_text_node(vmath.vector3(o.x, o.y + 40, 0), ((earn.state.streak_day == 7) and "×3" or "×2") .. " TODAY!")
                gui.set_font(t, o.font or "system_font"); gui.set_scale(t, vmath.vector3(0.9, 0.9, 1)); gui.set_color(t, vmath.vector4(1, 0.85, 0.2, 1)); gui.set_parent(t, o.parent)
                gui.animate(t, gui.PROP_POSITION, vmath.vector3(o.x, o.y + 140, 0), gui.EASING_OUTQUAD, 1.2, 0, function() pcall(gui.delete_node, t) end)
                gui.animate(t, "color.w", 0, gui.EASING_INQUAD, 0.6, 0.7)
                timer.delay(1.3, false, fade_out)
            end
            ui.refresh()   -- 换成开箱图，opening 期间保持显示
        end)
        return true
    end

    function ui.destroy() for _, n in ipairs({ chest, glow, hint }) do pcall(gui.delete_node, n) end end
    ui.refresh()
    return ui
end

return M
