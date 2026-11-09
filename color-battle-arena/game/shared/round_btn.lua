-- shared/round_btn.lua
-- 圆形图标按钮 + 底下一行译文（2026-10-14 用户定案：麻将底栏那种圆钮比带字胶囊好，底下的字走多语言，各游戏底栏逐个换）。
-- 画法同 games/mahjong setup_bar：深绿玻璃圆底 btn_round（300² 显示 150）+ 彩色图标（shared/icon_*.png 160² 显示 94）
-- + 右上角数量角标（badge_red / badge_green 54²）+ 圆底下方 game_font（全字形，中日韩都有）0.62 倍奶白文字。
-- 贴图要在宿主图集里：/assets/images/shared/btn_round.png、badge_red.png、badge_green.png、icon_<名>.png。
-- 用法：
--   local b = round_btn.new(root, { atlas = "flashlinez", icon = "icon_undo", text = T("UNDO"), x = -250, y = -700 })
--   gui.pick_node(b.root, ax, ay)   -- 命中用 root（圆底）；显隐/透明度也作用在 b.root（子节点跟着）
--   b.set_text(T("..."))            -- 换文字（长译文按 MAX_W 自动缩字）
--   b.set_badge(n)                  -- 角标：n>0 红圈数字（>99 → 99+），0 隐藏；plus = true 时 0 显示绿 "+"（麻将：点了去商店买）
--   b.bounce()                      -- 点击回弹
--   整图模式：{ atlas = "flashlinez", image = "btn_undo_round", text = T("UNDO"), ... } —— root 直接用该图（300² 显示 150），不建 icon 节点；
--   现有整图：shared/btn_undo_round（蓝底黄回转箭头）、btn_share_round（绿底白分享节点），用户 2026-10-14 出图，tools/split_round_btns.py 切。
--   root 模式：{ root = gui.get_node("btn_undo"), atlas = "watersort", image = "btn_undo_round", text = T("UNDO"), badge = false } —— 复用 .gui 已有节点
--   当圆底（Water Sort / Nuts Sort 底栏三钮，位置与长屏下移逻辑按 id 走），改成 D×D 并贴图；现有整图第三张 shared/btn_restart_round（红底白重开箭头）。
--   opts.badge = false 不建角标；opts.d 改直径（默认 D）；opts.max_w 文字最大宽（默认 MAX_W）；opts.font 换字体（默认 game_font）
local i18n = require("shared.i18n")
local M = {}

M.D = 150                 -- 圆底显示直径（麻将 BAR_D）
M.ICON = 94               -- 图标显示尺寸
M.BADGE = 54              -- 角标尺寸
M.LABEL_SCALE = 0.62      -- 48px 字 × 0.62 ≈ 30px
M.LABEL_GAP = 24          -- 文字顶到圆底的距离（北锚，麻将原来是居中 -D/2-24，文字一行高约 30，顶在 -D/2-9；改北锚便于两行译文不顶上来）
M.MAX_W = 210             -- 文字最大显示宽（两个钮间距 500 左右时不相撞；COMPARTILHAR 这种会缩）
M.LABEL_COLOR = vmath.vector4(1, 0.96, 0.85, 1)

local function box(parent, x, y, w, h, atlas, anim)
    local n = gui.new_box_node(vmath.vector3(x, y, 0), vmath.vector3(w, h, 0))
    gui.set_parent(n, parent, false)
    if atlas then gui.set_texture(n, atlas); pcall(gui.play_flipbook, n, hash(anim)) end
    gui.set_xanchor(n, gui.ANCHOR_NONE); gui.set_yanchor(n, gui.ANCHOR_NONE)
    return n
end

function M.new(parent, o)
    local d = o.d or M.D
    local b = { w = d, h = d, max_w = o.max_w or M.MAX_W, plus = o.plus }
    -- 两种画法：image = 整图（图标已画在圆钮里，用户出图，如 shared/btn_undo_round）；否则 btn_round 圆底 + icon 图标两层
    if o.root then
        -- root 模式：复用 .gui 里已有的命中框节点（位置、长屏下移、pick_node 都按它的 id 走），改成 D×D 贴新图
        b.root = o.root
        gui.set_size(b.root, vmath.vector3(d, d, 0))
        if o.atlas then gui.set_texture(b.root, o.atlas); pcall(gui.play_flipbook, b.root, hash(o.image or "btn_round")) end
    else
        b.root = box(parent, o.x or 0, o.y or 0, d, d, o.atlas, o.image or "btn_round")
    end
    if not o.image then b.icon = box(b.root, 0, 2, M.ICON, M.ICON, o.atlas, o.icon) end
    b.label = gui.new_text_node(vmath.vector3(0, -d / 2 - 9, 0), "")
    gui.set_parent(b.label, b.root, false)
    gui.set_font(b.label, o.font or "game_font"); gui.set_pivot(b.label, gui.PIVOT_N)
    gui.set_color(b.label, o.color or M.LABEL_COLOR)
    gui.set_xanchor(b.label, gui.ANCHOR_NONE); gui.set_yanchor(b.label, gui.ANCHOR_NONE)
    if o.badge ~= false then
        b.badge_bg = box(b.root, d / 2 - 20, d / 2 - 20, M.BADGE, M.BADGE, o.atlas, "badge_red")
        b.badge = gui.new_text_node(vmath.vector3(0, 2, 0), "0")
        gui.set_parent(b.badge, b.badge_bg, false)
        gui.set_font(b.badge, o.font or "game_font"); gui.set_scale(b.badge, vmath.vector3(0.7, 0.7, 1))
        gui.set_xanchor(b.badge, gui.ANCHOR_NONE); gui.set_yanchor(b.badge, gui.ANCHOR_NONE)
    end

    function b.set_text(s)
        gui.set_scale(b.label, vmath.vector3(M.LABEL_SCALE, M.LABEL_SCALE, 1))   -- fit 只缩不放：先重置
        gui.set_text(b.label, s or "")
        i18n.fit(b.label, b.max_w)
    end
    function b.set_badge(n)
        if not b.badge_bg then return end
        n = n or 0
        if n > 0 then
            gui.set_enabled(b.badge_bg, true); pcall(gui.play_flipbook, b.badge_bg, hash("badge_red"))
            gui.set_text(b.badge, n > 99 and "99+" or tostring(n))
        elseif b.plus then
            gui.set_enabled(b.badge_bg, true); pcall(gui.play_flipbook, b.badge_bg, hash("badge_green"))
            gui.set_text(b.badge, "+")
        else
            gui.set_enabled(b.badge_bg, false)
        end
    end
    function b.set_enabled(v) gui.set_enabled(b.root, v) end
    function b.bounce()
        gui.cancel_animations(b.root, gui.PROP_SCALE)
        gui.set_scale(b.root, vmath.vector3(0.88, 0.88, 1))
        gui.animate(b.root, gui.PROP_SCALE, vmath.vector3(1, 1, 1), gui.EASING_OUTBACK, 0.2)
    end
    function b.delete() gui.delete_node(b.root) end   -- 子节点随 root 一起删

    b.set_text(o.text)
    b.set_badge(o.count or 0)
    return b
end

return M
