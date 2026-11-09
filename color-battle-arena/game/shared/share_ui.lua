-- shared/share_ui.lua
-- 分享/回放共用 UI（spec 2026-09-23 share-link-replay §3.3/§3.4）：
--   toast(text)                       顶级文本 2s 淡出（克隆宿主 "level_text" 继承字体）
--   share_text(text)                  系统分享面板：defold-sharing `share.text`；HTML5 navigator.share→剪贴板；否则只 toast
--   show_banner(title,on_skip,on_play) 观看态横幅 "WATCHING A REPLAY" + SKIP / PLAY IT MYSELF
--   hide_banner() / banner_visible() / on_input(action) → "skip"|"play"|nil
-- 要求宿主 gui 里有 id 为 "level_text" 的文本节点。
local layout = require("shared.layout")
local T = require("shared.i18n").t
local pill_btn = require("shared.pill_btn")   -- 回放横幅/链接局按钮改三段胶囊 + 译文（2026-10-18 多语言）
local M = {}
local st = { banner = nil, toast = nil }

local function clone_text(text, pos, scale, color)
    local n = gui.clone(gui.get_node("level_text"))
    gui.set_parent(n, nil)
    gui.set_enabled(n, true)
    gui.set_position(n, pos)
    gui.set_scale(n, vmath.vector3(scale, scale, 1))
    gui.set_rotation(n, vmath.quat_rotation_z(0))
    gui.set_text(n, text)
    gui.set_color(n, color)
    return n
end

function M.toast(text)
    if st.toast then pcall(gui.delete_node, st.toast) end
    local n = clone_text(text, vmath.vector3(540, 1500, 0), 1.0, vmath.vector4(1, 1, 1, 0))
    st.toast = n
    gui.animate(n, "color.w", 1, gui.EASING_OUTQUAD, 0.2, 0, function()
        gui.animate(n, "color.w", 0, gui.EASING_INQUAD, 0.4, 1.6, function()
            pcall(gui.delete_node, n)
            if st.toast == n then st.toast = nil end
        end)
    end)
end

-- iOS：分享面板收起后引擎音频可能停在"被打断"状态（见 audiofix/ext.manifest），
-- 面板收起时机不可知，按几个时间点让引擎重新激活（重复调用无害）
local function schedule_audio_resume()
    if not (audiofix and audiofix.resume) then return end
    for _, t in ipairs({ 1.0, 3.0, 6.0, 12.0 }) do
        timer.delay(t, false, function()
            local ok = audiofix.resume()
            pcall(function() require("shared.deeplink").log("audiofix.resume after share t=" .. t .. " -> " .. tostring(ok)) end)
        end)
    end
end

function M.share_text(text)
    if share and share.text then
        share.text(text)
        schedule_audio_resume()
        return
    end
    if html5 then
        local js = string.format(
            "(navigator.share ? navigator.share({text: %q}) : Promise.reject())" ..
            ".catch(function(){ return navigator.clipboard && navigator.clipboard.writeText(%q) })",
            text, text)
        pcall(html5.run, js)
        M.toast(T("Link copied"))
        return
    end
    print("[share] " .. text)
    M.toast(T("Link copied"))
end

--- 回放 / 链接局用的胶囊按钮（2026-10-18 多语言）：shared/pill_btn 三段零件（result_atlas）+ 译文，替代各游戏烘焙英文的
--- btn_skip / btn_play_myself / btn_again / btn_quit / btn_share_flat / btn_*_pill。返回 root 节点：命中用 gui.pick_node(root)，
--- 删 root 连零件一起删，缩放动画打在 root 上。o = { icon = "share"|"flag"|"next"|…, min_w = 330, pop = 延迟秒（给了就从 0.2 弹到 1） }
function M.pill(x, y, text, color, o)
    o = o or {}
    local b = pill_btn.new(nil, { atlas = "result_atlas", color = color or "blue", icon = o.icon, text = text, x = x, y = y, min_w = o.min_w or 330 })
    if o.pop then
        gui.set_scale(b.root, vmath.vector3(0.2, 0.2, 1))
        gui.animate(b.root, gui.PROP_SCALE, vmath.vector3(1, 1, 1), gui.EASING_OUTBACK, 0.3, o.pop)
    end
    return b.root
end

--- atlas = 宿主图集名（历史参数，按钮已改胶囊不再用它）
--- opts.no_buttons = 只显示标题（Flash Linez 回看：不给 SKIP / PLAY，用户 2026-10-07）
function M.show_banner(title, on_skip, on_play, atlas, opts)
    M.hide_banner()
    local b = { nodes = {} }
    if opts and opts.no_buttons then
        local extra = layout.extra()
        local bar = gui.new_box_node(vmath.vector3(540, 90 - extra - extra / 2, 0), vmath.vector3(layout.width() + 4, 180 + extra, 0))   -- 宽屏通栏
        gui.set_color(bar, vmath.vector4(0.1, 0.1, 0.16, 0.94))
        b.nodes[#b.nodes + 1] = bar
        b.nodes[#b.nodes + 1] = clone_text(title, vmath.vector3(540, 150 - extra, 0), 0.9, vmath.vector4(1, 1, 1, 1))
        st.banner = b
        return
    end
    -- 放底部（用户 2026-09-23）：盖住 UNDO/SHARE/RESET 那一行，观看时不该碰它们。
    -- 长屏上那一行被安全区逻辑下移了 extra，横幅整体跟着下移并向下出血（同 win_celebration.screen_extra 公式）
    local extra = layout.extra()
    local shift = extra
    local bar = gui.new_box_node(vmath.vector3(540, 170 - shift - extra / 2, 0), vmath.vector3(layout.width() + 4, 340 + extra, 0))   -- 宽屏通栏
    gui.set_color(bar, vmath.vector4(0.1, 0.1, 0.16, 0.94))
    b.nodes[#b.nodes + 1] = bar
    b.nodes[#b.nodes + 1] = clone_text(title, vmath.vector3(540, 285 - shift, 0), 0.9, vmath.vector4(1, 1, 1, 1))
    -- 两键改三段胶囊 + 译文（2026-10-18 多语言：原 btn_skip / btn_play_myself 是烘焙英文图，atlas 参数不再使用）；宿主 gui 要有 result_atlas + button_font
    b.skip = M.pill(330, 130 - shift, T("SKIP"), "purple")
    b.play = M.pill(750, 130 - shift, T("PLAY IT MYSELF"), "blue")
    b.nodes[#b.nodes + 1] = b.skip
    b.nodes[#b.nodes + 1] = b.play
    b.on_skip, b.on_play = on_skip, on_play
    st.banner = b
end

function M.set_banner_handlers(on_skip, on_play)
    if st.banner then st.banner.on_skip, st.banner.on_play = on_skip, on_play end
end

function M.hide_banner()
    if not st.banner then return end
    for _, n in ipairs(st.banner.nodes) do pcall(gui.delete_node, n) end
    st.banner = nil
end

function M.banner_visible() return st.banner ~= nil end

-- 网页端开播闸门：浏览器在用户首次点击前不许出声，回放链接是自动开播的，
-- 所以 HTML5 上先盖一层提示，点一下再开播（这一下同时解锁 AudioContext）
function M.show_gate(text)
    M.hide_gate()
    local g = { nodes = {} }
    local dim = gui.new_box_node(vmath.vector3(540, 960, 0), vmath.vector3(1080, 2400, 0)); layout.fill(dim)
    gui.set_color(dim, vmath.vector4(0, 0, 0, 0.55))
    g.nodes[#g.nodes + 1] = dim
    g.nodes[#g.nodes + 1] = clone_text(text, vmath.vector3(540, 1000, 0), 1.3, vmath.vector4(1, 1, 1, 1))
    local hint = clone_text(T("TAP ANYWHERE"), vmath.vector3(540, 920, 0), 0.8, vmath.vector4(1, 0.85, 0.2, 1))
    g.nodes[#g.nodes + 1] = hint
    st.gate = g
end

function M.hide_gate()
    if not st.gate then return end
    for _, n in ipairs(st.gate.nodes) do pcall(gui.delete_node, n) end
    st.gate = nil
end

function M.gate_visible() return st.gate ~= nil end

function M.on_input(action)
    local b = st.banner
    if not b or not action.released then return nil end
    if b.skip and gui.pick_node(b.skip, action.x, action.y) then
        if b.on_skip then b.on_skip() end
        return "skip"
    end
    if b.play and gui.pick_node(b.play, action.x, action.y) then
        if b.on_play then b.on_play() end
        return "play"
    end
    return nil
end

return M
