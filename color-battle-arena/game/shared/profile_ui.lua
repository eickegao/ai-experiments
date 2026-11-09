-- shared/profile_ui.lua
-- 昵称 + 头像面板（spec 3.2）：首次打卡前弹出；输入框用系统键盘（gui.show_keyboard，输入经 on_input 的 text/backspace），
-- 头像九宫格（avatar_1..9，占位图，用户正式头像同名替换）；OK → earn.set_profile，服务端 nickname_blocked 时提示换名。
local earn = require("shared.earn")
local T = require("shared.i18n").t
local layout = require("shared.layout")   -- 遮罩铺满整屏（iPad 2026-10-19）
local M = {}
local st = nil
local WHITE = vmath.vector4(1, 1, 1, 1)
local NAVY = vmath.vector4(0.16, 0.2, 0.45, 1)
local RED = vmath.vector4(0.9, 0.25, 0.25, 1)
local MAX = 12

local function utf8_len(s) local _, n = s:gsub("[^\128-\191]", ""); return n end
local function utf8_drop_last(s) return (s:gsub("[%z\1-\127\194-\244][\128-\191]*$", "")) end

function M.validate(nick)
    nick = (nick or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local n = utf8_len(nick)
    if n < 2 then return false, "At least 2 characters" end
    if n > MAX then return false, "At most 12 characters" end
    return true
end

function M.apply_text(cur, action_id, action)
    if action_id == "text" or action_id == hash("text") then
        local add = (action.text or ""):gsub("[\r\n\t]", "")
        local out = cur
        for ch in add:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            if utf8_len(out) >= MAX then break end
            out = out .. ch
        end
        return out
    elseif action_id == "backspace" or action_id == hash("backspace") then
        if action.pressed or action.repeated then return utf8_drop_last(cur) end
    end
    return cur
end

local function box(parent, x, y, w, h, tex, atlas, slice)
    local n = gui.new_box_node(vmath.vector3(x, y, 0), vmath.vector3(w, h, 0))
    if tex then gui.set_texture(n, atlas); gui.play_flipbook(n, hash(tex)) end
    if slice then gui.set_slice9(n, vmath.vector4(slice, slice, slice, slice)) end
    gui.set_parent(n, parent)
    return n
end
local function label(parent, s, x, y, sc, font, col)
    local t = gui.new_text_node(vmath.vector3(x, y, 0), s)
    gui.set_font(t, font); gui.set_scale(t, vmath.vector3(sc, sc, 1)); gui.set_color(t, col or WHITE)
    gui.set_parent(t, parent)
    return t
end

function M.is_open() return st ~= nil end

function M.close()
    if not st then return end
    pcall(gui.hide_keyboard)
    pcall(gui.delete_node, st.dim)
    st = nil
end

function M.open(o)
    if st then M.close() end
    local atlas, font = o.atlas, o.font or "system_font"
    st = { on_done = o.on_done, text = earn.state.nickname or "", avatar = earn.state.avatar or 1 }
    st.dim = box(o.root, 0, 0, 1080, 2400); layout.fill(st.dim)   -- 铺满整屏（用户 2026-10-19：iPad 上阴影没撑满）
    gui.set_color(st.dim, vmath.vector4(0, 0, 0, 0.72))   -- 压暗背景（用户 2026-10-02：原 0.55 太亮抢戏）
    -- 面板（用户 2026-10-02 效果图，二改：整体缩小、输入框靠近标签、行距拉开、Save 上移）
    local panel = box(st.dim, 0, 30, 900, 1380, "profile_panel", atlas, 48)
    box(panel, 0, 690, 560, 118, "profile_title", atlas)
    box(panel, 440, 685, 96, 98, "btn_x_blue", atlas)
    st.close = box(panel, 440, 685, 200, 200, nil, atlas); gui.set_color(st.close, vmath.vector4(0, 0, 0, 0))   -- 透明命中框 200×200（用户 2026-10-02：常点不中）
    -- 上半：当前头像（大）+ 名字输入框（紧挨 "Your Name" 与头像）
    st.big = box(panel, -300, 500, 210, 215, "avatar_" .. st.avatar, atlas)   -- 大头像不带铅笔（用户 2026-10-02）
    local nl = label(panel, T("Name"), -150, 565, 0.66, font, NAVY); gui.set_pivot(nl, gui.PIVOT_W)
    st.field = box(panel, 100, 480, 500, 94, "input_box", atlas, 24)
    st.field_text = label(st.field, "", -215, 0, 0.83, "name_font", NAVY); gui.set_pivot(st.field_text, gui.PIVOT_W)   -- 多语言字体（中日韩泰欧）
    st.err = label(panel, "", 100, 415, 0.48, font, RED)
    -- 分隔线 + "Choose Your Avatar"
    local line = box(panel, 0, 365, 800, 3); gui.set_color(line, vmath.vector4(0.55, 0.7, 0.95, 0.8))
    local cl = box(panel, 0, 365, 440, 40); gui.set_color(cl, vmath.vector4(1, 0.98, 0.93, 1))
    label(panel, T("Choose Your Avatar"), 0, 365, 0.68, font, NAVY)
    -- 头像 6×5（行距 150 让选中环不被下一行盖住）；选中 = 青色圆环 + 右下绿勾
    st.avatars = {}
    st.sel = box(panel, 0, 0, 120, 123, "avatar_sel", atlas)
    for i = 1, 30 do
        local col, row = (i - 1) % 6, math.floor((i - 1) / 6)
        st.avatars[i] = box(panel, -340 + col * 136, 250 - row * 150, 120, 123, "avatar_" .. i, atlas)   -- 图 180×184
    end
    st.tick = box(panel, 0, 0, 42, 42, "icon_check", atlas)
    st.ok = box(panel, 0, -540, 480, 100, "btn_save", atlas)
    local function render()
        gui.set_text(st.field_text, st.text == "" and T("Enter a name") or st.text)
        gui.set_color(st.field_text, st.text == "" and vmath.vector4(0.5, 0.5, 0.55, 1) or NAVY)
        local sel = st.avatars[st.avatar] or st.avatars[1]
        local p = gui.get_position(sel)
        gui.set_position(st.sel, p)
        gui.move_above(st.sel, st.avatars[30]); gui.move_above(sel, st.sel); gui.move_above(st.tick, sel)   -- 环压在别的头像上、选中头像压在环上
        gui.set_position(st.tick, vmath.vector3(p.x + 42, p.y - 42, 0))
        gui.play_flipbook(st.big, hash("avatar_" .. (st.avatar or 1)))
    end
    st.render = render
    render()
end

local function submit()
    local ok, msg = M.validate(st.text)
    if not ok then gui.set_text(st.err, msg); return end
    gui.set_text(st.err, "")
    local nick, avatar, done = st.text, st.avatar, st.on_done
    earn.set_profile(nick, avatar, function(ok2, d)
        if ok2 then
            M.close()
            if done then done() end
        elseif st then
            gui.set_text(st.err, d and d.reason == "nickname_blocked" and T("That name isn't allowed — try another") or T("Couldn't save — check your connection"))
        end
    end)
end

--- 面板打开时大厅把全部输入交给这里；返回 true 吃掉
function M.on_input(action_id, action)
    if not st then return false end
    if action_id == hash("enter") then pcall(gui.hide_keyboard); return true end   -- 回车键 = 收键盘（用户 2026-10-02）
    if action_id == hash("text") or action_id == hash("marked_text") or action_id == hash("backspace") then
        if action_id == hash("text") and (action.text or ""):find("[\r\n]") then pcall(gui.hide_keyboard) end   -- 回车作为文本进来也收
        local new = M.apply_text(st.text, action_id, action)
        if new ~= st.text then st.text = new; st.render() end
        return true
    end
    if action_id == hash("touch") and action.released then
        if gui.pick_node(st.field, action.x, action.y) then pcall(gui.show_keyboard, gui.KEYBOARD_TYPE_DEFAULT, true); return true end
        pcall(gui.hide_keyboard)   -- 点输入框以外任何地方先收键盘
        if gui.pick_node(st.close, action.x, action.y) then M.close(); return true end
        if gui.pick_node(st.ok, action.x, action.y) then submit(); return true end
        for i, a in ipairs(st.avatars) do
            if gui.pick_node(a, action.x, action.y) then st.avatar = i; st.render(); return true end
        end
    end
    return true
end

return M
