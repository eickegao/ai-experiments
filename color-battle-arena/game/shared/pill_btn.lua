-- shared/pill_btn.lua
-- 运行时拼装的胶囊按钮（多语言方案 B，用户 2026-10-10 定案：按钮宽度按文字临时生成，不再用整张带字贴图）。
-- 零件：tools/gen_pill_parts.py → assets/images/pill/（pill_<color>_l/m/r 三段 2× 贴图 + icon_<name> 白色图标），要放进宿主图集。
-- 文字：button.font（PlayDozUI 48px + 描边 2.2 假粗体 + 阴影 y-3.7 做 3D 深边），颜色/描边白、阴影 = 该配色的底边色。
-- 用法：
--   local b = pill_btn.new(parent_or_nil, { atlas = "watersort", color = "green", icon = "flag", text = T("CHALLENGE"), x = 0, y = -820 })
--   gui.pick_node(b.root, ax, ay)   -- 命中用 root（透明，尺寸 = 整个胶囊）
--   b.set_text(T("..."))            -- 换文字自动重排宽度
--   也可传 root = 已有节点（.gui 里摆好位置的 box），零件挂在它下面，它本身 set_visible(false)。
--   整图按钮（封面 PLAY / HOW TO PLAY / BACK TO HOME，shared/buttons.atlas）只叠字：pill_btn.label(gui.get_node("btn_play"), { text = T("PLAY"), color = "orange" })
local i18n = require("shared.i18n")
local M = {}

M.H = 139                 -- 显示高（贴图 272 × 0.51）
local K = 0.51            -- 2× 贴图 → 显示缩放
local CAP = 66            -- 圆头贴图显示宽（130 × K）
local MARGIN = 12         -- 圆头贴图左侧的透明外边距（24 × K）
local BODY_DY = -4.6      -- 贴图中心比胶囊本体中心低 9px（阴影在下）→ 零件节点下移
local PAD = 45            -- 本体左/右留白（原图图标距本体左缘 88px × K）
local ICON = 50            -- 图标显示尺寸
local GAP = 14            -- 图标与文字间距
local TEXT_SCALE = 0.85   -- 48px 字 × 0.85 ≈ 41px（比原图 33px 大一号更清楚，用户 2026-10-10）
local ICON_DY = -2.5      -- 图标 3D 深边偏移（原图 5px × K）

M.ICON, M.GAP, M.PAD = ICON, GAP, PAD   -- 单测用

M.EDGE = {   -- 与 tools/gen_pill_parts.py COLORS 的 edge 一致（文字/图标的 3D 阴影色）
    blue = vmath.vector4(18/255, 82/255, 156/255, 1), orange = vmath.vector4(168/255, 62/255, 20/255, 1),
    green = vmath.vector4(38/255, 118/255, 54/255, 1), purple = vmath.vector4(84/255, 66/255, 140/255, 1),
    gold = vmath.vector4(178/255, 102/255, 12/255, 1), grey = vmath.vector4(72/255, 62/255, 110/255, 1),
}

local function box(parent, x, y, w, h, atlas, anim)
    local n = gui.new_box_node(vmath.vector3(x, y, 0), vmath.vector3(w, h, 0))
    gui.set_parent(n, parent, false)
    if atlas then gui.set_texture(n, atlas); pcall(gui.play_flipbook, n, hash(anim)) end
    gui.set_xanchor(n, gui.ANCHOR_NONE); gui.set_yanchor(n, gui.ANCHOR_NONE)
    return n
end

local function text_width(node)
    local ok, m = pcall(function() return resource.get_text_metrics(gui.get_font_resource(gui.get_font(node)), gui.get_text(node)) end)
    return (ok and m and m.width or 0) * gui.get_scale(node).x
end

function M.new(parent, o)
    o = o or {}
    local color, edge = o.color or "blue", M.EDGE[o.color or "blue"] or M.EDGE.blue
    local root = o.root
    if not root then
        root = gui.new_box_node(vmath.vector3(o.x or 0, o.y or 0, 0), vmath.vector3(1, M.H, 0))
        if parent then gui.set_parent(root, parent, false) end
    end
    gui.set_visible(root, false)   -- 只做命中框/变换父节点，自己不画
    local b = { root = root, nodes = {} }
    local function part(x, y, w, h, anim) local n = box(root, x, y, w, h, o.atlas, anim); b.nodes[#b.nodes + 1] = n; return n end
    b.l = part(0, BODY_DY, CAP, M.H, "pill_" .. color .. "_l")
    b.m = part(0, BODY_DY, 1, M.H, "pill_" .. color .. "_m")
    b.r = part(0, BODY_DY, CAP, M.H, "pill_" .. color .. "_r")
    if o.icon then
        b.icon_sh = part(0, ICON_DY, ICON, ICON, "icon_" .. o.icon); gui.set_color(b.icon_sh, edge)
        b.icon = part(0, 0, ICON, ICON, "icon_" .. o.icon)
    end
    b.text = gui.new_text_node(vmath.vector3(0, 0, 0), o.text or "")
    gui.set_parent(b.text, root, false)
    gui.set_font(b.text, o.font or "button_font")
    gui.set_pivot(b.text, gui.PIVOT_W)
    local ts = o.text_scale or TEXT_SCALE
    gui.set_scale(b.text, vmath.vector3(ts, ts, 1))
    -- 描边 = 拉丁字母的假粗体；中日韩笔画密，再描边会糊成一团（"重置"），这些语言只留 3D 阴影
    local cjk = ({ ["zh-Hans"] = true, ["zh-Hant"] = true, ja = true, ko = true })[i18n.lang]
    gui.set_color(b.text, vmath.vector4(1, 1, 1, 1)); gui.set_outline(b.text, vmath.vector4(1, 1, 1, cjk and 0 or 1)); gui.set_shadow(b.text, edge)
    gui.set_xanchor(b.text, gui.ANCHOR_NONE); gui.set_yanchor(b.text, gui.ANCHOR_NONE)
    b.nodes[#b.nodes + 1] = b.text

    --- 按文字宽度重排：本体宽 = PAD + 图标 + GAP + 文字 + PAD，不小于 min_w，不大于 max_w（超了缩文字）
    function b.layout()
        local min_w, max_w = o.min_w or 200, o.max_w or 460
        local iw = o.icon and (ICON + GAP) or 0
        gui.set_scale(b.text, vmath.vector3(ts, ts, 1))
        local tw = text_width(b.text)
        if PAD + iw + tw + PAD > max_w then i18n.fit(b.text, max_w - PAD - iw - PAD); tw = text_width(b.text) end
        local w = math.floor(math.max(min_w, PAD + iw + tw + PAD) / 2 + 0.5) * 2   -- 取偶数整数：零件对齐到像素，接缝不露线
        b.w = w
        gui.set_size(root, vmath.vector3(w, M.H, 0))
        gui.set_position(b.l, vmath.vector3(-w / 2 - MARGIN + CAP / 2, BODY_DY, 0))
        gui.set_position(b.r, vmath.vector3(w / 2 + MARGIN - CAP / 2, BODY_DY, 0))
        local body_in = CAP - MARGIN   -- 圆头贴图里属于本体的宽
        gui.set_size(b.m, vmath.vector3(w - 2 * body_in, M.H, 0))   -- 不与圆头重叠：半透明阴影叠加会出一条深线
        local x = -(iw + tw) / 2   -- 内容整体居中：短文字撑不满 min_w 时也在正中（用户 2026-10-14：CLOSE 的字偏左）
        if o.icon then
            gui.set_position(b.icon, vmath.vector3(x + ICON / 2, 0, 0)); gui.set_position(b.icon_sh, vmath.vector3(x + ICON / 2, ICON_DY, 0))
            x = x + ICON + GAP
        end
        gui.set_position(b.text, vmath.vector3(x, 0, 0))
    end
    function b.set_text(s) gui.set_text(b.text, s or ""); b.layout() end
    --- 一列按钮等宽用：把宽度抬到 w（不小于自身文字所需；结算页上下键统一取最宽的那个，用户 2026-10-22）
    function b.set_width(w) o.min_w = w; o.max_w = math.max(o.max_w or 460, w); b.layout() end
    --- 行排布用：按给定文字缩放重排（row() 塞不下时统一缩小）
    function b.relayout(scale) ts = scale or ts; b.layout() end
    function b.delete() for _, n in ipairs(b.nodes) do pcall(gui.delete_node, n) end; b.nodes = {} end
    b.layout()
    return b
end

--- 整图按钮叠字（2026-10-13 用户定案：封面的空白玻璃按钮图由用户出，字由程序叠；shared/buttons.atlas btn_glass_<color>）。
--- root = .gui 里已摆好、带贴图的 box 节点（命中仍用它）。文字 button_font 居中，宽度超过 root 宽 × 0.7 时等比缩小。
--- o = { text, color = "orange"|"green"|"purple"（暂只用于将来按色微调），text_scale = LABEL_SCALE, max_w = root 宽 × LABEL_MAXW, font = "label_font",
---       fill = 白, outline = LABEL_OUTLINE（近黑）, dy = 0（文字相对 root 中心的上移量） }
--- 字体 label_font = assets/fonts/label.font：与 button.font 同字同字符集，72px、描边 1.5（≈48px 时的 1）、无阴影（用户 2026-10-13：不要阴影，加黑边线）；宿主 gui 要声明。
--- 扁平模板按钮（Arrow/TAPIX/WorDoz/CardDoz 的 cover_btn_play/home，tools/cover_art_gen.py 空白版）同样用 label：
---   PLAY：text_scale 1.64（原烘焙 118px 字）、max_w 460、dy 6（面在图中心上方 6）；BACK TO HOME：text_scale 0.72、max_w 520、fill/outline 用各游戏 home_text 色。
M.LABEL_SCALE = 0.97   -- label.font 72px × 0.97 ≈ 70px 行高，大写字母约占 171 高按钮的 1/3，接近原烘焙 PLAY 的比例（72px 底字放大到 1.6 倍仍清楚）
M.LABEL_MAXW = 0.74    -- 文字最宽占按钮宽的比例（两端留出圆角与星光）
M.LABEL_OUTLINE = vmath.vector4(0.08, 0.06, 0.10, 1)   -- 文字黑描边色（近黑微偏紫，比纯黑柔和）
--- 返回 { root, text, set_text(s), delete() }。
function M.label(root, o)
    o = o or {}
    local size = gui.get_size(root)
    local ts = o.text_scale or M.LABEL_SCALE
    local max_w = o.max_w or size.x * M.LABEL_MAXW
    local b = { root = root }
    b.text = gui.new_text_node(vmath.vector3(0, o.dy or 0, 0), o.text or "")   -- 用户出的玻璃按钮面就在几何中心（量过：上抬 4.5% 时字明显偏高，2026-10-13）
    gui.set_parent(b.text, root, false)
    gui.set_font(b.text, o.font or "label_font")
    gui.set_pivot(b.text, gui.PIVOT_CENTER)
    -- 白字 + 黑描边、无阴影（用户 2026-10-13：玻璃按钮上阴影怎么调都重，改成黑边线）；label.font 描边 1、阴影关
    gui.set_color(b.text, o.fill or vmath.vector4(1, 1, 1, 1)); gui.set_outline(b.text, o.outline or M.LABEL_OUTLINE); gui.set_shadow(b.text, vmath.vector4(0, 0, 0, 0))
    gui.set_xanchor(b.text, gui.ANCHOR_NONE); gui.set_yanchor(b.text, gui.ANCHOR_NONE)
    function b.set_text(s)
        gui.set_text(b.text, s or "")
        gui.set_scale(b.text, vmath.vector3(ts, ts, 1))   -- fit 只缩不放：先回到默认再量
        i18n.fit(b.text, max_w)
    end
    function b.delete() pcall(gui.delete_node, b.text) end
    b.set_text(o.text)
    return b
end

--- 一行按钮并排居中：按各自宽度顺序摆，间距 gap；总宽超过 avail 时所有按钮文字等比缩小后重排。
--- btns = { b1, b2, ... }（pill_btn.new 返回值，按从左到右）；o = { gap = 24, cx = 0, y = nil(不改), avail = 1040 }
function M.row(btns, o)
    o = o or {}
    local gap, avail = o.gap or 24, o.avail or 1040
    local function total() local t = 0; for i, b in ipairs(btns) do t = t + b.w + (i > 1 and gap or 0) end; return t end
    local t = total()
    if t > avail then
        local k = avail / t
        for _, b in ipairs(btns) do b.relayout(TEXT_SCALE * k) end
        t = total()
    end
    local x = (o.cx or 0) - t / 2
    for _, b in ipairs(btns) do
        local p = gui.get_position(b.root)
        p.x = x + b.w / 2; if o.y then p.y = o.y end
        gui.set_position(b.root, p)
        x = x + b.w + gap
    end
end

--- 静态登记（从不调用）：封面三个整图按钮的键，让 tools/i18n_extract.py 看得到（各封面以字面量传入 label 时也能对上）
function M._i18n_keys() return i18n.t("PLAY"), i18n.t("HOW TO PLAY"), i18n.t("BACK TO HOME") end

return M
