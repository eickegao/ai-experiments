-- shared/win_celebration.lua
-- 通用过关/失败结算演出（版式源自 Pupdoku 的优秀实现）：
--   全屏暗化（含长屏上下出血，绝不露边）→ 标题斜角弹入回正
--   →（胜利）彩带雨 1.6s → 2.2s 后按钮弹出；失败红字、按钮立即出。
-- 纯动态建节点、不依赖任何 .gui 节点；显示期间吞掉全部输入
-- （防触摸穿透到底层封面——历史大坑）。音效/震动由游戏自己放。
--
-- 用法（宿主 gui_script）：
--   local wc = require("shared.win_celebration")
--   wc.show(self, { mode = "win"|"fail", title = ?, button = ?,
--                   clone_text = "level_text" })   -- 克隆此节点继承字体
--   function update(self, dt) wc.update(self, dt) end
--   -- on_input 最前：
--   local r = wc.on_input(self, action)
--   if r == "primary" then wc.hide(self); <next/retry>; return true
--   elseif r then return true end
--   -- 开新关前：wc.hide(self)

local layout = require("shared.layout")
local T = require("shared.i18n").t
local M = {}

local GOLD = vmath.vector4(1, 0.85, 0.2, 1)
local RED = vmath.vector4(1, 0.35, 0.3, 1)
local CONFETTI = {
    vmath.vector4(0.95, 0.35, 0.35, 1), vmath.vector4(0.98, 0.65, 0.25, 1),
    vmath.vector4(0.98, 0.85, 0.30, 1), vmath.vector4(0.40, 0.80, 0.45, 1),
    vmath.vector4(0.35, 0.65, 0.95, 1), vmath.vector4(0.70, 0.45, 0.90, 1),
}


function M.hide(self)
    local st = self.__wc
    if not st then return end
    for _, n in ipairs(st.nodes) do pcall(gui.delete_node, n) end
    self.__wc = nil
end

function M.show(self, opts)
    M.hide(self)
    opts = opts or {}
    local mode = opts.mode or "win"
    local st = { t = 0, emit = 0, mode = mode, btn_shown = false,
                 armed = false, nodes = {} }
    self.__wc = st
    local extra = layout.extra()

    -- 暗化层（顶级节点，建得晚画得上；上下出血盖满长屏）
    local dim = gui.new_box_node(vmath.vector3(540, 960, 0),
        vmath.vector3(1080, 1920 + 2 * extra, 0))
    layout.fill(dim)   -- 宽屏（iPad）也铺满
    gui.set_color(dim, vmath.vector4(0, 0, 0, 0))
    -- opts.dim 可自定义黑幕深度（2026-08-13 Arrow 要求对齐 pupdoku 的 0.88）
    gui.animate(dim, "color.w", opts.dim or (mode == "win" and 0.5 or 0.55),
        gui.EASING_OUTQUAD, 0.3)
    st.nodes[#st.nodes + 1] = dim

    -- 标题：克隆宿主文本节点（继承字体），脱离原父挂顶级
    local title = gui.clone(gui.get_node(opts.clone_text or "level_text"))
    gui.set_parent(title, nil)
    gui.set_enabled(title, true)
    gui.set_position(title, vmath.vector3(540, 1140, 0))
    gui.set_text(title, opts.title and T(opts.title) or (mode == "win" and T("LEVEL CLEAR") or T("FAILED")))   -- 各游戏传的 "LEVEL CLEAR" 字面量也走表（用户 2026-10-10 真机：原来永远不翻）
    gui.set_color(title, mode == "win" and GOLD or RED)
    gui.set_scale(title, vmath.vector3(0.1, 0.1, 1))
    gui.set_rotation(title, vmath.quat_rotation_z(math.rad(-12)))
    local ts = opts.title_scale or 1.7
    gui.animate(title, gui.PROP_SCALE, vmath.vector3(ts, ts, 1), gui.EASING_OUTBACK, 0.45)
    gui.animate(title, "euler.z", 0, gui.EASING_OUTBACK, 0.45)
    st.nodes[#st.nodes + 1] = title
    st.title = title

    -- 按钮（胜利 2.2s 后弹出；失败立即）
    local btn = gui.new_box_node(vmath.vector3(540, 760, 0), vmath.vector3(360, 110, 0))
    gui.set_color(btn, vmath.vector4(0.16, 0.15, 0.24, 0.95))
    gui.set_enabled(btn, false)
    st.nodes[#st.nodes + 1] = btn
    st.btn = btn
    -- opts.button_texture = { atlas, anim }：主按钮用宿主图集里的胶囊贴图（与 SHARE 同款），不再画文字
    if opts.button_texture or opts.pill then
        gui.set_color(btn, vmath.vector4(1, 1, 1, 1))
        gui.set_size(btn, vmath.vector3(260, 140, 0))
        if opts.button_texture then
            gui.set_texture(btn, opts.button_texture[1])
            pcall(gui.play_flipbook, btn, hash(opts.button_texture[2]))
        end
        -- 样板（多语言方案 B，2026-10-10）：opts.button_font 给了就认为贴图是无字胶囊，文字用按钮字体画在图标右侧
        -- 贴图 510×272 显示成 260×140（×0.51）：原文字 64px 起点 x=196 → 节点 scale 0.68、x=-30；描边白=假粗体，阴影=深边色
        -- 多语言方案 B（2026-10-10）：opts.pill = { atlas, color, icon } → 贴图不用，按钮改为运行时拼装胶囊（宽度按译文）
        if opts.pill then
            local b = require("shared.pill_btn").new(nil, { root = btn, atlas = opts.pill.atlas, color = opts.pill.color, icon = opts.pill.icon,
                text = T(opts.button or "NEXT"), min_w = opts.pill.min_w or 260 })
            for _, n in ipairs(b.nodes) do st.nodes[#st.nodes + 1] = n end
        end
        if opts.no_button then st.btn_shown = true end
        if mode == "fail" then M._show_btn(st) end
        return
    end
    local bt = gui.clone(gui.get_node(opts.clone_text or "level_text"))
    gui.set_parent(bt, btn, false)
    gui.set_enabled(bt, true)
    gui.set_position(bt, vmath.vector3(0, 0, 0))
    gui.set_scale(bt, vmath.vector3(0.9, 0.9, 1))
    gui.set_rotation(bt, vmath.quat_rotation_z(0))
    gui.set_text(bt, opts.button and T(opts.button) or (mode == "win" and T("NEXT") or T("RETRY")))
    gui.set_color(bt, vmath.vector4(1, 1, 1, 1))
    st.nodes[#st.nodes + 1] = bt
    -- opts.no_button：宿主自己画按钮（分享回放结束页三键），主按钮永不显示
    if opts.no_button then st.btn_shown = true end

    if mode == "fail" then
        M._show_btn(st)
    end
end

local function pop(n)
    gui.set_enabled(n, true)
    gui.set_scale(n, vmath.vector3(0.2, 0.2, 1))
    gui.animate(n, gui.PROP_SCALE, vmath.vector3(1, 1, 1), gui.EASING_OUTBACK, 0.3)
end

function M._show_btn(st)
    if st.btn_shown then return end
    st.btn_shown = true
    pop(st.btn)
    for _, n in ipairs(st.companions or {}) do pcall(pop, n) end
end

--- 宿主自建的伴随按钮（如过关页的 BRAG）：登记后先藏起来，与主按钮同一时刻、同一弹跳出现
--- （用户 2026-10-01：BRAG 先出、NEXT 过 2 秒才出很怪）。节点归宿主所有，宿主自己删。
function M.add_button(self, node)
    local st = self.__wc
    if not st or st.btn_shown then return end
    gui.set_enabled(node, false)
    st.companions = st.companions or {}
    st.companions[#st.companions + 1] = node
end

-- 彩带：顶部随机位置生成，飘落 + 旋转 + 淡出自删
local function spawn_confetti(self, st, extra)
    local x = 540 + (math.random() - 0.5) * layout.width()   -- 宽屏整宽撒
    local y = 1920 + extra + 30
    local n = gui.new_box_node(vmath.vector3(x, y, 0),
        vmath.vector3(14 + math.random() * 14, 22 + math.random() * 12, 0))
    gui.set_color(n, CONFETTI[math.random(#CONFETTI)])
    gui.set_rotation(n, vmath.quat_rotation_z(math.random() * 6.28))
    local dur = 1.3 + math.random() * 0.9
    gui.animate(n, gui.PROP_POSITION,
        vmath.vector3(x + (math.random() - 0.5) * 360, -60, 0),
        gui.EASING_INSINE, dur, 0, function() pcall(gui.delete_node, n) end)
    gui.animate(n, "euler.z", (math.random() - 0.5) * 720, gui.EASING_LINEAR, dur)
end

function M.update(self, dt)
    local st = self.__wc
    if not st then return end
    st.t = st.t + dt
    if st.mode == "win" then
        if st.t < 1.6 then
            st.emit = st.emit + dt * 40
            local extra = st.extra or layout.extra()
            st.extra = extra
            while st.emit >= 1 do
                spawn_confetti(self, st, extra)
                st.emit = st.emit - 1
            end
        end
        if st.t >= 2.2 then
            M._show_btn(st)
        end
    end
end

-- 返回值："primary"=主按钮被点；true=已吞输入；false=未显示（放行）
function M.on_input(self, action)
    local st = self.__wc
    if not st then return false end
    if action.pressed then
        st.armed = true
    elseif action.released and st.armed and st.btn_shown and gui.is_enabled(st.btn)
           and gui.pick_node(st.btn, action.x, action.y) then
        return "primary"
    end
    return true
end

return M
