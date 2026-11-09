-- shared/shop_ui.lua
-- 通用商店面板（2026-09-29 按用户意见改版）：紫色标题条 "Store" + iOS 风格关闭（浅灰圆+灰叉）+ 金币余额居中，
-- 3 列道具卡（图标+xN 角标、名字、绿色金币价按钮）；看视频按钮只在广告可用时出现；金币包分页/底部说明默认不显示。
-- 接入（每个游戏）：
--   1. 游戏 atlas 加入 /assets/images/shared/*.png（tools/shop_art.py 生成）与 /assets/images/dashboard/coin_gold.png
--   2. local inv = require("shared.items").new(key, CATALOG, STARTER, ORDER)；CATALOG 条目可带 soon = true（功能未做，灰卡）
--   3. 入口：顶栏 shop_ui.new_hud_button(root, atlas, x, y)（LV/金币右侧，推荐）或 shop_ui.new_button（同图，任意位置/尺寸）
--      点它 shop_ui.open{ root, atlas, font, inv, focus, on_change, on_close }；游戏间只需换 CATALOG（道具），
--      可选覆盖 title / info / coin_packs（{ {icon, 数量文字, 价格文字}, ... }，传 false 不显示 Coins 分页）
--   4. on_input 最前面：if shop_ui.is_open() then shop_ui.on_input(action); return true end
--      入口命中：shop_ui.hit(btn, action) —— 按钮带点击回弹
local coin = require("shared.coin")
local i18n = require("shared.i18n")
local T = i18n.t
local M = {}
local st = nil

local WHITE = vmath.vector4(1, 1, 1, 1)
local DARK = vmath.vector4(0.24, 0.2, 0.4, 1)

local function node(parent, x, y, w, h, tex, atlas, col, slice)
    local n = gui.new_box_node(vmath.vector3(x, y, 0), vmath.vector3(w, h, 0))
    if tex then gui.set_texture(n, atlas); gui.play_flipbook(n, hash(tex)) end
    if col then gui.set_color(n, col) end
    if slice then gui.set_slice9(n, vmath.vector4(slice, slice, slice, slice)) end
    gui.set_parent(n, parent)
    return n
end

local function text(parent, s, x, y, sc, font, col, pivot)
    local t = gui.new_text_node(vmath.vector3(x, y, 0), s)
    gui.set_font(t, font); gui.set_scale(t, vmath.vector3(sc, sc, 1))
    gui.set_color(t, col or WHITE)
    if pivot then gui.set_pivot(t, pivot) end
    gui.set_parent(t, parent)
    return t
end

--- 商店入口按钮（icon_store，资源图切图）
function M.new_button(root, atlas, x, y, size)
    size = size or 150
    return node(root, x, y, size, size, "icon_store", atlas)
end

--- 顶栏商店入口（2026-09-28 用户：放 LV/金币右侧，用资源图切出的商店图标 icon_store，不加闪光；
--- 持续轻微呼吸缩放 1.0↔1.08，让玩家知道可以点）。返回按钮节点（命中用 M.hit）
local breathing = {}
local function breathe(b)
    gui.set_scale(b, vmath.vector3(1, 1, 1))
    gui.animate(b, gui.PROP_SCALE, vmath.vector3(1.08, 1.08, 1), gui.EASING_INOUTSINE, 0.9, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
end

function M.new_hud_button(root, atlas, x, y, size)
    local b = node(root, x, y, size or 130, size or 130, "icon_store", atlas)
    breathing[b] = true
    breathe(b)
    return b
end

--- 入口命中判定（带按下回弹，回弹完恢复呼吸），btn 可为 nil
function M.hit(btn, action)
    if not btn or not gui.pick_node(btn, action.x, action.y) then return false end
    gui.cancel_animations(btn, gui.PROP_SCALE)
    gui.set_scale(btn, vmath.vector3(0.88, 0.88, 1))
    gui.animate(btn, gui.PROP_SCALE, vmath.vector3(1, 1, 1), gui.EASING_OUTBACK, 0.2, 0, function()
        if breathing[btn] then breathe(btn) end
    end)
    return true
end

function M.is_open() return st ~= nil end

function M.close()
    if not st then return end
    pcall(gui.delete_node, st.dim)
    local cb = st.on_close
    st = nil
    if cb then cb() end
end

local function toast(s)
    if not st then return end
    local t = text(st.panel, s, 0, -st.ph / 2 - 60, 1.0, st.font, vmath.vector4(1, 0.45, 0.4, 1))   -- 面板下方黑幕上
    gui.animate(t, "color.w", 0, gui.EASING_INQUAD, 1.2, 0.6, function() pcall(gui.delete_node, t) end)
end

local build_tab

local function clear_body()
    if st.body then pcall(gui.delete_node, st.body) end
    st.body = node(st.panel, 0, 0, 1, 1, nil, nil, vmath.vector4(1, 1, 1, 0))
    gui.set_inherit_alpha(st.body, false)
    st.btns_body = {}
end

-- 卡片：图标 + 库存角标 + 名字 + 绿色金币价按钮；看视频按钮只在广告可用时出现（用户 2026-09-29：现在只有购买）
local function boosters_page()
    local inv, atlas, font = st.inv, st.atlas, st.font
    local CW, GAP = 272, 22
    local top = st.cards_top
    for i, id in ipairs(inv.order) do
        local it = inv.catalog[id]
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        local n_in_row = math.min(3, #inv.order - row * 3)
        local x = (col - (n_in_row - 1) / 2) * (CW + GAP)
        local y = top - st.ch / 2 - row * (st.ch + GAP)
        local card = node(st.body, x, y, CW, st.ch, "card_bg", atlas, st.focus == id and vmath.vector4(1, 0.93, 0.75, 1) or nil, 24)
        gui.set_inherit_alpha(card, false)
        local cy = st.ch / 2
        node(card, 0, cy - 95, 150, 150, it.icon, atlas, it.soon and vmath.vector4(1, 1, 1, 0.45) or nil)
        local badge = node(card, 70, cy - 150, 70, 48, "btn_grey", atlas, vmath.vector4(0.45, 0.47, 0.6, 1), 18)
        local cnt = text(badge, "x" .. inv.count(id), 0, 0, 0.8, font)
        local nm = text(card, T(it.name), 0, cy - 205, 1.0, font, DARK)   -- 道具名走译文（各游戏 items.lua 静态列键）
        i18n.fit(nm, CW - 24)   -- 长名字缩到卡片内（用户 2026-10-19：FlashLinez 商店 Rainbow Ball/Regenbogenkugel 等放不下）
        if it.soon then
            i18n.fit(text(card, T("Coming soon"), 0, cy - 275, 0.8, font, vmath.vector4(0.45, 0.45, 0.55, 1)), CW - 24)   -- 意/西语 Prossimamente 等超卡宽
        else
            local buy = node(card, 0, cy - 280, 236, 84, "btn_green", atlas, nil, 22)
            node(buy, -52, 0, 52, 52, "coin_gold", atlas)
            text(buy, tostring(it.price), 22, 0, 1.1, font)
            st.btns_body[#st.btns_body + 1] = { buy, function()
                if inv.buy(id) then
                    gui.set_text(cnt, "x" .. inv.count(id)); st.set_balance()
                    if st.on_change then st.on_change(id) end
                else toast(T("Not enough coins")) end
            end }
            if st.video then
                local vid = node(card, 0, cy - 380, 236, 84, "btn_purple", atlas, nil, 22)
                node(vid, -72, 0, 44, 44, "icon_play", atlas)
                i18n.fit(text(vid, T("Watch"), 20, 0, 0.95, font), 150)   -- 越南语 Xem quảng cáo 超按钮
                st.btns_body[#st.btns_body + 1] = { vid, function()
                    inv.watch(id, function(ok)
                        if ok and st then gui.set_text(cnt, "x" .. inv.count(id)); if st.on_change then st.on_change(id) end end
                    end)
                end }
            end
        end
    end
end

M.COIN_PACKS = { { "icon_coins_s", "100", "$0.99" }, { "icon_coins_m", "600", "$4.99" }, { "icon_coins_l", "1500", "$9.99" } }
local function coins_page()
    local atlas, font = st.atlas, st.font
    local CW, CH, GAP = 272, 360, 22
    local top = st.ph / 2 - 300
    for i, p in ipairs(st.coin_packs) do
        local x = (i - (#st.coin_packs + 1) / 2) * (CW + GAP)
        local card = node(st.body, x, top - CH / 2, CW, CH, "card_bg", atlas, nil, 24)
        gui.set_inherit_alpha(card, false)
        node(card, 0, 70, 150, 150, p[1], atlas)
        text(card, p[2], 0, -30, 1.2, font, DARK)
        local b = node(card, 0, -120, 236, 84, "btn_grey", atlas, nil, 22)
        text(b, p[3], 0, 0, 1.0, font, vmath.vector4(0.4, 0.4, 0.5, 1))
    end
    text(st.body, T("Coin packs coming soon"), 0, top - CH - 60, 0.9, font, vmath.vector4(0.4, 0.38, 0.55, 1))
end

build_tab = function(tab)
    st.tab = tab
    if st.tab_b then
        gui.play_flipbook(st.tab_b, hash(tab == "boosters" and "btn_blue" or "btn_grey"))
        gui.set_color(st.tab_bt, tab == "boosters" and WHITE or vmath.vector4(0.3, 0.35, 0.6, 1))
        gui.play_flipbook(st.tab_c, hash(tab == "coins" and "btn_blue" or "btn_grey"))
        gui.set_color(st.tab_ct, tab == "coins" and WHITE or vmath.vector4(0.3, 0.35, 0.6, 1))
    end
    clear_body()
    if tab == "boosters" then boosters_page() else coins_page() end
end

--- opts = { root, atlas, font, inv, focus = 道具 id（高亮该卡，可选）, on_change(id), on_close(),
---          title = 标题（默认 "Store"）, info = 底部说明（默认无）,
---          coin_packs = 金币包表（给了才出现 "Items / Coins" 分页，默认无；内购接好后再开） }
--- 版式（2026-09-29 用户改）：标题 "Store" + iOS 风格关闭 + 金币余额居中 + 道具卡（只有金币购买）
function M.open(opts)
    if st then M.close() end
    local atlas, font = opts.atlas, opts.font or "game_font"
    local video = opts.inv.video_available()
    local ch = video and 430 or 330
    local rows = math.max(1, math.ceil(#opts.inv.order / 3))
    local tabs = type(opts.coin_packs) == "table" and #opts.coin_packs > 0
    local head = tabs and 300 or 210
    local pw = 960
    local ph = head + rows * (ch + 22) + (opts.info and 120 or 30)
    st = { inv = opts.inv, atlas = atlas, font = font, focus = opts.focus, ph = ph, btns = {}, btns_body = {},
           on_change = opts.on_change, on_close = opts.on_close, coin_packs = opts.coin_packs,
           video = video, ch = ch, cards_top = ph / 2 - head }
    st.dim = node(opts.root, 0, 0, 2400, 4000, nil, nil, vmath.vector4(0, 0, 0, 0.6))
    st.panel = node(st.dim, 0, -20, pw, ph, "panel_cream", atlas, nil, 40)
    gui.set_inherit_alpha(st.panel, false)
    local top = ph / 2
    -- 标题条
    local ban = node(st.panel, 0, top - 10, 560, 130, "banner_purple", atlas, nil, 30)
    text(ban, opts.title or T("Store"), 0, 4, 2.0, font)
    -- 关闭：iOS 风格浅灰圆 + 灰叉，面板右上角内侧
    local close = node(st.panel, pw / 2 - 62, top - 62, 76, 76, "btn_close_ios", atlas)
    st.btns[#st.btns + 1] = { close, M.close }
    -- 金币余额：图标 + 数字整体居中
    st.coin_icon = node(st.panel, 0, top - 125, 52, 52, "coin_gold", atlas)
    st.coin_text = text(st.panel, "", 0, top - 125, 1.05, font, DARK, gui.PIVOT_W)
    st.set_balance = function()
        gui.set_text(st.coin_text, tostring(coin.get_balance()))
        pcall(function()
            local fr = gui.get_font_resource(gui.get_font(st.coin_text))
            local w = resource.get_text_metrics(fr, gui.get_text(st.coin_text)).width * 1.05
            local left = -(52 + 12 + w) / 2
            gui.set_position(st.coin_icon, vmath.vector3(left + 26, top - 125, 0))
            gui.set_position(st.coin_text, vmath.vector3(left + 64, top - 125, 0))
        end)
    end
    st.set_balance()
    if tabs then
        st.tab_b = node(st.panel, -210, top - 215, 400, 90, "btn_blue", atlas, nil, 22)
        st.tab_bt = text(st.tab_b, T("Items"), 0, 0, 1.1, font)
        st.tab_c = node(st.panel, 210, top - 215, 400, 90, "btn_grey", atlas, nil, 22)
        st.tab_ct = text(st.tab_c, T("Coins"), 0, 0, 1.1, font)
        st.btns[#st.btns + 1] = { st.tab_b, function() build_tab("boosters") end }
        st.btns[#st.btns + 1] = { st.tab_c, function() build_tab("coins") end }
    end
    if opts.info then
        local info = node(st.panel, 0, -ph / 2 + 70, pw - 80, 80, "info_bar", atlas, nil, 26)
        text(info, opts.info, 0, 0, 0.72, font, vmath.vector4(0.4, 0.38, 0.55, 1))
    end
    build_tab((tabs and opts.tab) or "boosters")
    gui.set_scale(st.panel, vmath.vector3(0.85, 0.85, 1))
    gui.animate(st.panel, gui.PROP_SCALE, vmath.vector3(1, 1, 1), gui.EASING_OUTBACK, 0.22)
end

--- 面板打开时吞掉所有输入；点面板外 = 关闭
function M.on_input(action)
    if not st then return false end
    -- 打开商店那次点击的松手会紧接着到这里：没见过 pressed 前的 released 一律忽略，否则一开就被"点外面"关掉
    if action.pressed then st.armed = true; return true end
    if not action.released or not st.armed then return true end
    for _, list in ipairs({ st.btns, st.btns_body }) do
        for _, b in ipairs(list) do
            if gui.pick_node(b[1], action.x, action.y) then b[2](); return true end
        end
    end
    if not gui.pick_node(st.panel, action.x, action.y) then M.close() end
    return true
end

return M
