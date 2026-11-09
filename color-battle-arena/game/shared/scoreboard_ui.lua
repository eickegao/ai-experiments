-- shared/scoreboard_ui.lua — 单游戏分数榜面板（2026-10-07 用户定案，Flash Linez 结算页 RANK 钮打开；别的游戏可照接）
-- 三个页签：MY BEST（本地最高 10 局）/ THIS WEEK / ALL TIME（服务端每人最高分 top 30 + 我的名次）。
-- 底栏：THIS WEEK / ALL TIME 页签显示本局在该榜排第几（POST /api/score 的回包）；没有本局（零分/非结算页进来）就显示我的最高分名次。
-- 贴图来自 shared/scoreboard.atlas（面板/角标/头像/国旗的子集，别把 4096² 的大厅图集拖进网页包；宿主 gui 要声明 texture "scoreboard_atlas"：rank_frame/rank_inner/row_white/play_tri/trophy_laurel/badge_1..3/avatar_n/flag_CC/btn_x_blue/btn_blue/btn_grey/input_box/tag_your_rank）。
-- 节点都是顶级（屏幕坐标 1080×1920 中心 540,960），画在宿主 root 之上。
local ranking_ui = require("shared.ranking_ui")
local scores = require("shared.scores")
local earn = require("shared.earn")
local T = require("shared.i18n").t
local layout = require("shared.layout")
local M = {}

local ATLAS = "scoreboard_atlas"
local WHITE, NAVY, HEAD, GOLD = vmath.vector4(1, 1, 1, 1), vmath.vector4(0.16, 0.2, 0.42, 1), vmath.vector4(0.35, 0.4, 0.6, 1), vmath.vector4(1, 0.85, 0.2, 1)
local ROW_H = 96
local TABS = { { "mine", function() return T("MY BEST") end }, { "week", function() return T("THIS WEEK") end }, { "all", function() return T("ALL TIME") end } }   -- 名字延迟求值：模块加载时语言表可能还没 init
local st = nil

local function box(parent, x, y, w, h, tex, slice, col)
    local n = gui.new_box_node(vmath.vector3(x, y, 0), vmath.vector3(w, h, 0))
    if tex then gui.set_texture(n, ATLAS); pcall(gui.play_flipbook, n, hash(tex)) end
    if slice then gui.set_slice9(n, vmath.vector4(slice, slice, slice, slice)) end
    if col then gui.set_color(n, col) end
    if parent then gui.set_parent(n, parent) end
    return n
end
local function label(parent, s, x, y, sc, col, pivot, font)
    local t = gui.new_text_node(vmath.vector3(x, y, 0), s)
    gui.set_font(t, font or st.font); gui.set_scale(t, vmath.vector3(sc, sc, 1)); gui.set_color(t, col or WHITE)
    if pivot then gui.set_pivot(t, pivot) end
    if parent then gui.set_parent(t, parent) end
    return t
end
local function fmt(n) return ranking_ui.fmt_points(n) end

function M.is_open() return st ~= nil end

--- silent = 不触发 on_close（WATCH 进回看、宿主自己收场时用）
function M.close(silent)
    if not st then return end
    pcall(gui.delete_node, st.dim)
    local cb = st.on_close
    st = nil
    if cb and not silent then cb() end
end

-- ---------- 列表 ----------
local function clear_rows()
    for _, r in ipairs(st.rows) do pcall(gui.delete_node, r) end
    st.rows, st.content_h, st.plays = {}, 0, {}
end
local function set_scroll(s)
    st.scroll = math.max(0, math.min(math.max(0, st.content_h - st.list_h), s))
    gui.set_position(st.content, vmath.vector3(0, st.list_h / 2 + st.scroll, 0))
end
local ROW_TINT = { vmath.vector4(1, 0.93, 0.55, 1), vmath.vector4(0.84, 0.91, 1, 1), vmath.vector4(1, 0.87, 0.7, 1) }   -- 金/银/铜（用户 2026-10-08 设计稿）
local ROW_MINE, ROW_PLAIN = vmath.vector4(1, 0.97, 0.8, 1), vmath.vector4(0.97, 0.985, 1, 1)
local function add_row(rank, mine, build)
    local y = -st.content_h - ROW_H / 2
    local r = box(st.content, 0, y, 900, ROW_H - 8, "row_white", 24, ROW_TINT[rank] or (mine and ROW_MINE) or ROW_PLAIN)
    build(r)
    st.content_h = st.content_h + ROW_H
    st.rows[#st.rows + 1] = r
end
local function rank_badge(parent, rank, x)
    if rank <= 3 then box(parent, x, 0, 60, 63, "badge_" .. rank) else label(parent, "#" .. rank, x, 0, 0.62, NAVY) end
end
local function flag(parent, cc, x, y)
    box(parent, x, y, 66, 55, ranking_ui.flag_image(cc, st.viewer_cc, st.territory))
end

local function set_tab(which)
    st.tab = which
    for _, t in ipairs(TABS) do
        local active = (t[1] == which)
        gui.play_flipbook(st.tabs[t[1]].bg, hash(active and "btn_blue" or "btn_grey"))
        gui.set_color(st.tabs[t[1]].txt, active and WHITE or NAVY)
    end
    clear_rows()
    gui.set_text(st.status, "")
    gui.set_text(st.me_rank, ""); gui.set_text(st.me_score, ""); gui.set_enabled(st.me_flag, false)
    if which == "mine" then
        local l = st.local_list or {}
        if #l == 0 then gui.set_text(st.status, T("No games yet")) end
        for i, e in ipairs(l) do
            add_row(i, false, function(r)
                rank_badge(r, i, -400)
                label(r, fmt(e.score), -320, 0, 0.78, NAVY, gui.PIVOT_W)
                label(r, st.local_detail and st.local_detail(e) or ((e.cleared or 0) .. " balls"), 90, 0, 0.5, HEAD, gui.PIVOT_W)   -- 明细列：宿主可传 local_detail(e)（CLASHDOZ 显示名次，2026-10-26）
                label(r, e.date or "", 420, 0, 0.5, HEAD, gui.PIVOT_E)
            end)
        end
        local tg = st.this_game
        if tg then   -- 有本局：底栏显示本局在本地榜的名次（用户 2026-10-08：不是最好成绩）
            gui.set_text(st.me_tag, T("YOU"))
            gui.set_text(st.me_rank, tg.rank_local and ("#" .. tg.rank_local) or "—")
            gui.set_text(st.me_score, fmt(tg.score))
        else
            gui.set_text(st.me_tag, T("YOUR BEST"))
            gui.set_text(st.me_score, (#l > 0) and fmt(l[1].score) or "0")
        end
        set_scroll(0)
        return
    end
    gui.set_text(st.me_tag, st.this_game and T("THIS GAME") or T("YOU"))
    gui.set_text(st.status, T("Loading..."))
    local want = st.tab
    scores.fetch_board(st.game, which, function(d)
        if not st or st.tab ~= want then return end
        if not d then gui.set_text(st.status, T("No connection")); return end
        st.viewer_cc = earn.state.country or st.viewer_cc
        gui.set_text(st.status, (#(d.top or {}) == 0) and T("No scores yet — play to be first!") or "")
        for i, row in ipairs(d.top or {}) do
            add_row(row.rank, row.mine, function(r)
                rank_badge(r, row.rank, -400)
                box(r, -318, 4, 70, 72, "avatar_" .. (row.avatar or 1))
                label(r, row.nickname or "", -262, 0, 0.64, NAVY, gui.PIVOT_W, st.name_font)
                label(r, fmt(row.score), 150, 0, 0.66, NAVY, gui.PIVOT_E)
                flag(r, row.country, 230, 0)
                -- 播放钮：有录制的条目（用户 2026-10-08：看看别人是怎么打的）
                if row.share_id and st.on_play then
                    local pb = box(r, 350, 0, 150, 70, "btn_blue", 22)
                    box(pb, -46, 1, 26, 26, "play_tri")
                    label(pb, T("WATCH"), 14, 2, 0.44, WHITE)
                    st.plays[#st.plays + 1] = { node = pb, id = row.share_id }
                end
            end)
        end
        set_scroll(0)
        local tg = st.this_game
        local rank, score
        if tg then
            -- 底栏 = 本局在这个页签里排第几（用户 2026-10-08：只显示这次拿了第几，不要 OF 总数）
            rank, score = (which == "week") and tg.rank_week or tg.rank_all, tg.score
        else
            rank, score = d.me and d.me.rank, d.me and d.me.score
        end
        gui.set_text(st.me_rank, rank and ("#" .. fmt(rank)) or "—")
        gui.set_text(st.me_score, score and fmt(score) or "")
        gui.set_enabled(st.me_flag, score ~= nil)
        if score then gui.play_flipbook(st.me_flag, ranking_ui.flag_image(st.viewer_cc, st.viewer_cc, st.territory)) end
    end)
end

--- opts = { game, font, name_font, local_list, this_game = { score, rank_local, rank_week, rank_all } | nil, on_close,
---          on_play(share_id) = 榜上条目的播放钮（有录制的条目才有钮；传了才显示） }
function M.open(opts)
    M.close()
    st = { game = opts.game, font = opts.font or "game_font", name_font = opts.name_font or opts.font or "game_font",
           local_list = opts.local_list or {}, local_detail = opts.local_detail, on_close = opts.on_close, on_play = opts.on_play, rows = {}, content_h = 0, scroll = 0, tabs = {}, plays = {},
           viewer_cc = earn.state.country, territory = nil }
    pcall(function() st.territory = sys.get_sys_info().territory end)
    local extra = layout.extra()
    st.dim = box(nil, 540, 960, 1080, 1920 + 2 * extra, nil, nil, vmath.vector4(0, 0, 0, 0.72)); layout.fill(st.dim)   -- 宽屏（iPad）也铺满
    -- 用户 2026-10-08 设计稿：蓝色外框，顶部 170 px 露出来就是标题栏（奖杯 + 白字带影），下面一块浅色圆角内容框
    local panel = box(st.dim, 0, -10, 1000, 1700, "rank_frame", 48)
    st.panel = panel
    box(panel, 0, -98, 970, 1495, "rank_inner", 40)
    box(panel, -340, 762, 150, 130, "trophy_laurel")
    -- 标题居中、更大、粗体（字体只有 Medium：白字两层错位 3px 叠出粗体，下面再压一层深蓝影；用户 2026-10-08）
    label(panel, T("RANKING"), 8, 752, 1.85, vmath.vector4(0.12, 0.35, 0.72, 1))
    label(panel, T("RANKING"), 3, 760, 1.85, WHITE)
    label(panel, T("RANKING"), 0, 760, 1.85, WHITE)
    box(panel, 462, 802, 96, 98, "btn_x_blue")   -- 收进框角（用户 2026-10-08）
    st.close_btn = box(panel, 462, 802, 200, 200, nil, nil, vmath.vector4(0, 0, 0, 0))
    -- 本局排第几：不再在标题下单独一行，改在底栏按当前页签显示（用户 2026-10-08）
    local tg = opts.this_game
    if tg and (tonumber(tg.score) or 0) <= 0 then tg = nil end   -- 零分不上榜，也不提这一局
    st.this_game = tg
    -- 页签
    for i, t in ipairs(TABS) do
        local x = (i - 2) * 300
        local bg = box(panel, x, 560, 280, 86, "btn_grey", 22)
        local txt = label(bg, t[2](), 0, 2, 0.52, NAVY)
        st.tabs[t[1]] = { bg = bg, txt = txt }
    end
    st.status = label(panel, "", 0, 440, 0.6, HEAD)
    -- 列表裁剪区
    local top_y, bottom_y = 490, -640
    local height = top_y - bottom_y
    st.clip = box(panel, 0, top_y - height / 2, 920, height, nil, nil, vmath.vector4(0, 0, 0, 0))
    gui.set_clipping_mode(st.clip, gui.CLIPPING_MODE_STENCIL); gui.set_clipping_visible(st.clip, false)
    st.content = box(st.clip, 0, height / 2, 920, 10, nil, nil, vmath.vector4(0, 0, 0, 0))
    st.list_h = height
    -- 底部"我"
    local bar = box(panel, 0, -740, 920, 96, "input_box", 24)
    st.me_tag = label(bar, T("YOU"), -400, 0, 0.5, HEAD, gui.PIVOT_W)
    st.me_rank = label(bar, "", -180, 0, 0.7, NAVY, gui.PIVOT_W)
    st.me_score = label(bar, "", 320, 0, 0.7, NAVY, gui.PIVOT_E)
    st.me_flag = box(bar, 400, 0, 66, 55, "flag_US"); gui.set_enabled(st.me_flag, false)
    set_tab(opts.tab or ((tg and tg.rank_week) and "week" or "mine"))
end

--- 面板打开时宿主把 touch 的 pressed/移动/released 全交过来；返回 true = 已吞
function M.on_input(action)
    if not st then return false end
    if action.pressed then
        st.drag = { y0 = action.y, s0 = st.scroll or 0, moved = false }
        return true
    elseif st.drag and not action.released then
        local dy = action.y - st.drag.y0
        if math.abs(dy) > 20 then st.drag.moved = true end
        if st.drag.moved then set_scroll(st.drag.s0 + dy) end
        return true
    elseif action.released then
        local moved = st.drag and st.drag.moved
        st.drag = nil
        if moved then return true end
        if gui.pick_node(st.close_btn, action.x, action.y) then M.close(); return true end
        for _, pbtn in ipairs(st.plays) do
            if gui.pick_node(pbtn.node, action.x, action.y) then
                local cb, id = st.on_play, pbtn.id
                M.close(true)
                cb(id)
                return true
            end
        end
        for _, t in ipairs(TABS) do
            if gui.pick_node(st.tabs[t[1]].bg, action.x, action.y) then
                if st.tab ~= t[1] then set_tab(t[1]) end
                return true
            end
        end
        if not gui.pick_node(st.panel, action.x, action.y) then M.close() end
        return true
    end
    return true
end

return M
