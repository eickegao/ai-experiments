-- shared/result_ui.lua
-- 统一结算页（1.2.0 子项目 2，spec docs/superpowers/specs/2026-10-13-result-ui-design.md）：
--   win：黑幕 → 桂叶+王冠（背后光芒）+四号角+红缎带标题弹入（号角音+彩带+重震）→ 0.8s 大金币+"+N"（鞭炮）→ 2.2s 主键(+BRAG 在主键上方) 弹出
--        → 点主键飞币逐枚落袋（coin 音+轻震，余额副本跳数）→ update 倒计时到点回调 on_primary
--   fail：黑幕 → 桂叶+裂纹灰王冠+三断箭+棕缎带标题（fail 音+两下重震）→ 0.3s RETRY(+附加键) 弹出
--   win 也可传 extra（附加键在 BRAG/主键之上，CLASHDOZ 的 RANKING / CLOSE，2026-10-26）
-- 纯动态顶级节点（屏幕坐标），贴图 texture 名 result_atlas（shared/result.atlas），文字 game_font / button_font / title_font（宿主 gui 要声明），
-- 音效打到每个游戏 collection 里的 /result_sfx 对象（shared/result_sfx.go）。显示期间吞掉全部输入。
-- 推进不挂动画回调（2026-08-17 Water Sort NEXT 失灵教训）：飞币完成由 update(dt) 倒计时判定。
--
-- 用法（宿主 gui_script）：
--   local result_ui = require("shared.result_ui")
--   result_ui.show(host, { mode = "win"|"fail", title = "LEVEL CLEAR", reward = N|nil, hud = vector3|nil, button = "NEXT"|"CLOSE"|"RETRY",
--                          on_primary = fn, on_share = fn|nil, extra = { { text, icon, color, badge, on_tap } }|nil, sound = bool|nil,
--                          btn_shift = px|nil（整列按钮再往下让这么多：CLASHDOZ 金币行下面还有一行技能点，2026-11-05） })
--   function update(self, dt) result_ui.update(host, dt) end
--   on_input 最前：if result_ui.on_input(host, action) then return true end
--     （必须在宿主任何 `if not action.released then return` / `if action.pressed then … return` 之前：模块要先收到 pressed 才认 released，
--       否则按钮永远点不动——2026-10-13 审查 CatTrail/Pupdoku 踩过）
--   余额副本优先传 hud_node（宿主 HUD 金币节点）/ hud_text_node：模块克隆它们保持屏幕变换，与真实 HUD 像素重合；
--   退而求其次传 hud = 屏幕坐标 vector3。
--   开新关 / 离开前：result_ui.hide(host)；fail 页附加键角标刷新：result_ui.set_badge(host, "UNDO", n)
local layout = require("shared.layout")
local i18n = require("shared.i18n")
local haptic = require("shared.haptic")
local coin = require("shared.coin")
local pill_btn = require("shared.pill_btn")
local T = i18n.t
local M = {}

M.SFX = "/result_sfx"
M.ATLAS = "result_atlas"
local GOLD = vmath.vector4(1, 0.85, 0.2, 1)
local RED = vmath.vector4(1, 0.35, 0.3, 1)
local WHITE = vmath.vector4(1, 1, 1, 1)
local CONFETTI = {
    vmath.vector4(0.95, 0.35, 0.35, 1), vmath.vector4(0.98, 0.65, 0.25, 1), vmath.vector4(0.98, 0.85, 0.30, 1),
    vmath.vector4(0.40, 0.80, 0.45, 1), vmath.vector4(0.35, 0.65, 0.95, 1), vmath.vector4(0.70, 0.45, 0.90, 1),
}
local TITLE_Y, COIN_X, COIN_Y, PLUS_GAP = 1250, 540, 930, 30   -- COIN_X 仅作飞币落点兜底；实际金币位置随 +N 字宽居中算
local BTN_Y, BRAG_Y, EXTRA_STEP = 760, 600, 160   -- BTN_Y = 按钮列最上一格；BRAG_Y = 有 BRAG 时主键下移到的那格
local BTN_T_WIN, BTN_T_FAIL, COIN_T, CONFETTI_T = 2.2, 0.3, 0.8, 1.6
local FLY_MAX, FLY_GAP, FLY_DUR, FLY_TAIL = 12, 0.1, 0.5, 0.35

--- 千分位（与大厅/各游戏 fmt_coins 一致，余额副本克隆 HUD 文字时格式不跳）
local function fmt(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
local function sfx(st, name) if st.sound ~= false then pcall(msg.post, M.SFX .. "#" .. name, "play_sound") end end
local function box(st, x, y, w, h, anim, parent)
    local n = gui.new_box_node(vmath.vector3(x, y, 0), vmath.vector3(w, h, 0))
    if anim then gui.set_texture(n, M.ATLAS); pcall(gui.play_flipbook, n, hash(anim)) end
    if parent then gui.set_parent(n, parent, false) end
    st.nodes[#st.nodes + 1] = n
    return n
end
local function text(st, s, x, y, sc, col, pivot, parent, font)
    local n = gui.new_text_node(vmath.vector3(x, y, 0), s)
    gui.set_font(n, font or "game_font"); gui.set_scale(n, vmath.vector3(sc, sc, 1)); gui.set_color(n, col or WHITE)
    if pivot then gui.set_pivot(n, pivot) end
    if parent then gui.set_parent(n, parent, false) end
    st.nodes[#st.nodes + 1] = n
    return n
end
local function pop(n, delay)
    gui.set_enabled(n, true)
    gui.set_scale(n, vmath.vector3(0.2, 0.2, 1))
    gui.animate(n, gui.PROP_SCALE, vmath.vector3(1, 1, 1), gui.EASING_OUTBACK, 0.3, delay or 0)
end
local function alive(host, st) return host.__result == st end

--- 装饰标题组（照搬 Flash Linez 结算页版式，坐标以桂叶中心为原点）：
--   win：桂叶 1.2 倍打底，王冠顶在桂叶上沿中央，四支号角一排贴桂叶两翼，红缎带横在桂叶下沿、白字写在缎带上
--   fail：灰褐桂叶 + 裂纹灰王冠 + 三支断箭交叉 + 棕色破缎带、深灰字
local function title_group(st, mode, title)
    local g = box(st, 540, TITLE_Y, 1, 1)
    gui.set_visible(g, false)
    local win = mode == "win"
    local ly = win and -24 or -50   -- 桂叶中心相对组中心：让整组（缎带底～王冠顶）在 TITLE_Y 上下居中
    local rib
    if win then
        -- 王冠 + 背后光芒挂在一个浮动子节点上，整体微微上下浮（±5，1.8 s 乒乓）；桂叶/号角/缎带不动（用户 2026-10-13）
        local fl = box(st, 0, ly + 85, 1, 1, nil, g)
        gui.set_visible(fl, false)
        gui.animate(fl, "position.y", ly + 95, gui.EASING_INOUTSINE, 1.8, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
        st.rays = box(st, 0, 0, 640, 640, "fx_rays", fl)   -- 光芒中心在王冠背后（先建 = 压在最底）
        gui.set_color(st.rays, vmath.vector4(1, 1, 1, 0))
        gui.animate(st.rays, "color.w", 0.9, gui.EASING_OUTQUAD, 0.6, 0.2)
        gui.animate(st.rays, "euler.z", 360, gui.EASING_LINEAR, 14, 0, nil, gui.PLAYBACK_LOOP_FORWARD)
        box(st, 0, ly, 540, 335, "deco_leaf_win", g)
        box(st, 0, 0, 206, 165, "deco_crown", fl)
        box(st, -280, ly, 159, 129, "deco_trumpet1", g); box(st, -150, ly, 127, 127, "deco_trumpet2", g)
        box(st, 150, ly, 127, 127, "deco_trumpet3", g);  box(st, 280, ly, 159, 129, "deco_trumpet4", g)
        rib = box(st, 0, ly - 130, 700, 179, "deco_ribbon_win", g)   -- 贴图里的两颗星已抹掉：字长不定，不能让装饰压字
        gui.set_slice9(rib, vmath.vector4(120, 0, 120, 0))
    else
        box(st, 0, ly, 450, 279, "deco_leaf_fail", g)
        box(st, 7, ly + 62, 206, 165, "deco_crown_fail", g)   -- 灰暗裂纹王冠（与过关金冠成对；骷髅因儿童/地区禁忌弃用，用户 2026-10-13）
        box(st, -325, ly - 49, 203, 181, "deco_arrow1", g); box(st, -252, ly - 75, 110, 243, "deco_arrow2", g)
        box(st, 270, ly - 42, 129, 185, "deco_arrow3", g)
        rib = box(st, 7, ly - 163, 780, 179, "deco_ribbon_fail", g)
        gui.set_slice9(rib, vmath.vector4(150, 0, 150, 0))
    end
    -- 标题：title_font（PlayDozUI 80px 描边假粗 + 下阴影）单层；缎带贴图的带身中心在节点中心上方约 22（下面是折角）
    local t = text(st, T(title), 0, 22, 1, WHITE, nil, rib, "title_font")
    if win then
        gui.set_outline(t, WHITE); gui.set_shadow(t, vmath.vector4(0.62, 0.10, 0.16, 1))
    else
        local ink = vmath.vector4(0.22, 0.13, 0.09, 1)
        gui.set_color(t, ink); gui.set_outline(t, ink); gui.set_shadow(t, vmath.vector4(0, 0, 0, 0))
    end
    i18n.fit(t, win and 440 or 480)   -- 缎带两端是折角，字只能占中段
    gui.set_scale(g, vmath.vector3(0.1, 0.1, 1))
    gui.set_rotation(g, vmath.quat_rotation_z(math.rad(-12)))
    gui.animate(g, gui.PROP_SCALE, vmath.vector3(1, 1, 1), gui.EASING_OUTBACK, 0.45)
    gui.animate(g, "euler.z", 0, gui.EASING_OUTBACK, 0.45)
    return g
end

local function pill(st, o)
    local b = pill_btn.new(nil, { atlas = M.ATLAS, color = o.color, icon = o.icon, text = T(o.text), x = 540, y = o.y, min_w = o.min_w or 260 })
    gui.set_enabled(b.root, false)
    st.pills[#st.pills + 1] = { b = b, key = o.text, on_tap = o.on_tap, badge = o.badge }
    return b
end

--- 附加键角标（库存数；0 = 绿 "+"）
local function badge(st, b, n)
    local bd = box(st, b.w / 2 - 10, pill_btn.H / 2 - 10, 54, 54, n > 0 and "badge_red" or "badge_green", b.root)
    local tx = text(st, n > 0 and (n > 99 and "99+" or tostring(n)) or "+", 0, 0, 0.7, WHITE, nil, bd)
    return { node = bd, text = tx }
end

function M.hide(host)
    local st = host.__result
    if not st then return end
    host.__result = nil
    for _, p in ipairs(st.pills) do pcall(p.b.delete); pcall(gui.delete_node, p.b.root) end
    for i = #st.nodes, 1, -1 do pcall(gui.delete_node, st.nodes[i]) end
end

function M.is_shown(host) return host.__result ~= nil end

function M.show(host, opts)
    M.hide(host)
    opts = opts or {}
    local mode = opts.mode or "win"
    local st = { mode = mode, t = 0, emit = 0, nodes = {}, pills = {}, badges = {}, armed = false, btn_shown = false,
                 flying = nil, sound = opts.sound, on_primary = opts.on_primary, reward = tonumber(opts.reward) or 0, hud = opts.hud }
    local extra = layout.extra()
    -- 余额副本：克隆宿主 HUD 节点（set_parent(nil, true) 保持屏幕变换，与真实 HUD 像素重合）；飞币落点按锚点补 FIT 出血
    if opts.hud_node then
        local ic = gui.clone(opts.hud_node); gui.set_parent(ic, nil, true); st.nodes[#st.nodes + 1] = ic
        st.hud_icon_clone = ic
        local p = gui.get_position(ic)
        local ya = gui.get_yanchor(ic)
        st.hud = vmath.vector3(p.x, p.y + (ya == gui.ANCHOR_TOP and extra or (ya == gui.ANCHOR_BOTTOM and -extra or 0)), 0)
        if opts.hud_text_node then local tx = gui.clone(opts.hud_text_node); gui.set_parent(tx, nil, true); st.nodes[#st.nodes + 1] = tx; st.hud_text_clone = tx end
    end
    host.__result = st
    -- 黑幕（上下出血盖满长屏）
    local dim = box(st, 540, 960, 1080, 1920 + 2 * extra); layout.fill(dim)   -- 宽屏（iPad）也铺满
    gui.set_color(dim, vmath.vector4(0, 0, 0, 0))
    gui.animate(dim, "color.w", 0.88, gui.EASING_OUTQUAD, 0.3)
    -- 标题组
    st.title = title_group(st, mode, opts.title or (mode == "win" and "LEVEL CLEAR" or "FAILED"))
    local BTN_Y = BTN_Y - (tonumber(opts.btn_shift) or 0)   -- 按钮列整体下移（默认 0，其他游戏不变）
    if mode == "win" then
        sfx(st, "win"); pcall(haptic.heavy, 6)
        if st.reward > 0 then
            -- 大金币 + "+N"（0.8s 后弹出；鞭炮在 update 里到点放）：+N 左对齐放在金币右缘外 PLUS_GAP，
            -- 两者按实测字宽整组以 540 居中（用户 2026-10-13：原来 +N 居中定点，+20 时数字撞上金币）
            st.plus = text(st, "+" .. st.reward, 0, COIN_Y, 2.2, vmath.vector4(1, 0.85, 0.2, 0), gui.PIVOT_W)
            local okw, w = pcall(function() return resource.get_text_metrics(gui.get_font_resource(gui.get_font(st.plus)), gui.get_text(st.plus)).width end)
            w = ((okw and tonumber(w)) or 90) * 2.2
            local left = 540 - (120 + PLUS_GAP + w) / 2
            st.coin_x = left + 60
            st.coin = box(st, st.coin_x, COIN_Y, 120, 122, "coin_gold")
            gui.set_scale(st.coin, vmath.vector3(0.1, 0.1, 1))
            gui.animate(st.coin, gui.PROP_SCALE, vmath.vector3(1, 1, 1), gui.EASING_OUTBACK, 0.4, COIN_T)
            gui.set_position(st.plus, vmath.vector3(left + 120 + PLUS_GAP, COIN_Y, 0))
            gui.animate(st.plus, "color.w", 1, gui.EASING_OUTQUAD, 0.3, COIN_T + 0.1)
            -- 余额副本（HUD 位置；币已入账，从入账前的数起跳）
            if st.hud then
                st.bal_shown = math.max(0, coin.get_balance() - st.reward)   -- 预览局没入账时不显示负数
                if st.hud_icon_clone then
                    st.bal_icon = st.hud_icon_clone
                    st.bal_text = st.hud_text_clone or text(st, fmt(st.bal_shown), st.hud.x + 42, st.hud.y, 1.05, WHITE, gui.PIVOT_W)
                    gui.set_text(st.bal_text, fmt(st.bal_shown))
                else
                    st.bal_icon = box(st, st.hud.x, st.hud.y, 58, 59, "coin_gold")
                    st.bal_text = text(st, fmt(st.bal_shown), st.hud.x + 42, st.hud.y, 1.05, WHITE, gui.PIVOT_W)
                end
            end
        end
        -- 主键（NEXT/CLOSE）永远是按钮列最底下那个，BRAG 在它上面（用户 2026-10-19：下一步/关闭统一放结算页底部；fail 侧同理，主键在附加键下面）
        -- win 模式也可带附加键（CLASHDOZ 2026-10-26：RANKING / CLOSE）：附加键 1..n 从 BTN_Y 起往下排，BRAG、主键依次顺延；extra 为空时坐标与原来一致
        local extras = {}
        for i, e in ipairs(opts.extra or {}) do if i <= 3 then extras[#extras + 1] = e end end
        local top = BTN_Y - EXTRA_STEP * #extras
        pill(st, { text = opts.button or "NEXT", color = "purple", icon = "next", y = opts.on_share and (top - EXTRA_STEP) or top, on_tap = function() M._primary(host, st) end })
        if opts.on_share then
            pill(st, { text = "BRAG", color = "blue", icon = "flag", y = top, on_tap = function() sfx(st, "click"); opts.on_share() end })
        end
        for i, e in ipairs(extras) do
            pill(st, { text = e.text, color = e.color or "blue", icon = e.icon, y = BTN_Y - EXTRA_STEP * (i - 1), badge = e.badge,
                       on_tap = function() sfx(st, "click"); if e.on_tap then e.on_tap() end end })
        end
    else
        sfx(st, "fail"); pcall(haptic.heavy, 2)
        local close = opts.button == "CLOSE"
        -- 按钮列自上而下 = 附加键 1..n、主键；最上面一个固定在 BTN_Y，主键往下让（标题组缎带底边约 950，附加键不能往上叠）
        local extras = {}
        for i, e in ipairs(opts.extra or {}) do if i <= 3 then extras[#extras + 1] = e end end
        pill(st, { text = opts.button or "RETRY", color = close and "purple" or "orange", icon = close and "next" or "reset",
                   y = BTN_Y - EXTRA_STEP * #extras, on_tap = function() M._primary(host, st) end })
        for i, e in ipairs(extras) do
            pill(st, { text = e.text, color = e.color or "blue", icon = e.icon, y = BTN_Y - EXTRA_STEP * (i - 1), badge = e.badge,
                       on_tap = function() sfx(st, "click"); if e.on_tap then e.on_tap() end end })
        end
    end
    -- 同一页的按钮上下等宽（用户 2026-10-22：不管文字长短，两个键大小一样才好看）：全部抬到最宽那个；角标按统一后的宽度贴右缘
    local w = 0
    for _, p in ipairs(st.pills) do w = math.max(w, p.b.w) end
    for _, p in ipairs(st.pills) do
        p.b.set_width(w)
        if p.badge ~= nil then st.badges[p.key] = badge(st, p.b, tonumber(p.badge) or 0) end
    end
end

--- 主键：win 且有奖励 → 飞币（update 倒计时到点回调）；否则立即回调
function M._primary(host, st)
    if st.flying or st.done then return end
    sfx(st, "click")
    if st.mode ~= "win" or st.reward <= 0 then
        st.done = true
        if st.on_primary then st.on_primary() end
        return
    end
    for _, p in ipairs(st.pills) do gui.set_enabled(p.b.root, false) end
    if st.plus then gui.animate(st.plus, "color.w", 0, gui.EASING_OUTQUAD, 0.2) end
    if st.coin then gui.set_enabled(st.coin, false) end
    if st.rays then gui.animate(st.rays, "color.w", 0, gui.EASING_OUTQUAD, 0.3) end
    local n = math.min(FLY_MAX, st.reward)
    local base, rem = math.floor(st.reward / n), st.reward % n          -- 每枚加 base，最后 rem 枚各多 1
    local target = st.hud or vmath.vector3(COIN_X, COIN_Y, 0)
    for k = 1, n do
        local c = box(st, (st.coin_x or COIN_X) + math.random(-60, 60), COIN_Y + math.random(-40, 40), 88, 90, "coin_gold")
        local delay = (k - 1) * FLY_GAP
        local add = base + ((k > n - rem) and 1 or 0)
        gui.animate(c, gui.PROP_SCALE, vmath.vector3(0.6, 0.6, 1), gui.EASING_INQUAD, FLY_DUR, delay)
        gui.animate(c, gui.PROP_POSITION, vmath.vector3(target.x, target.y, 0), gui.EASING_INQUAD, FLY_DUR, delay, function()
            if not alive(host, st) then return end
            sfx(st, "coin"); pcall(haptic.tap); pcall(gui.delete_node, c)
            if st.bal_text then
                st.bal_shown = st.bal_shown + add
                pcall(gui.set_text, st.bal_text, fmt(st.bal_shown))
                pcall(gui.set_scale, st.bal_icon, vmath.vector3(1.3, 1.3, 1))
                pcall(gui.animate, st.bal_icon, gui.PROP_SCALE, vmath.vector3(1, 1, 1), gui.EASING_OUTQUAD, 0.15)
            end
        end)
    end
    st.flying = FLY_DUR + (n - 1) * FLY_GAP + FLY_TAIL
end

local function confetti(st, extra)
    local x = 540 + (math.random() - 0.5) * layout.width()   -- 宽屏整宽撒
    local y = 1920 + extra + 30
    local n = gui.new_box_node(vmath.vector3(x, y, 0), vmath.vector3(14 + math.random() * 14, 22 + math.random() * 12, 0))
    gui.set_color(n, CONFETTI[math.random(#CONFETTI)])
    gui.set_rotation(n, vmath.quat_rotation_z(math.random() * 6.28))
    local dur = 1.3 + math.random() * 0.9
    gui.animate(n, gui.PROP_POSITION, vmath.vector3(x + (math.random() - 0.5) * 360, -60, 0), gui.EASING_INSINE, dur, 0, function() pcall(gui.delete_node, n) end)
    gui.animate(n, "euler.z", (math.random() - 0.5) * 720, gui.EASING_LINEAR, dur)
    st.nodes[#st.nodes + 1] = n
end

function M.update(host, dt)
    local st = host.__result
    if not st then return end
    local before = st.t
    st.t = st.t + dt
    if st.mode == "win" then
        if st.t < CONFETTI_T then
            st.extra = st.extra or layout.extra()
            st.emit = st.emit + dt * 40
            while st.emit >= 1 do confetti(st, st.extra); st.emit = st.emit - 1 end
        end
        if before < COIN_T and st.t >= COIN_T and st.reward > 0 then sfx(st, "firework") end
    end
    local show_at = st.mode == "win" and BTN_T_WIN or BTN_T_FAIL
    if not st.btn_shown and st.t >= show_at then
        st.btn_shown = true
        for i, p in ipairs(st.pills) do pop(p.b.root, (i - 1) * 0.1) end
    end
    if st.flying then
        st.flying = st.flying - dt
        if st.flying <= 0 then
            st.flying = nil; st.done = true
            if st.on_primary then st.on_primary() end
        end
    end
end

--- 返回 true = 已吞输入（显示期间一律 true）；false = 未显示
function M.on_input(host, action)
    local st = host.__result
    if not st then return false end
    if action.x == nil or action.y == nil then return true end   -- 非触摸动作（Android back 键等）：显示期间照吞，不进命中判定
    if action.pressed then st.armed = true
    elseif action.released and st.armed and st.btn_shown and not st.flying then
        for _, p in ipairs(st.pills) do
            if gui.is_enabled(p.b.root) and gui.pick_node(p.b.root, action.x, action.y) then
                gui.set_scale(p.b.root, vmath.vector3(0.9, 0.9, 1))
                gui.animate(p.b.root, gui.PROP_SCALE, vmath.vector3(1, 1, 1), gui.EASING_OUTBACK, 0.2)
                if p.on_tap then p.on_tap() end
                return true
            end
        end
    end
    return true
end

--- fail 页附加键角标刷新（如 Mahjong 买完道具）
function M.set_badge(host, text_key, n)
    local st = host.__result
    local bd = st and st.badges[text_key]
    if not bd then return end
    n = tonumber(n) or 0
    pcall(gui.play_flipbook, bd.node, hash(n > 0 and "badge_red" or "badge_green"))
    gui.set_text(bd.text, n > 0 and (n > 99 and "99+" or tostring(n)) or "+")
end

-- 让 tools/i18n_extract.py 看到各游戏以字面量传进来的标题/按钮 key（模块里 T(opts.title) 是动态的）；此函数从不调用
local function _i18n_keys()
    return T("LEVEL CLEAR"), T("DONE"), T("VICTORY"), T("ALL CLEAR"), T("FAILED"),
           T("NEXT"), T("CLOSE"), T("RETRY"), T("HOME"), T("QUIT"), T("BRAG"), T("UNDO"), T("RANKING"), T("PLAY")
end

return M
