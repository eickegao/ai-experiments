-- shared/item_drawer.lua
-- 通用左侧道具抽屉（2026-09-28 用户效果图）：屏幕左边缘一个木质把手（箭头），点一下或往右拖 → 拉出木质竖条道具栏。
-- 每格：道具图标 + 名字 + 右上角数量角标（红圈数字，0 个不显示）。点有货的格 = on_use，没货 = on_buy（去商店）。
-- 道具库存/购买走 shared/items.lua（inv），购买界面走 shared/shop_ui.lua。每个游戏只需给出自己的道具 id 列表。
-- 接入：
--   1. 游戏 atlas 加入 /assets/images/shared/drawer_*.png、badge_red.png、badge_green.png（tools/shop_art.py 生成）
--   2. local dr = require("shared.item_drawer").new{ root, atlas, font, inv, ids = {"star","bomb","egg"},
local i18n = require("shared.i18n")
--          y = 把手的 y（抽屉以它为中心展开，把手对着中间那格）, to_root = fn(可选),
--          count = fn(id)（可选，显示数量）, keep_open = true（可选，点了不收起）,
--          on_use = function(id) ... end,   -- 点了有货的道具
--          on_buy = function(id) ... end }  -- 点了没库存的道具（通常 shop_ui.open{ focus = id, ... }）
--   3. on_input 里（商店面板之后、游戏操作之前）：if dr.on_input(action) then return true end
--   4. 库存变化后 dr.refresh()
local M = {}

local layout = require("shared.layout")
local function screen_l() return -540 - layout.extra_x() end   -- root 坐标下屏幕左边缘（root 居中；宽屏按左右出血外推，iPad 2026-10-19）
local PW = 220                 -- 抽屉宽
local SLOT = 180               -- 每格边长
local HEAD = 24                -- 顶部留白（与底部一致，中间格正好在抽屉中心）
local TAB_W, TAB_H = 80, 160
local OPEN_T = 0.22

local WHITE = vmath.vector4(1, 1, 1, 1)

local function box(parent, x, y, w, h, tex, atlas, slice)
    local n = gui.new_box_node(vmath.vector3(x, y, 0), vmath.vector3(w, h, 0))
    if tex then gui.set_texture(n, atlas); gui.play_flipbook(n, hash(tex)) end
    if slice then gui.set_slice9(n, vmath.vector4(slice, slice, slice, slice)) end
    gui.set_parent(n, parent)
    return n
end

local function label(parent, s, x, y, sc, font)
    local t = gui.new_text_node(vmath.vector3(x, y, 0), s)
    gui.set_font(t, font); gui.set_scale(t, vmath.vector3(sc, sc, 1)); gui.set_color(t, WHITE)
    gui.set_parent(t, parent)
    return t
end

function M.new(o)
    local self = {}
    local atlas, font, inv = o.atlas, o.font or "game_font", o.inv
    local n = #o.ids
    local PH = HEAD + n * (SLOT + 16) + 24
    local SCREEN_L = screen_l()
    local x_closed = SCREEN_L - PW / 2 - 6        -- 整个藏在屏幕外，只露出把手
    local x_open = SCREEN_L + PW / 2 + 8
    local open, drag = false, nil
    -- 输入 x → root 坐标（游戏可传 o.to_root(action)，root 有缩放时更准）
    local function X(action) return o.to_root and o.to_root(action).x or action.x end

    -- 把手在抽屉竖直中心 = 中间那格（用户 2026-09-29）；tab_y 与 y 同义（兼容旧参数）
    local py = o.tab_y or o.y or 0
    local tab_dy = 0
    local panel = box(o.root, x_closed, py, PW, PH, "drawer_panel", atlas, 34)
    -- 把手贴在抽屉右边缘（抽屉收起时它正好在屏幕左边缘）
    local tab = box(panel, PW / 2 + TAB_W / 2 - 16, tab_dy, TAB_W, TAB_H, "drawer_tab", atlas, 30)
    local arrow = box(tab, 6, 0, 44, 44, "drawer_arrow", atlas)

    local slots = {}
    for i, id in ipairs(o.ids) do
        local it = inv.catalog[id]
        local y = PH / 2 - HEAD - (i - 0.5) * (SLOT + 16)
        local s = box(panel, 0, y, SLOT, SLOT, "drawer_slot", atlas, 22)
        box(s, 0, 16, 118, 118, it.icon, atlas)
        i18n.fit(label(s, i18n.t(it.name), 0, -62, 0.8, font), SLOT - 12)   -- 抽屉格道具名走译文并缩到格内（2026-10-19 德语下还是英文 Star/Bomb/Hammer）
        local badge = box(s, SLOT / 2 - 16, SLOT / 2 - 16, 58, 58, "badge_red", atlas)
        local cnt = label(badge, "0", 0, 0, 0.75, font)
        slots[i] = { id = id, node = s, badge = badge, cnt = cnt }
    end

    -- 数量：游戏可给 o.count(id)（比如扣掉已装备的），默认库存
    local function count(id) return o.count and o.count(id) or inv.count(id) end

    function self.refresh()
        for _, s in ipairs(slots) do
            local c = count(s.id)
            gui.set_enabled(s.badge, c > 0)          -- 只显示数字，0 个不显示（用户 2026-09-29）
            gui.set_text(s.cnt, c > 99 and "99+" or tostring(c))
        end
    end

    local function slide(to_open, t)
        open = to_open
        local p = gui.get_position(panel)
        gui.cancel_animations(panel, "position.x")
        gui.animate(panel, "position.x", to_open and x_open or x_closed, gui.EASING_OUTCUBIC, t or OPEN_T)
        gui.set_euler(arrow, vmath.vector3(0, 0, to_open and 180 or 0))
        if to_open then self.refresh() end
        return p
    end

    function self.open() slide(true) end
    function self.close() slide(false) end
    function self.is_open() return open end
    function self.set_enabled(on) gui.set_enabled(panel, on) end

    --- 返回 true = 输入被抽屉吃掉
    function self.on_input(action)
        if not gui.is_enabled(panel) then return false end
        if action.pressed then
            if gui.pick_node(tab, action.x, action.y) then
                drag = { x0 = X(action), px = gui.get_position(panel).x, moved = false, tab = true }
                gui.cancel_animations(panel, "position.x")
                return true
            end
            if open then
                drag = { x0 = X(action), px = gui.get_position(panel).x, moved = false, inside = gui.pick_node(panel, action.x, action.y) }
                return true
            end
            return false
        end
        if not drag then return false end
        if action.released then
            local d = drag; drag = nil
            if d.moved then
                local x = gui.get_position(panel).x
                slide(x > (x_open + x_closed) / 2)
            elseif d.tab then
                slide(not open)
            elseif not d.inside then
                slide(false)                                 -- 点抽屉外 = 收起
            else
                for _, s in ipairs(slots) do
                    if gui.pick_node(s.node, action.x, action.y) then
                        gui.set_scale(s.node, vmath.vector3(0.9, 0.9, 1))
                        gui.animate(s.node, gui.PROP_SCALE, vmath.vector3(1, 1, 1), gui.EASING_OUTBACK, 0.2)
                        if count(s.id) > 0 then
                            if not o.keep_open then slide(false) end
                            if o.on_use then o.on_use(s.id) end
                        elseif o.on_buy then
                            o.on_buy(s.id)
                        end
                        break
                    end
                end
            end
            return true
        end
        -- 拖动：抽屉跟手
        local dx = X(action) - drag.x0
        if math.abs(dx) > 12 then drag.moved = true end
        if drag.moved then
            local p = gui.get_position(panel)
            p.x = math.max(x_closed, math.min(x_open, drag.px + dx))
            gui.set_position(panel, p)
        end
        return true
    end

    self.refresh()
    return self
end

return M
