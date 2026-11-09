-- shared/ranking_ui.lua
-- 周榜 / 国家榜 / 规则 / 上周领奖 四个全屏页（spec 3.3、3.4、2.5）。纯动态建节点在 ranking.gui 的 root 下；
-- 页面打开期间大厅 gui 通过 M.is_open() 跳过自己的输入处理；本模块不碰输入焦点（焦点按游戏对象算，
-- release 会把同一对象上大厅 gui 的焦点一起放掉——2026-10-01 真机：关掉周榜后整个大厅不响应）。关闭时通知大厅 ranking_closed。
-- 美术占位：奖杯/地球用文字，国旗用国家码胶囊（用户美术到位后换图）。
local earn = require("shared.earn")
local T = require("shared.i18n").t
local layout = require("shared.layout")   -- 底幕铺满整屏（iPad 2026-10-19）
local M = {}
local WHITE = vmath.vector4(1, 1, 1, 1)
local NAVY = vmath.vector4(0.16, 0.2, 0.45, 1)
local GOLD = vmath.vector4(1, 0.82, 0.2, 1)
local DIM = vmath.vector4(0.05, 0.08, 0.2, 0.96)
local open_flag = false
function M.is_open() return open_flag end

-- ---------- 纯函数（可单测） ----------
function M.fmt_points(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
function M.fmt_rank(r) return r and ("#" .. r) or "—" end
function M.countdown(end_epoch, now)
    local left = math.max(0, math.floor((end_epoch or 0) - (now or os.time())))
    local d, h, m = math.floor(left / 86400), math.floor(left % 86400 / 3600), math.floor(left % 3600 / 60)
    if d > 0 then return d .. "d " .. h .. "h " .. m .. "m" end
    if h > 0 then return h .. "h " .. m .. "m" end
    return m .. "m"
end
function M.change_text(c)
    if not c or c == 0 then return "—" end
    return c > 0 and ("▲ +" .. c) or ("▼ " .. c)
end
function M.rules_text(prize_text, contact_email)
    return table.concat({
        T("WEEKLY RANKING RULES"),
        "",
        T("• Every coin you earn in any game counts as points (purchases excluded)."),
        T("• Check in automatically by playing one game a day. Day 4 doubles and Day 7 triples the coins you earn that day."),
        T("• The week runs Monday 00:00 to Sunday 24:00 in your local time."),
        "• " .. ((prize_text and prize_text ~= "") and prize_text or T("Top 20 win a gift card!")),
        T("• Final results are published every Tuesday. If you finish in the Top 20, email %s within 7 days with your player name and country to claim your prize."):format(contact_email or ""),
        T("• Accounts with suspicious activity are disqualified."),
        T("• This promotion is run by PlayDoz. Apple and Google are not sponsors and are not involved in any way."),
    }, "\n")
end

-- ---------- 节点工具 ----------
local function box(parent, x, y, w, h, tex, slice, col)
    local n = gui.new_box_node(vmath.vector3(x, y, 0), vmath.vector3(w, h, 0))
    if tex then gui.set_texture(n, "dashboard_atlas"); gui.play_flipbook(n, hash(tex)) end
    if slice then gui.set_slice9(n, vmath.vector4(slice, slice, slice, slice)) end
    if col then gui.set_color(n, col) end
    gui.set_parent(n, parent)
    return n
end
local function label(parent, s, x, y, sc, col, pivot, font)
    local t = gui.new_text_node(vmath.vector3(x, y, 0), s)
    gui.set_font(t, font or "system_font"); gui.set_scale(t, vmath.vector3(sc, sc, 1)); gui.set_color(t, col or WHITE)
    if pivot then gui.set_pivot(t, pivot) end
    gui.set_parent(t, parent)
    return t
end
local function pill(parent, cc, x, y)   -- 国旗占位：国家码胶囊
    local p = box(parent, x, y, 92, 44, "btn_grey", 20)
    label(p, cc or "ZZ", 0, 0, 0.5, NAVY)
    return p
end

-- 常见国家名（国旗占位用国家码胶囊；用户美术到位后换图）
local COUNTRY = { US = "USA", CA = "Canada", CN = "China", JP = "Japan", KR = "Korea", GB = "UK", DE = "Germany", FR = "France", IT = "Italy", ES = "Spain",
    BR = "Brazil", MX = "Mexico", AR = "Argentina", CO = "Colombia", CL = "Chile", PE = "Peru", VE = "Venezuela", UY = "Uruguay", EC = "Ecuador", BO = "Bolivia",
    IN = "India", ID = "Indonesia", MY = "Malaysia", PH = "Philippines", SG = "Singapore", TH = "Thailand", VN = "Vietnam", SA = "Saudi Arabia", AE = "UAE", IL = "Israel",
    TR = "Turkey", IR = "Iran", IQ = "Iraq", PK = "Pakistan", BD = "Bangladesh", KZ = "Kazakhstan", UZ = "Uzbekistan", RU = "Russia", UA = "Ukraine", PL = "Poland",
    NL = "Netherlands", BE = "Belgium", CH = "Switzerland", SE = "Sweden", NO = "Norway", DK = "Denmark", FI = "Finland", IE = "Ireland", PT = "Portugal", GR = "Greece",
    CZ = "Czechia", HU = "Hungary", RO = "Romania", BG = "Bulgaria", AT = "Austria", SK = "Slovakia", SI = "Slovenia", RS = "Serbia", HR = "Croatia", MK = "N. Macedonia",
    AU = "Australia", NZ = "New Zealand", ZA = "South Africa", EG = "Egypt", NG = "Nigeria", KE = "Kenya", ET = "Ethiopia", MA = "Morocco", DZ = "Algeria", TN = "Tunisia",
    TW = "Taiwan", HK = "Hong Kong" }
function M.country_name(cc) return COUNTRY[cc or ""] or cc or "—" end

local HEAD = vmath.vector4(0.3, 0.42, 0.65, 1)   -- 列头灰蓝
-- 国旗（用户 2026-10-02 提供 70 面图集，tools/flags_cut.py 切出 flag_<CC>）；没有图的国家用白胶囊 + 国家码
local FLAGS = { TW = true }
for cc in ("US CA CN JP KR GB DE FR IT ES BR MX AR CO CL PE VE UY EC BO IN ID MY PH SG TH VN SA AE IL TR IR IQ PK BD KZ UZ RU UA PL NL BE CH SE NO DK FI IE PT GR CZ HU RO BG AT SK SI RS HR MK AU NZ ZA EG NG KE ET MA DZ TN"):gmatch("%a+") do FLAGS[cc] = true end
-- 旗子选择规则（用户 2026-10-02）：
--  · 国家未知 / 不在旗表内 → PlayDoz 旗 flag_ZZ
--  · 台湾玩家：看榜的人在中国大陆 → 显示 CN 旗；否则显示 TW 旗
--    "在中国大陆" = 当前 IP 国家(viewer，服务端判定) 是 CN  或  手机系统地区(territory，sys.get_sys_info) 是 CN，二者取并集（保守）
function M.flag_image(cc, viewer, territory)
    if cc == "TW" and (viewer == "CN" or (territory or ""):upper() == "CN") then cc = "CN" end
    if not cc or not FLAGS[cc] then cc = "ZZ" end
    return "flag_" .. cc
end
local viewer_cc = nil   -- 看榜者国家（服务端按 IP 判定，随榜单数据回来）
local territory = (sys and sys.get_sys_info and (sys.get_sys_info().territory or "")) or ""   -- 手机系统地区（如 "CN"）
local function flag(parent, cc, x, y)
    local f = { img = box(parent, x, y, 66, 55, "flag_ZZ") }   -- 旗图 84×70
    function f.set(c) gui.play_flipbook(f.img, hash(M.flag_image(c, viewer_cc, territory))) end
    f.set(cc)
    return f
end
local function rank_badge(parent, rank, x)
    if rank <= 3 then box(parent, x, 0, 60, 63, "badge_" .. rank)   -- 用户素材，数字已烘进图
    else label(parent, tostring(rank), x, 0, 0.7, NAVY) end
end

local function clear(self)
    if self.page then pcall(gui.delete_node, self.page.root) end
    self.page = nil
end

-- 页面骨架（示意图 2026-10-02）：半透明压暗 + 浅蓝面板，标题白字居中，左返回钮、右 (i)
local function frame(self, title, with_info)
    clear(self)
    local root = gui.get_node("root")
    gui.set_enabled(root, true)
    local pg = { root = box(root, 0, 0, 1080, 2400, nil, nil, vmath.vector4(0, 0, 0, 0.72)), rows = {}, scroll = 0 }
    layout.fill(pg.root)   -- 宽屏（iPad）也铺满
    pg.panel = box(pg.root, 0, -10, 1000, 1700, "rank_panel", 48)
    local HDR = { ["Weekly Ranking"] = "hdr_weekly", ["Country Ranking"] = "hdr_country" }
    if HDR[title] then   -- 用户横幅（660×106 源图，等比放到 960 宽；返回钮/(i) 已烘在图里，用透明命中框）
        box(pg.panel, 0, 738, 960, 154, HDR[title])   -- 距面板顶 25px；横幅两端的返回箭头/(i) 已抹掉（规则页从打卡卡片的 (i) 进）
    else
        label(pg.panel, title, 0, 780, 1.05, WHITE)
        if with_info then pg.info = box(pg.panel, 430, 780, 72, 72, "icon_info_rank") end
    end
    box(pg.panel, 500, 830, 96, 98, "btn_x_blue")   -- 右上角大叉关闭，与昵称面板一致（用户 2026-10-02）
    pg.back = box(pg.panel, 500, 830, 200, 200, nil, nil, vmath.vector4(0, 0, 0, 0))   -- 命中范围放大到 200×200（用户：常点不中）
    self.page = pg
    open_flag = true
    return pg
end

function M.close(self)
    clear(self)
    gui.set_enabled(gui.get_node("root"), false)
    open_flag = false
    msg.post("#gui", "ranking_closed")
end

-- 可滚动列表：裁剪框 + 内容节点
local ROW_H = 96
local function list(pg, top_y, bottom_y)
    local height = top_y - bottom_y
    pg.clip = box(pg.panel, 0, top_y - height / 2, 920, height, nil, nil, vmath.vector4(0, 0, 0, 0))
    gui.set_clipping_mode(pg.clip, gui.CLIPPING_MODE_STENCIL); gui.set_clipping_visible(pg.clip, false)
    pg.content = box(pg.clip, 0, height / 2, 920, 10, nil, nil, vmath.vector4(0, 0, 0, 0))
    pg.list_h, pg.content_h, pg.scroll = height, 0, 0
end
local function add_row(pg, build)
    local y = -pg.content_h - ROW_H / 2
    local r = box(pg.content, 0, y, 900, ROW_H - 8, "row_cream", 24)
    build(r)
    pg.content_h = pg.content_h + ROW_H
    pg.rows[#pg.rows + 1] = r
end
local function set_scroll(pg, s)
    pg.scroll = math.max(0, math.min(math.max(0, pg.content_h - pg.list_h), s))
    gui.set_position(pg.content, vmath.vector3(0, pg.list_h / 2 + pg.scroll, 0))
end
local function clear_rows(pg)
    for _, r in ipairs(pg.rows) do pcall(gui.delete_node, r) end
    pg.rows, pg.content_h = {}, 0
end
local function col_heads(pg, y, cols)   -- cols = { {text, x, pivot}, ... }
    for _, c in ipairs(cols) do label(pg.panel, c[1], c[2], y, 0.48, HEAD, c[3]) end
end

-- ---------- 周榜 ----------
local function load_weekly(self, scope, country)
    local pg = self.page
    gui.set_text(pg.status, T("Loading..."))
    earn.fetch_ranking(scope, country, function(d)
        if self.page ~= pg then return end
        clear_rows(pg)
        if not d then gui.set_text(pg.status, T("No connection")); return end
        viewer_cc = d.me and d.me.country or viewer_cc
        gui.set_text(pg.status, (#(d.top or {}) == 0) and T("No scores yet this week — play to be first!") or "")
        pg.week_end = d.week_end_epoch
        gui.set_text(pg.prize2, d.prize_text and d.prize_text:gsub("^Top 20 win ", "") or "")
        for _, row in ipairs(d.top or {}) do
            add_row(pg, function(r)
                rank_badge(r, row.rank, -400)
                box(r, -318, 4, 70, 72, "avatar_" .. (row.avatar or 1))
                label(r, row.nickname or "", -262, 0, 0.68, NAVY, gui.PIVOT_W, "name_font")
                label(r, M.fmt_points(row.points), 170, 0, 0.7, NAVY, gui.PIVOT_E)
                flag(r, row.country, 310, 0)
                label(r, (row.country ~= "ZZ") and row.country or "", 400, 0, 0.5, NAVY)
            end)
        end
        set_scroll(pg, 0)
        gui.set_text(pg.me_rank, M.fmt_rank(d.me and d.me.rank))
        gui.set_text(pg.me_pts, M.fmt_points(d.me and d.me.points or 0))
        if d.me then
            gui.play_flipbook(pg.me_avatar, hash("avatar_" .. (d.me.avatar or 1)))
            pg.me_flag.set(d.me.country); gui.set_text(pg.me_cc, (d.me.country ~= "ZZ") and d.me.country or "")
        end
    end)
end

function M.open_weekly(self, scope, country)
    local pg = frame(self, "Weekly Ranking", true)
    -- 奖品卡：紫色，奖杯 + 文案 + 倒计时
    local card = box(pg.panel, 0, 560, 920, 190, "btn_purple", 28)   -- 横幅下沿 661，留 6px
    box(card, -340, 0, 170, 147, "trophy_laurel")
    box(card, 340, 6, 150, 116, "card_amazon")
    local t1 = label(card, T("Top 20 win"), -230, 48, 0.74, WHITE, gui.PIVOT_W)
    pg.prize2 = label(card, T("$5 Gift Card!"), -230, -2, 0.84, GOLD, gui.PIVOT_W)
    pg.timer = label(card, "", -230, -52, 0.48, vmath.vector4(1, 0.95, 0.75, 1), gui.PIVOT_W)
    col_heads(pg, 420, { { "#", -400 }, { T("Player"), -262, gui.PIVOT_W }, { T("Points"), 170, gui.PIVOT_E }, { T("Country"), 350 } })
    list(pg, 392, -560)
    pg.status = label(pg.panel, "", 0, 200, 0.6, NAVY)
    -- 底部 Your Rank 条
    local bar = box(pg.panel, 0, -700, 920, 190, "input_box", 24)
    box(bar, -340, 78, 150, 57, "tag_your_rank")
    pg.me_rank = label(bar, "—", -360, -14, 1.0, NAVY)
    pg.me_avatar = box(bar, -190, -8, 84, 86, "avatar_1")
    label(bar, T("You"), -110, -14, 0.74, NAVY, gui.PIVOT_W)
    pg.me_pts = label(bar, "0", 170, -14, 0.8, NAVY, gui.PIVOT_E)
    pg.me_flag = flag(bar, "ZZ", 310, -14)
    pg.me_cc = label(bar, "", 400, -14, 0.5, NAVY)
    pg.kind, pg.scope, pg.country = "weekly", scope or "global", country
    load_weekly(self, pg.scope, pg.country)
end

-- ---------- 国家榜 ----------
function M.open_country(self)
    local pg = frame(self, "Country Ranking", true)
    local card = box(pg.panel, 0, 560, 920, 190, "btn_blue", 28)
    box(card, -340, 0, 180, 142, "globe_laurel")
    label(card, T("Which country is #1?"), -200, 48, 0.78, WHITE, gui.PIVOT_W)
    label(card, T("Total points from all players"), -200, 0, 0.5, WHITE, gui.PIVOT_W)
    pg.timer = label(card, "", -200, -52, 0.5, vmath.vector4(1, 0.95, 0.75, 1), gui.PIVOT_W)
    col_heads(pg, 420, { { "#", -400 }, { T("Country"), -262, gui.PIVOT_W }, { T("Total Points"), 170, gui.PIVOT_E }, { T("Change"), 390 } })
    list(pg, 392, -790)
    pg.status = label(pg.panel, T("Loading..."), 0, 200, 0.6, NAVY)
    pg.kind = "country"
    earn.fetch_countries(function(d)
        if self.page ~= pg then return end
        if not d then gui.set_text(pg.status, T("No connection")); return end
        local rows = d.rows or {}
        viewer_cc = d.me_country or viewer_cc
        gui.set_text(pg.status, (#rows == 0) and T("No scores yet this week") or "")
        pg.week_end = d.week_end_epoch
        for _, row in ipairs(rows) do
            add_row(pg, function(r)
                rank_badge(r, row.rank, -400)
                flag(r, row.country, -310, 0)
                label(r, M.country_name(row.country) .. (row.country == d.me_country and "  (you)" or ""), -250, 0, 0.7, NAVY, gui.PIVOT_W)
                label(r, M.fmt_points(row.points), 170, 0, 0.7, NAVY, gui.PIVOT_E)
                local ch = row.change or 0
                if ch == 0 then box(r, 390, 0, 40, 21, "arrow_flat")
                else
                    box(r, 360, 0, 36, 34, ch > 0 and "arrow_up" or "arrow_down")
                    label(r, (ch > 0 and "+" or "") .. ch, 392, 0, 0.56, ch > 0 and vmath.vector4(0.1, 0.6, 0.2, 1) or vmath.vector4(0.85, 0.2, 0.2, 1), gui.PIVOT_W)
                end
            end)
        end
        set_scroll(pg, 0)
    end)
end

-- ---------- 规则 / 领奖 ----------
function M.open_rules(self)
    local pg = frame(self, T("How it works"), false)
    local t = label(pg.panel, M.rules_text(earn.state.prize_text or "", earn.state.contact_email or "rewards@playdoz.com"), -440, 680, 0.58, NAVY, gui.PIVOT_NW)
    gui.set_line_break(t, true); gui.set_size(t, vmath.vector3(880, 1500, 0))
    pg.kind = "rules"
end

function M.open_prize(self, info)
    info = info or {}
    local pg = frame(self, T("Last Week's Result"), false)
    label(pg.panel, T("You finished %s!"):format(M.fmt_rank(info.rank)), 0, 560, 1.3, GOLD)
    label(pg.panel, T("%s points"):format(M.fmt_points(info.points)), 0, 470, 0.8, NAVY)
    label(pg.panel, info.prize or "", 0, 360, 0.9, NAVY)
    local t = label(pg.panel, T("To claim: email %s\nwith your player name and country within 7 days."):format(info.contact_email or ""), 0, 220, 0.6, NAVY)
    gui.set_line_break(t, true); gui.set_size(t, vmath.vector3(880, 300, 0))
    pg.kind = "prize"
end

-- ---------- 每帧 / 输入 ----------
function M.update(self, dt)
    local pg = self.page
    if not pg or not pg.timer or not pg.week_end then return end
    pg.t = (pg.t or 1) + dt
    if pg.t >= 1 then pg.t = 0; gui.set_text(pg.timer, T("Ends in %s"):format(M.countdown(pg.week_end, os.time()))) end
end

function M.on_input(self, action_id, action)
    local pg = self.page
    if not pg then return false end
    if action_id ~= hash("touch") then return true end
    if action.pressed then
        if gui.pick_node(pg.back, action.x, action.y) then M.close(self); return true end   -- 按下即关
        pg.drag = { y0 = action.y, s0 = pg.scroll or 0, moved = false }
    elseif pg.drag and not action.released then
        local dy = action.y - pg.drag.y0
        if math.abs(dy) > 20 then pg.drag.moved = true end
        if pg.clip and pg.drag.moved then set_scroll(pg, pg.drag.s0 + dy) end
    elseif pg.drag and action.released then
        local moved = pg.drag.moved; pg.drag = nil
        if not moved then
            if gui.pick_node(pg.back, action.x, action.y) then M.close(self); return true end
            if pg.info and gui.pick_node(pg.info, action.x, action.y) then M.open_rules(self); return true end
            if pg.kind == "rules" or pg.kind == "prize" then M.close(self); return true end
        end
    end
    return true
end

return M
