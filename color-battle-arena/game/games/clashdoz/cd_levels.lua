-- games/clashdoz/cd_levels.lua — CLASHDOZ 关卡表。
-- 2026-11-03 用户重定（见 M.LEVELS 上方）：100 关全部比最后面积；关里没有任何挡球的东西；3～10 队（最多 9 个电脑）；
--   技能每次进关随机发（我方也随机，M.roll）、全桌打散、减速最多一个电脑有；关与关只靠人数和棋盘形状区分。
--   2026-11-02 那版的竞速 / 染区 / 对决关（M.RACES / M.ZONES / M.DUELS）和地形墙库暂时不进关卡表，代码留着。
-- 一关 = { n 队数, time 秒, shape 棋盘形状, bases 出生区 {x, y, r}（第 1 个 = 玩家）, board 棋盘底色 }
-- 坐标单位 = 格（0..32，格中心 i-0.5）。shape 外的格子是"空洞"（grid=false，当墙）；shape 内不在任何出生区里的格子是中立（grid=0）。
local M = {}
local GRID = 32
local CX = GRID / 2

local SHAPES = {
    square  = function() return function() return true end end,
    circle  = function(p) return function(x, y) local dx, dy = x - CX, y - CX; return dx * dx + dy * dy <= p.r * p.r end end,
    diamond = function(p) return function(x, y) return math.abs(x - CX) + math.abs(y - CX) <= p.r end end,
    ring    = function(p) return function(x, y) local d2 = (x - CX) ^ 2 + (y - CX) ^ 2; return d2 <= p.ro * p.ro and d2 >= p.ri * p.ri end end,
    octagon = function(p) return function(x, y) return math.abs(x - CX) + math.abs(y - CX) <= p.k end end,
    -- 2026-11-03 新形状（关卡只靠形状和人数区分）：box 小方盘（半边 h）、hexagon 平顶六边形（外接半径 r）、oval 横椭圆（半轴 a, b）、squircle 圆角方（|dx|^4 + |dy|^4 ≤ r^4）
    box     = function(p) return function(x, y) return math.abs(x - CX) <= p.h and math.abs(y - CX) <= p.h end end,
    hexagon = function(p) return function(x, y) local dx, dy = math.abs(x - CX), math.abs(y - CX); return dy <= p.r * 0.866 and dx <= p.r - dy * 0.57735 end end,
    oval    = function(p) return function(x, y) local dx, dy = (x - CX) / p.a, (y - CX) / p.b; return dx * dx + dy * dy <= 1 end end,
    squircle = function(p) return function(x, y) local dx, dy = x - CX, y - CX; return dx ^ 4 + dy ^ 4 <= p.r ^ 4 end end,
}

local function around(cx, cy, rad, n, r, a0)   -- 环上均匀 n 个出生区
    local t = {}
    for k = 0, n - 1 do local a = (a0 or 0) + k * 2 * math.pi / n; t[#t + 1] = { cx + rad * math.cos(a), cy + rad * math.sin(a), r } end
    return t
end
local function concat(a, b) local t = {}; for _, v in ipairs(a) do t[#t + 1] = v end; for _, v in ipairs(b) do t[#t + 1] = v end; return t end

-- 2026-11-01 用户重定关卡：三种过关方式（area 占地最多 / zone 把目标区全染成自己的 / race 先到星星）、最多 4 色、
-- 全盘占满不留白（fill = true：每个格归最近的出生区）、棋盘上有装置：walls 墙（空洞，把棋盘隔成几间）、
-- portals 传送阵（成对，任何一方的球踩到就传到另一端）、boosts 加速装置（踩到的球自己提速）。
-- goal = { kind = "area" } | { kind = "zone", rect = {i0, j0, i1, j1} } | { kind = "race", at = {i, j} }（格坐标 1..32）
-- untimed = true：不计时（染区关，用户 2026-11-02：占领住就过，不用时间）——sim 倒计时无限、顶上不画数字，什么时候染满什么时候结束（电脑先染满 = 输）
-- track = true：跑道关（全盘跑道格 config.TRACK，不挡球不变色、禁技能，bases 只当出生点，全队同一入口）
M.RACE_GUARD = 3.2   -- 竞速关星星周围中立圈半径（格）
local function rect(i0, j0, i1, j1) return { i0, j0, i1, j1 } end
local AREA, SQ = { kind = "area" }, { kind = "square" }

-- 接力关的一盘：{ spawns = { {i,j} 每队一个（不够按队号轮用）}, exits = { {i,j} 任一个踩到都切下一盘 }, walls 或 open（跑道矩形并集，见下）, boosts }
-- shared(spawn, exit, walls, boosts) 一个起点一个出口（sim 支持多起点/多出口，暂没关卡用）
local function shared(spawn, exit, walls, boosts) return { spawns = { spawn }, exits = exit and { exit } or nil, walls = walls, boosts = boosts } end
-- 单人限时竞速（用户 2026-11-02：不需要对手，限时内到星星就算过；形状尽量怪、不放加速）：
local SNAKE_H = { rect(1, 6, 26, 6), rect(7, 11, 32, 11), rect(1, 16, 26, 16), rect(7, 21, 32, 21), rect(1, 26, 26, 26) }   -- 横向长蛇：五道横墙左右交替留口，左下进左上出
local SNAKE_V = { rect(6, 1, 6, 26), rect(11, 7, 11, 32), rect(16, 1, 16, 26), rect(21, 7, 21, 32), rect(26, 1, 26, 26) }   -- 竖向长蛇：五道竖墙上下交替留口，左下进右下出
local RING = { rect(6, 6, 27, 6), rect(6, 27, 13, 27), rect(20, 27, 27, 27), rect(6, 6, 6, 27), rect(27, 6, 27, 27) }   -- 方环：只有顶上一个口，外面绕到顶再进中心
local S_WALLS = { rect(1, 8, 24, 9), rect(9, 16, 32, 17), rect(1, 24, 24, 25) }   -- 三道横墙的 S 形赛道（左上进右下出）
local MAZE_WALLS = { rect(8, 8, 24, 8), rect(8, 24, 13, 24), rect(20, 24, 24, 24), rect(8, 8, 8, 24), rect(24, 8, 24, 24),   -- 外框顶缺口 i 14..19
                     rect(12, 12, 20, 12), rect(12, 20, 20, 20), rect(12, 12, 12, 20), rect(20, 12, 20, 13), rect(20, 19, 20, 20) }   -- 内框右缺口 j 14..18；中心 (16,16)
-- 单盘怪形赛道（用户 2026-11-02：先给几个竞速关看看）：stage.open = 跑道矩形并集，其余全是墙——螺旋 / 楼梯 / 斜带这种形状写"跑道在哪"比写墙直观
local function clamp(r) return { math.max(1, r[1]), math.max(1, r[2]), math.min(GRID, r[3]), math.min(GRID, r[4]) } end
local function spiral(w, gap)   -- 宽 w 的跑道从左下沿外圈顺时针（右 → 上 → 左 → 再往里）一圈圈绕到中心
    local p, t = w + gap, {}
    local x0, y0, x1, y1, k = 1, 1, GRID, GRID, 0
    while x1 - x0 + 1 >= w and y1 - y0 + 1 >= w do
        t[#t + 1] = rect(k == 0 and x0 or x0 - p, y0, x1, y0 + w - 1)   -- 底边（第 2 圈起从上一圈左边的底端接过来）
        if y1 - y0 + 1 >= 2 * w + gap then
            t[#t + 1] = rect(x1 - w + 1, y0, x1, y1)      -- 右边
            t[#t + 1] = rect(x0, y1 - w + 1, x1, y1)      -- 顶边
            t[#t + 1] = rect(x0, y0 + p, x0 + w - 1, y1)  -- 左边（下端留一格墙，不和本圈底边接通）
        end
        x0, y0, x1, y1, k = x0 + p, y0 + p, x1 - p, y1 - p, k + 1
    end
    return t
end
local function stairs(w, run)   -- 宽 w 的楼梯：横 run 格、竖 run 格交替，从左下爬到右上
    local t, x, y = {}, 1, 1
    while x <= GRID and y <= GRID do
        t[#t + 1] = clamp(rect(x, y, x + run + w - 1, y + w - 1))
        t[#t + 1] = clamp(rect(x + run, y, x + run + w - 1, y + run + w - 1))
        x, y = x + run, y + run
    end
    return t
end
local function xband(h)   -- 两条斜带交叉成 X：|i-j| <= h 与 |i+j-33| <= h（锯齿边，球会蹦）
    local t = {}
    for j = 1, GRID do t[#t + 1] = clamp(rect(j - h, j, j + h, j)); t[#t + 1] = clamp(rect(GRID + 1 - j - h, j, GRID + 1 - j + h, j)) end
    return t
end
-- 2026-11-02 用户试玩：窄道太难、球控不住 → 跑道一律至少 4 格宽（原来 3 格、漏斗关最窄 1 格）
local LAP = { rect(1, 1, 32, 4), rect(29, 1, 32, 32), rect(1, 29, 32, 32), rect(1, 7, 4, 32) }   -- 绕场长条：宽 4 沿四边一整圈，左边下端堵死（星星在左边尽头 (2,12)，再往下是缓冲死胡同）
local ZIGZAG = { rect(1, 1, 32, 6), rect(29, 7, 32, 7), rect(1, 8, 32, 12), rect(1, 13, 4, 13), rect(1, 14, 32, 17), rect(29, 18, 32, 18), rect(1, 19, 32, 22), rect(1, 23, 4, 23), rect(1, 24, 32, 27) }   -- 折返跑：五条横道宽 6 → 5 → 4 → 4 → 4，接口（宽 4）左右交替
local STAIRS, XBAND, SPIRAL = stairs(4, 5), xband(3), spiral(4, 1)
local function solo(spawn, open, exits) return { spawns = { spawn }, open = open, exits = exits } end
-- 长坡接力迷宫（用户 2026-11-02：棋盘本身很小、跑道很长、有点倾斜、底下滚动；到顶传送到别处；像迷宫有几条路、有的不通要退回来换一条；道别太窄）：
--   view = 16 只露 16×16 格的窗口跟着球滚（格子 / 球原大，用户：不要放大），speed = 0.6 球放慢；slant_snake 生成宽 w、每条爬 rise 行的斜坡蛇道；出口 { i, j, to = 盘号 } 指定去哪一盘，死胡同盘只有一个退回岔口的口
local function slant_snake(w, rise, legs)   -- 返回 open 矩形表 + 最后一条道终点侧的行区间 {y0, y1} 与 x（右端或左端）
    local t, y0 = {}, 1
    local right
    for k = 1, legs do
        right = (k % 2 == 1)
        for x = 1, GRID do
            local f = right and (x - 1) or (GRID - x)
            local yb = y0 + math.floor(f * rise / (GRID - 1) + 0.5)
            t[#t + 1] = rect(x, yb, x, yb + w - 1)
        end
        if k < legs then   -- 终点侧竖着接到下一条
            local xe0, xe1 = right and (GRID - w + 1) or 1, right and GRID or w
            t[#t + 1] = rect(xe0, y0 + rise, xe1, y0 + rise + w + 1)
            y0 = y0 + rise + w + 1
        end
    end
    return t, y0 + rise, y0 + rise + w - 1, right and GRID - 2 or 3
end
local SLOPE1, S1_Y0, S1_Y1, S1_X = slant_snake(5, 4, 3)   -- 三条斜坡，终点在右上
local SLOPE2, S2_Y0, S2_Y1, S2_X = slant_snake(5, 4, 2)   -- 两条斜坡，终点在左上
local S1_EXIT = { S1_X, math.floor((S1_Y0 + S1_Y1) / 2) }
local S2_STAR = { S2_X, math.floor((S2_Y0 + S2_Y1) / 2) }
local HUB = { rect(14, 1, 18, 16), rect(3, 12, 30, 16), rect(3, 12, 7, 28), rect(26, 12, 30, 28), rect(14, 12, 18, 30) }   -- 三叉岔口：进来往上，左 / 中 / 右三条路各一个传送阵
local DEAD_R = { rect(14, 1, 18, 8), rect(14, 6, 26, 10) }   -- 死胡同（往右拐一下就到头，尽头只有退回去的传送阵）
local DEAD_L = { rect(14, 1, 18, 8), rect(6, 6, 18, 10) }
-- ================================================================ 100 关（用户 2026-11-02 口述定案）
-- 每 10 关一组：第 1～9 关 = 7 个占地（比面积，2～4 队）+ 1 个竞速（单人限时跑道）+ 1 个染区（不限时染满目标区），顺序每组不同；
-- 第 10 关 = 1 V 1 对决：我方带什么卡由关卡指定（deck，固定 4 张不能改），敌人卡数相同、等级不超过我方；只有对决关赢了才给技能点（cd_profile.on_win）。
-- 战地 / 染区一律 4 队（用户 2026-11-03：三个人的局面不好；2026-11-02：不要一对一，1 V 1 只在第 10 关）；敌人等级永远封顶到我方（plan.cap / profile.max_level）。
local CIRCLE, DIAMOND, OCT, RINGS = { kind = "circle", r = 15.8 }, { kind = "diamond", r = 15.5 }, { kind = "octagon", k = 24 }, { kind = "ring", ro = 15.8, ri = 6 }
local BOARDS = { { 0.05, 0.05, 0.12 }, { 0.04, 0.08, 0.12 }, { 0.08, 0.05, 0.10 }, { 0.09, 0.04, 0.09 }, { 0.10, 0.05, 0.06 }, { 0.04, 0.07, 0.12 }, { 0.10, 0.06, 0.04 }, { 0.05, 0.08, 0.08 } }
local CROSS = { rect(16, 8, 17, 13), rect(16, 20, 17, 25), rect(8, 16, 13, 17), rect(20, 16, 25, 17) }   -- 十字四短墙（原第 15 关）
local PILLAR = { rect(14, 14, 19, 19) }                                                                   -- 中央方柱
local FOUR = { rect(11, 11, 13, 13), rect(20, 11, 22, 13), rect(11, 20, 13, 22), rect(20, 20, 22, 22) }   -- 四个小方块
local VBARS = { rect(16, 8, 17, 12), rect(16, 21, 17, 25) }                                               -- 上下两竖条
local HBARS = { rect(9, 16, 12, 17), rect(21, 16, 24, 17) }                                               -- 左右两横条
local BEAM_H, BEAM_V = { rect(13, 16, 20, 17) }, { rect(16, 13, 17, 20) }                                 -- 中央横梁 / 竖梁
local FRAME = { rect(10, 10, 14, 10), rect(18, 10, 22, 10), rect(10, 22, 14, 22), rect(18, 22, 22, 22),        -- 方框四边各开一个口
                rect(10, 10, 10, 14), rect(10, 18, 10, 22), rect(22, 10, 22, 14), rect(22, 18, 22, 22) }
local LCORN = { rect(10, 10, 13, 10), rect(10, 10, 10, 13), rect(19, 10, 22, 10), rect(22, 10, 22, 13),         -- 四个 L 形角
                rect(10, 22, 13, 22), rect(10, 19, 10, 22), rect(19, 22, 22, 22), rect(22, 19, 22, 22) }
local XDOTS = { rect(11, 11, 12, 12), rect(20, 20, 21, 21), rect(11, 20, 12, 21), rect(20, 11, 21, 12),         -- 2×2 方块排成 X
                rect(14, 14, 15, 15), rect(17, 17, 18, 18), rect(14, 17, 15, 18), rect(17, 14, 18, 15) }
local BIGPLUS = { rect(16, 10, 17, 22), rect(10, 16, 22, 17) }                                             -- 大十字把中间分成四格
local DIAMOND_W = { rect(16, 9, 17, 10), rect(9, 16, 10, 17), rect(22, 16, 23, 17), rect(16, 22, 17, 23),      -- 菱形一圈 8 个小方块
                    rect(12, 12, 13, 13), rect(19, 19, 20, 20), rect(12, 19, 13, 20), rect(19, 12, 20, 13) }
-- 占地关墙型库（都收在离中心 8 格以内，出生区按半径 ≥ 10 放，球落不进墙里）；前两关不放墙（用户 2026-11-03：地形好看一点）
local WALLSETS = { PILLAR, CROSS, FRAME, FOUR, LCORN, VBARS, XDOTS, HBARS, BIGPLUS, BEAM_H, DIAMOND_W, BEAM_V }

-- ---------------------------------------------------------------- 竞速关 10 个（从易到难，每组一个）
local SLOPE4, S4_Y0, S4_Y1, S4_X = slant_snake(4, 3, 4)   -- 四条宽 4 的斜坡，终点在左上
local S4_STAR = { S4_X, math.floor((S4_Y0 + S4_Y1) / 2) }
-- 限时 = 弱电脑（eager 0.3）12 种子最慢用时再放宽，并在完美跑法用时的 3～16 倍之间（clashdoz_test 守卫）。2026-11-02 校准（完美 / 弱电脑最慢 → 限时）：
--   绕场 4.5 / 17 → 30；楼梯 2.6 / 24 → 25；X 2.3 / 24 → 35；折返 6.9 / 31 → 90；螺旋 8.3 / 39 → 90；长坡迷宫 17.1 / 51 → 150（用户试玩后"时间再给一点"，全部放宽过一轮）
M.RACES = {
    -- R1 绕场长条：宽 4 的跑道沿四边绕一整圈，左边下端堵死 → 只能往右、上、左绕回来，星星在左边尽头
    { n = 1, time = 30, shape = SQ, track = true, goal = { kind = "race", at = { 2, 12 } }, bases = { { 2, 2, 1.5 } }, board = BOARDS[1], stages = { solo({ 2, 2 }, LAP) } },
    -- R2 楼梯：宽 4、每级 5 格的楼梯从左下爬到右上，12 个直角
    { n = 1, time = 25, shape = SQ, track = true, goal = { kind = "race", at = { 31, 31 } }, bases = { { 2, 2, 1.5 } }, board = BOARDS[6], stages = { solo({ 2, 2 }, STAIRS) } },
    -- R3 X 斜道：两条锯齿斜带（横向 7 格宽）交叉，左下进、右下出（另两条臂是死胡同）
    { n = 1, time = 35, shape = SQ, track = true, goal = { kind = "race", at = { 31, 2 } }, bases = { { 2, 2, 1.5 } }, board = BOARDS[3], stages = { solo({ 2, 2 }, XBAND) } },
    -- R4 折返跑：五条横道（6 → 5 → 4 → 4 → 4 格宽），接口左右交替，星星在最上一条的右端
    { n = 1, time = 90, shape = SQ, track = true, goal = { kind = "race", at = { 30, 26 } }, bases = { { 2, 3, 1.5 } }, board = BOARDS[4], stages = { solo({ 2, 3 }, ZIGZAG) } },
    -- R5 螺旋：宽 4 的跑道从左下绕三圈到中心
    { n = 1, time = 90, shape = SQ, track = true, goal = { kind = "race", at = { 12, 21 } }, bases = { { 2, 2, 1.5 } }, board = BOARDS[5], stages = { solo({ 2, 2 }, SPIRAL) } },
    -- R6 两盘叠加：第 1 盘横向长蛇（左下进、左上出口）→ 第 2 盘三层迷宫到正中的星星
    { n = 1, time = 90, shape = SQ, track = true, goal = { kind = "race", at = { 16, 16 } }, bases = { { 3, 3, 1.5 } }, board = BOARDS[1],
      stages = { shared({ 3, 3 }, { 3, 30 }, SNAKE_H), shared({ 3, 3 }, nil, MAZE_WALLS) } },
    -- R7 长坡四段（长坡样式再来一关，不带岔路）：四条宽 4 的斜坡蛇道，小窗 16 格跟着滚、球速 0.6
    { n = 1, time = 90, shape = SQ, track = true, view = 16, speed = 0.6, goal = { kind = "race", at = S4_STAR }, bases = { { 2, 2, 1.5 } }, board = BOARDS[2], stages = { solo({ 2, 2 }, SLOPE4) } },
    -- R8 绕场 + 螺旋接力：绕场尽头的传送阵把球送进第 2 盘螺旋，再绕到中心
    { n = 1, time = 110, shape = SQ, track = true, goal = { kind = "race", at = { 12, 21 } }, bases = { { 2, 2, 1.5 } }, board = BOARDS[7],
      stages = { solo({ 2, 2 }, LAP, { { 2, 12, to = 2 } }), solo({ 2, 2 }, SPIRAL) } },
    -- R9 长坡接力迷宫（用户 2026-11-02 定案的新竞速样式）：只露 16×16 格的小窗跟着球滚（格子和球不放大）、球速 0.6；三条斜坡 → 三叉岔口（左通终点、中 / 右是死胡同，尽头的传送阵退回岔口）→ 两条斜坡到星星
    { n = 1, time = 150, shape = SQ, track = true, view = 16, speed = 0.6, maze = true, goal = { kind = "race", at = S2_STAR }, goal_stage = 5, bases = { { 2, 3, 1.5 } }, board = BOARDS[1],
      stages = {
        solo({ 2, 3 }, SLOPE1, { { S1_EXIT[1], S1_EXIT[2], to = 2 } }),
        solo({ 16, 2 }, HUB, { { 5, 26, to = 5 }, { 16, 28, to = 3 }, { 28, 26, to = 4 } }),
        solo({ 16, 2 }, DEAD_R, { { 24, 8, to = 2 } }),
        solo({ 16, 2 }, DEAD_L, { { 8, 8, to = 2 } }),
        solo({ 2, 3 }, SLOPE2),
      } },
    -- R10 四盘叠加：竖向长蛇（左下进右下出）→ 方环（外面绕到顶上的口再进中心）→ S 形三横墙（右上出）→ 三层迷宫到星星
    { n = 1, time = 200, shape = SQ, track = true, goal = { kind = "race", at = { 16, 16 } }, bases = { { 3, 3, 1.5 } }, board = BOARDS[6],
      stages = { shared({ 3, 3 }, { 30, 3 }, SNAKE_V), shared({ 3, 3 }, { 16, 16 }, RING), shared({ 3, 3 }, { 29, 29 }, S_WALLS), shared({ 3, 3 }, nil, MAZE_WALLS) } },
}

-- ---------------------------------------------------------------- 染区关 10 个（不限时，染满金框就过；装置只在这里出现）
local function zone(n, shape, r, bases, extra)
    local L = { n = n, time = 60, shape = shape, fill = true, untimed = true, goal = { kind = "zone", rect = r }, bases = bases, board = BOARDS[(n * 3 + r[1]) % #BOARDS + 1] }
    for k, v in pairs(extra or {}) do L[k] = v end
    return L
end
M.ZONES = {   -- 全部 4 队（用户 2026-11-03）
    zone(4, CIRCLE, rect(14, 14, 19, 19), around(CX, CX, 11, 4, 5, -math.pi / 2)),                                                       -- Z1 4 队圆盘十字站位，目标区正中 6×6（第一个染区关，没装置）
    zone(4, SQ, rect(14, 14, 19, 19), { { 6, 6, 6 }, { 26, 26, 6 }, { 6, 26, 6 }, { 26, 6, 6 } }, { boosts = { { 16, 8 }, { 8, 16 }, { 24, 16 }, { 16, 24 } } }),   -- Z2 4 队方盘四角，正中 6×6 + 四边中点加速装置
    zone(4, DIAMOND, rect(14, 14, 18, 18), around(CX, CX, 10, 4, 5, -math.pi / 2), { boosts = { { 16, 10 }, { 10, 16 }, { 22, 16 }, { 16, 22 } } }),   -- Z3 4 队菱形，正中 5×5 + 四加速
    zone(4, OCT, rect(14, 14, 19, 19), around(CX, CX, 11, 4, 5.5, math.pi * 1.25), { portals = { { { 4, 16 }, { 29, 16 } } } }),            -- Z4 4 队八边形对角站位，一对传送阵把左右连起来
    zone(4, SQ, rect(13, 13, 20, 20), { { 6, 6, 6 }, { 26, 26, 6 }, { 6, 26, 6 }, { 26, 6, 6 } }, { portals = { { { 3, 16 }, { 29, 16 } }, { { 16, 3 }, { 16, 29 } } } }),   -- Z5 4 队方盘，两对传送阵连对边
    zone(4, SQ, rect(13, 13, 20, 20), { { 8, 8, 6 }, { 25, 8, 6 }, { 8, 25, 6 }, { 25, 25, 6 } },
         { walls = { rect(1, 16, 32, 17) }, portals = { { { 16, 4 }, { 16, 29 } }, { { 4, 12 }, { 29, 21 } } } }),                       -- Z6 4 队，横墙隔成上下两间（各两家）、目标区横跨墙两边，只能靠传送阵过去
    zone(4, CIRCLE, rect(13, 13, 20, 20), around(CX, CX, 11, 4, 5.5, -math.pi / 2), { boosts = { { 16, 11 }, { 21, 16 }, { 16, 21 }, { 11, 16 } } }),   -- Z7 4 队圆盘，正中 8×8，四个加速装置
    zone(4, OCT, rect(13, 13, 19, 19), around(CX, CX, 11, 4, 5, -math.pi / 2), { portals = { { { 6, 6 }, { 26, 26 } }, { { 6, 26 }, { 26, 6 } } } }),   -- Z8 4 队八边形十字站位，正中 7×7，两对对角传送阵
    zone(4, SQ, rect(13, 13, 20, 20), { { 8, 8, 7 }, { 25, 25, 7 }, { 8, 25, 7 }, { 25, 8, 7 } },
         { walls = { rect(16, 1, 17, 32) }, portals = { { { 8, 16 }, { 25, 16 } }, { { 14, 3 }, { 19, 30 } } }, boosts = { { 12, 12 }, { 21, 21 }, { 12, 21 }, { 21, 12 } } }),   -- Z9 4 队，竖墙 + 两对传送阵 + 四加速
    zone(4, SQ, rect(12, 12, 21, 21), { { 6, 6, 6 }, { 26, 26, 6 }, { 6, 26, 6 }, { 26, 6, 6 } },
         { portals = { { { 3, 16 }, { 29, 16 } }, { { 16, 3 }, { 16, 29 } } }, boosts = { { 9, 16 }, { 23, 16 }, { 16, 9 }, { 16, 23 } } }),   -- Z10 4 队，正中 10×10，两对传送阵 + 四加速
}

-- ---------------------------------------------------------------- 对决关 10 个（每组第 10 关：1 V 1，卡由关卡指定）
local function card(id, level) return { id = id, level = level } end
local function duel(deck, shape, bases, walls, board_i)
    return { n = 2, time = 60, shape = shape, fill = true, goal = AREA, duel = true, deck = deck, bases = bases, walls = walls, board = BOARDS[board_i or 1] }
end
M.DUELS = {   -- 每副 DUEL_CARDS = 4 张，等级逐组抬高
    duel({ card("lightning", 1), card("accel", 1), card("split", 1), card("fire", 1) }, SQ, { { 6, 16, 7 }, { 26, 16, 7 } }, nil, 1),
    duel({ card("fire", 1), card("split", 1), card("giant", 1), card("teleport", 1) }, CIRCLE, { { 16, 6, 6 }, { 16, 26, 6 } }, nil, 2),
    duel({ card("giant", 1), card("teleport", 1), card("lightning", 1), card("bomb", 1) }, DIAMOND, { { 7, 16, 6 }, { 25, 16, 6 } }, nil, 3),
    duel({ card("lightning", 2), card("bomb", 1), card("accel", 2), card("fire", 1) }, SQ, { { 6, 16, 7 }, { 26, 16, 7 } }, PILLAR, 4),
    duel({ card("freeze", 2), card("fire", 2), card("split", 2), card("giant", 1) }, OCT, { { 8, 8, 6 }, { 24, 24, 6 } }, CROSS, 5),
    duel({ card("split", 2), card("accel", 2), card("teleport", 2), card("lightning", 2) }, RINGS, { { 16, 3.5, 4.5 }, { 16, 28.5, 4.5 } }, nil, 6),
    duel({ card("giant", 2), card("lightning", 2), card("bomb", 2), card("freeze", 2) }, SQ, { { 6, 6, 7 }, { 26, 26, 7 } }, VBARS, 7),
    duel({ card("teleport", 2), card("fire", 3), card("accel", 3), card("split", 2) }, CIRCLE, { { 6, 16, 6 }, { 26, 16, 6 } }, PILLAR, 8),
    duel({ card("bomb", 2), card("giant", 3), card("lightning", 3), card("freeze", 2) }, DIAMOND, { { 16, 7, 6 }, { 16, 25, 6 } }, FOUR, 3),
    duel({ card("lightning", 3), card("freeze", 3), card("giant", 3), card("fire", 3) }, SQ, { { 6, 16, 7 }, { 26, 16, 7 } }, CROSS, 5),
}

-- ---------------------------------------------------------------- 100 关（2026-11-03 用户重定：全部比面积、没有挡球的东西、3～10 队、只靠人数和形状区分）
-- 十种棋盘：大盘给人多的关，小盘（box / 小圆 / 小菱 / 横椭圆）只给 ≤ 6 队（人多盘小每队开局不到 40 格）
local BIG_SHAPES = { SQ, CIRCLE, DIAMOND, OCT, RINGS, { kind = "hexagon", r = 16 }, { kind = "squircle", r = 15.5 } }
local SMALL_SHAPES = { { kind = "box", h = 12.5 }, { kind = "circle", r = 12.8 }, { kind = "diamond", r = 13 }, { kind = "oval", a = 16, b = 11.5 } }
local ALL_SHAPES = concat(BIG_SHAPES, SMALL_SHAPES)
M.SHAPES_LIST = ALL_SHAPES
-- 每组 10 关的队数（含玩家）：第 1 组 3～6 慢慢加，第 5 组起出 10 队，后几组 7～10 来回换；相邻两关人数不同
local N_ORDER = {
    { 3, 3, 4, 3, 4, 4, 5, 4, 5, 6 },
    { 4, 5, 4, 6, 5, 6, 4, 7, 6, 7 },
    { 5, 6, 4, 7, 5, 8, 6, 7, 8, 6 },
    { 6, 5, 8, 6, 9, 7, 8, 5, 9, 7 },
    { 7, 8, 6, 9, 7, 10, 8, 6, 9, 10 },
    { 8, 6, 10, 7, 9, 10, 8, 10, 7, 9 },
    { 9, 7, 10, 8, 10, 6, 9, 10, 8, 10 },
    { 8, 10, 9, 7, 10, 9, 10, 8, 10, 9 },
    { 10, 8, 10, 9, 10, 7, 10, 9, 10, 10 },
    { 9, 10, 8, 10, 10, 9, 10, 10, 9, 10 },
}
M.N_ORDER = N_ORDER
--- 出生区（含球的随机落点范围 0.4r + 半格余量）全在棋盘形状里、不碰墙
local function bases_fit(shape, walls, bases)
    local inside = SHAPES[shape.kind](shape)
    for _, b in ipairs(bases) do
        local rr = b[3] * 0.4 + 0.8
        for k = 0, 8 do
            local a = k * math.pi / 4
            local x, y = b[1] + (k == 8 and 0 or rr * math.cos(a)), b[2] + (k == 8 and 0 or rr * math.sin(a))
            if not inside(x, y) then return false end
            local i, j = math.floor(x) + 1, math.floor(y) + 1
            for _, w in ipairs(walls or {}) do if i >= w[1] and j >= w[2] and i <= w[3] and j <= w[4] then return false end end
        end
    end
    return true
end
--- 第 k 关：队数按 N_ORDER，形状按 (k, 组) 轮换（人多只用大盘），出生区绕中心一圈、玩家永远在正下方；横椭圆的圈按长短轴拉开
-- 道具关（大炮 / 放大器 / 士兵，没有球）2026-11-03 深夜用户叫停："逻辑太复杂，还是玩老的用球占面积"——代码全留着（cd_sim build 模式、cd_ai、GUI、准备页），
-- 这个开关打开就回来：偶数关道具关、第 2 关 24×48 的 1v1 场地
M.BUILD_LEVELS = false
-- Boss 关（用户 2026-11-05 夜：每 10 关一场，卡和平时一样，只是地图不平衡——每个电脑开局比玩家多 BOSS_EDGE 的格子；首胜给 2 点）：
--   一般 1 对 1，第 4 / 6 / 8 / 10 组多人；玩家出生区的距离乘权重 w（> 1 → 地盘缩），boss_weights 二分到电脑平均格数 ≈ 玩家 × (1 + edge)；天然已不平衡 ≥ edge 的不加权（weights = nil）
M.BOSS_EDGE = 0.10
local BOSS_N = { 2, 2, 2, 4, 2, 5, 2, 6, 2, 8 }
local function boss_weights(shape, bases, n, edge)
    local inside = SHAPES[shape.kind](shape)
    local function ratio(w)   -- 玩家格数 / 电脑平均格数
        local cnt = {}
        for t = 1, n do cnt[t] = 0 end
        for i = 1, GRID do
            for j = 1, GRID do
                local x, y = i - 0.5, j - 0.5
                if inside(x, y) then
                    local best, bd = 0, math.huge
                    for t, b in ipairs(bases) do
                        local d = ((x - b[1]) ^ 2 + (y - b[2]) ^ 2) * (t == 1 and w or 1)
                        if d < bd then best, bd = t, d end
                    end
                    cnt[best] = cnt[best] + 1
                end
            end
        end
        local foe = 0
        for t = 2, n do foe = foe + cnt[t] end
        return cnt[1] / math.max(1, foe / (n - 1))
    end
    local target = 1 / (1 + edge)
    if ratio(1) <= target then return nil end   -- 用户 2026-11-05 夜：天然已经让电脑多 ≥ 10%（第 80 关 squircle 6 队玩家少 15%）就不再加权；只有本来平衡的才加到 10%
    local lo, hi = 1, 4
    for _ = 1, 20 do local mid = (lo + hi) / 2; if ratio(mid) > target then lo = mid else hi = mid end end
    -- 格子是整数个，二分落点处比例会跳一截（第 80 关 6 队跳到 1.156）：在落点附近扫一圈，取最接近目标的 w
    local best, be = (lo + hi) / 2, math.huge
    for k = -12, 12 do
        local wk = (lo + hi) / 2 + k * 0.004
        if wk >= 1 then local e = math.abs(ratio(wk) - target); if e < be then best, be = wk, e end end
    end
    local w = { best }
    for t = 2, n do w[t] = 1 end
    return w
end
local function area_level(k)
    local blk, pos = math.floor((k - 1) / 10) + 1, (k - 1) % 10 + 1
    local n = N_ORDER[blk][pos]
    local boss = pos == 10
    if boss then n = BOSS_N[blk] end
    if k == 1 then n = 2 end   -- 第 1 关 1 对 1（用户 2026-11-05 夜）
    if M.BUILD_LEVELS and k == 2 then n = 2 end   -- 第 2 关 1v1 道具关（用户 2026-11-03：先一对一看效果）
    local list = n >= 7 and BIG_SHAPES or ALL_SHAPES
    local shape = list[(k * 3 + blk) % #list + 1]
    if k == 1 then shape = SQ end   -- 第 1 关方盘
    local bases
    for rad = 11.5, 6, -0.5 do   -- 出生区半径从 11.5 往里收，直到整块出生区都在形状里
        local bs = around(CX, CX, rad, n, 4.5, -math.pi / 2)
        if shape.kind == "oval" then for _, b in ipairs(bs) do b[1] = CX + (b[1] - CX) * shape.a / shape.b end end
        if bases_fit(shape, nil, bs) then bases = bs; break end
    end
    assert(bases, "level " .. k .. " has no fitting bases")
    local weights = boss and boss_weights(shape, bases, n, M.BOSS_EDGE) or nil
    -- 2026-11-03 第二种打法：偶数关道具关（build：大炮 / 放大器 / 士兵，没有球），奇数关球关；人数 / 形状轮换照旧
    local build = M.BUILD_LEVELS and (k % 2 == 0)
    local BUILD = require("games.clashdoz.cd_config").BUILD
    if build and k == 2 then   -- 第 2 关：原版式 1v1 场地 24 宽 × 48 高，下半场玩家、上半场电脑，起始炮各在自己半场中央（用户 2026-11-03 深夜：先 1v1 测通再考虑多人）
        local A = BUILD.ARENA
        return { n = 2, time = A.time, mode = "build", arena = { w = A.w, h = A.h }, shape = SQ, goal = AREA,
                 bases = { { A.w / 2, A.h / 2 - 6, 1 }, { A.w / 2, A.h / 2 + 7, 1 } }, board = BOARDS[(k + blk * 3) % #BOARDS + 1] }   -- 起始炮离中线 6 格：射程 10 格，开局就打得到对面
    end
    -- 其余道具关 cells = 16：每边 16 格（形状 / 出生区仍按 32 格坐标写，layout() 里按比例换算）
    return { n = n, time = 60, mode = build and "build" or "ball", cells = build and BUILD.CELLS or nil, shape = shape, fill = true, goal = AREA, bases = bases, board = BOARDS[(k + blk * 3) % #BOARDS + 1],
             boss = boss or nil, weights = weights }
end
M.LEVELS = {}
for k = 1, 100 do M.LEVELS[k] = area_level(k) end
M.MAX_LEVEL = #M.LEVELS
-- 技能预览小局（用户 2026-11-05 夜：收藏页每张卡一个预览钮）：方盘 4 队均分、不计时、电脑不带技能；玩法页 FX.pv_drive 每隔几秒替玩家放这招
M.PREVIEW = { n = 4, untimed = true, shape = SQ, fill = true, goal = AREA, bases = around(CX, CX, 11.5, 4, 4.5, -math.pi / 2), board = BOARDS[1] }
function M.is_duel(k) local L = M.LEVELS[k]; return L ~= nil and L.duel == true end
function M.is_boss(k) local L = M.LEVELS[k]; return L ~= nil and L.boss == true end
function M.block(k) return math.floor((k - 1) / 10) + 1 end

function M.get(k) return M.LEVELS[k] end

-- ---------------------------------------------------------------- 对手配置（2026-10-27 八技能改版；2026-11-02 改按组）
-- plan(level) → { n_skills 每个电脑带几种技能, levels = {lo, hi} 技能等级范围, eager 电脑冷却好了就放的概率 [, cap 等级封顶] }
-- 第 1 组电脑只带 1 种一级；第 2 组 2 种一级；第 3 组起出二级、第 5 组起出三级。我方随机发到的技能等级 = levels[2]（组内最高），电脑永远不高过我方
-- 对决关（deck，暂不在关卡表里）：敌人卡数 = 我方卡数、等级 ≤ 我方这副牌的最高等级
local PLANS = {
    { upto = 10,  n_skills = 1, levels = { 1, 1 }, eager = 0.45 },
    { upto = 20,  n_skills = 2, levels = { 1, 1 }, eager = 0.6 },
    { upto = 30,  n_skills = 2, levels = { 1, 2 }, eager = 0.65 },
    { upto = 50,  n_skills = 2, levels = { 2, 2 }, eager = 0.7 },
    { upto = 70,  n_skills = 2, levels = { 2, 3 }, eager = 0.75 },
    { upto = 999, n_skills = 2, levels = { 3, 3 }, eager = 0.85 },
}
function M.plan(level_num)
    local base = PLANS[#PLANS]
    for _, p in ipairs(PLANS) do if level_num <= p.upto then base = p; break end end
    local L = M.LEVELS[level_num]
    if L and L.deck then
        local hi = 1
        for _, c in ipairs(L.deck) do hi = math.max(hi, c.level) end
        return { n_skills = #L.deck, levels = { math.max(1, hi - 1), hi }, eager = base.eager, cap = hi, duel = true }
    end
    return base
end
M.TRIAL_PLAN = { n_skills = 2, levels = { 1, 1 }, eager = 0.7 }   -- 1 VS 1 / 1 VS 8 试玩

--- 按种子生成队 2..n 的对手：{ [t] = { skills = { {id, level}, … } } }。每个对手的技能种类不重复、等级在 levels 范围内随机。
--- cap（可选）= 玩家最高卡等级：电脑等级封顶到 cap（至少 1）——用户 2026-10-30：我方卡还低时敌人技能球不能比我方高。
function M.enemies(n, plan, seed, cap)
    local config = require("games.clashdoz.cd_config")
    local rng = require("games.clashdoz.cd_rng")
    local r = rng.new((seed or 1) * 31 + 7)
    local function shuffled(list)
        local t = {}
        for i, v in ipairs(list) do t[i] = v end
        for i = #t, 2, -1 do local k = rng.range(r, 1, i); t[i], t[k] = t[k], t[i] end
        return t
    end
    if plan.cap then cap = plan.cap end   -- 对决关：封顶到关卡给我方那副牌的最高等级
    local out = {}
    for t = 2, n do
        local kinds = shuffled(config.ENEMY_SKILL_IDS)   -- 冰冻只给玩家（2026-10-30）
        local skills = {}
        for k = 1, plan.n_skills do
            local lv = rng.range(r, plan.levels[1], plan.levels[2])   -- 先抽再封顶：同种子同种类
            if cap then lv = math.min(lv, math.max(1, cap)) end
            skills[k] = { id = kinds[k], level = lv }
        end
        out[t] = { skills = skills }
    end
    return out
end

--- 2026-11-03 用户：技能每次进关都随机、不要扎堆、减速最多一个电脑有。
--- roll(n, plan, seed, slots) → loadout（我方 slots 种，等级 = plan.levels[2]）, enemies（{ [t] = { skills } }，每电脑 plan.n_skills 种，等级在 plan.levels 内）
--- 发牌：每次从候选里挑"全桌目前最少人有"的那种（候选先洗牌，同样少的随机），同一队不重复；我方先发（候选 = 全部 8 种），
--- 电脑按位轮流发（候选 = ENEMY_SKILL_IDS，没有 bomb；freeze 发满 FREEZE_BOTS_MAX 个电脑后不再发）——同种子同牌；开第 3 位只是多发一张，前两张不变
--- mode = "build"（道具关，2026-11-03）：不随机——我方三样道具都给（等级 = 组内最高，不用开第 3 位），每个电脑三样都给（等级在组范围内）
function M.roll(n, plan, seed, slots, mode)
    local config = require("games.clashdoz.cd_config")
    local rng = require("games.clashdoz.cd_rng")
    local r = rng.new((seed or 1) * 17 + 3)
    if mode == "build" then
        local hi = plan.levels[2]
        local loadout, enemies = {}, {}
        local ids = config.BUILD_ITEM_IDS or config.ITEM_IDS
        for _, id in ipairs(ids) do loadout[#loadout + 1] = { id = id, level = hi } end
        for t = 2, n do
            enemies[t] = { skills = {} }
            for _, id in ipairs(ids) do enemies[t].skills[#enemies[t].skills + 1] = { id = id, level = rng.range(r, plan.levels[1], hi) } end
        end
        return loadout, enemies
    end
    local count, freeze_bots = {}, 0
    local function deal(hand, pool, lo, hi)
        local cands = {}
        for i, v in ipairs(pool) do cands[i] = v end
        for i = #cands, 2, -1 do local k = rng.range(r, 1, i); cands[i], cands[k] = cands[k], cands[i] end
        local best, bc
        for _, id in ipairs(cands) do
            local dup = false
            for _, sk in ipairs(hand) do if sk.id == id then dup = true end end
            if not dup and (bc == nil or (count[id] or 0) < bc) then best, bc = id, count[id] or 0 end
        end
        if not best then return nil end
        count[best] = (count[best] or 0) + 1
        hand[#hand + 1] = { id = best, level = rng.range(r, lo, hi) }
        return best
    end
    local hi = plan.levels[2]
    local loadout = {}
    for _ = 1, slots or config.SLOTS_DEFAULT do deal(loadout, config.SKILL_IDS, hi, hi) end
    local enemies = {}
    for t = 2, n do enemies[t] = { skills = {} } end
    local no_freeze = {}
    for _, id in ipairs(config.ENEMY_SKILL_IDS) do if id ~= "freeze" then no_freeze[#no_freeze + 1] = id end end
    for _ = 1, plan.n_skills do
        for t = 2, n do
            local pool = freeze_bots >= (config.FREEZE_BOTS_MAX or 1) and no_freeze or config.ENEMY_SKILL_IDS
            if deal(enemies[t].skills, pool, plan.levels[1], hi) == "freeze" then freeze_bots = freeze_bots + 1 end
        end
    end
    -- 整平：顺序发牌受"同队不重复"牵制，人多时偶尔某种多出 2 人——把最多的一种换成最少的一种（只换电脑的、不碰 freeze），直到全桌最多最少只差 1
    for _ = 1, 16 do
        local lo_id, hi_id, lo_c, hi_c
        for _, id in ipairs(no_freeze) do
            local c = count[id] or 0
            if lo_c == nil or c < lo_c then lo_id, lo_c = id, c end
            if hi_c == nil or c > hi_c then hi_id, hi_c = id, c end
        end
        if hi_c - lo_c <= 1 then break end
        local done = false
        for t = 2, n do
            local hand = enemies[t].skills
            local has_lo, at = false, nil
            for k, sk in ipairs(hand) do if sk.id == lo_id then has_lo = true end; if sk.id == hi_id then at = k end end
            if at and not has_lo then hand[at].id = lo_id; count[hi_id] = count[hi_id] - 1; count[lo_id] = (count[lo_id] or 0) + 1; done = true; break end
        end
        if not done then break end
    end
    return loadout, enemies
end

--- 格 (i, j) 是否在关卡的墙里
function M.in_wall(L, i, j, walls)
    for _, w in ipairs(walls or L.walls or {}) do if i >= w[1] and j >= w[2] and i <= w[3] and j <= w[4] then return true end end
    return false
end

--- 第 k 盘里格 (i, j) 是否被挡：盘给了 open（跑道矩形并集）就看在不在里面，否则看 walls
function M.stage_blocked(L, st, i, j)
    if st.open then
        for _, r in ipairs(st.open) do if i >= r[1] and j >= r[2] and i <= r[3] and j <= r[4] then return false end end
        return true
    end
    return M.in_wall(L, i, j, st.walls or {})
end

--- 接力关第 k 盘里队 t 的起点格 {i, j}（分道盘每队一个，共同盘大家一个；不够按队号轮用）
function M.stage_spawn(st, t)
    local sp = st.spawns
    return sp[(t - 1) % #sp + 1]
end

--- 跑道接力关（stages）：第 k 盘的 region(i, j)（形状 + 该盘的墙，全盘跑道格）
function M.stage_region(L, k)
    local config = require("games.clashdoz.cd_config")
    local inside = SHAPES[L.shape.kind](L.shape)
    local st = L.stages[k]
    return function(i, j)
        local x, y = i - 0.5, j - 0.5
        if not inside(x, y) or M.stage_blocked(L, st, i, j) then return false end
        return config.TRACK
    end
end

--- 关卡 → sim 布局：region(i, j) → 队号 | 0 中立 | false 空洞（形状外 / 墙）；spawn(t, rnd) → 出生点 x, y（rnd = 0..1 随机函数）
--- fill = true 时每个格归最近的出生区（全盘占满不留白）；goal / portals / boosts 原样透传给 sim
function M.layout(L)
    local inside = SHAPES[L.shape.kind](L.shape)
    local config = require("games.clashdoz.cd_config")
    local st1 = L.stages and L.stages[1]
    local cells = L.cells or GRID
    local K = GRID / cells   -- 关卡表坐标（32 格）→ 这局格子：16 格盘一格 = 2 个关卡格
    if L.arena then   -- 1v1 竖长场地：坐标就是格坐标，下半场队 1、上半场队 2，起始点 = bases
        return {
            n = L.n, time = L.time, goal = L.goal, mode = L.mode, cols = L.arena.w, rows = L.arena.h,
            region = function(i, j) return j <= L.arena.h / 2 and 1 or 2 end,
            spawn = function(t, rnd) local b = L.bases[t]; return b[1] - 0.5, b[2] - 0.5 end,
        }
    end
    return {
        n = L.n,
        cells = cells,
        time = L.time,
        untimed = L.untimed,
        goal = L.goal,
        portals = L.portals,
        boosts = st1 and st1.boosts or L.boosts,
        track = L.track,
        view = L.view, speed = L.speed, maze = L.maze, goal_stage = L.goal_stage, deck = L.deck,
        mode = L.mode,   -- "build" 道具关（2026-11-03）；nil / "ball" 球关
        stages = L.stages,
        stage_region = L.stages and function(k) return M.stage_region(L, k) end or nil,
        region = function(i, j)
            local x, y = (i - 0.5) * K, (j - 0.5) * K
            local blocked = st1 and M.stage_blocked(L, st1, i, j) or (not st1 and M.in_wall(L, i, j))
            if not inside(x, y) or blocked then return false end
            if L.track then return config.TRACK end   -- 跑道关：全盘跑道格
            -- 竞速关：星星周围 guard 格开局是中立（唯一允许的白格）——球只能在自己颜色里跑，谁都得先一格格染过去才到得了星星，
            -- 否则星星落在几家交界上开局一秒就被碰到（2026-11-01 第 8 关实测）
            if L.goal and L.goal.kind == "race" and L.goal.at and not L.track then
                local g = L.goal.guard or M.RACE_GUARD
                if (x - (L.goal.at[1] - 0.5)) ^ 2 + (y - (L.goal.at[2] - 0.5)) ^ 2 <= g * g then return 0 end
            end
            local best, bd = 0, math.huge
            for t, b in ipairs(L.bases) do
                local d = ((x - b[1]) ^ 2 + (y - b[2]) ^ 2) * (L.weights and L.weights[t] or 1)   -- Boss 关：玩家距离加权 → 地盘比电脑小
                if (L.fill or d <= b[3] * b[3]) and d < bd then best, bd = t, d end
            end
            return best
        end,
        spawn = function(t, rnd)
            local b = L.bases[t]
            if st1 then local sp = M.stage_spawn(st1, t); b = { sp[1] - 0.5, sp[2] - 0.5, 1.5 } end   -- 接力关：第 1 盘里这队的起点（格中心）
            local a, d = rnd() * 2 * math.pi, rnd() * b[3] * 0.4
            return (b[1] + d * math.cos(a)) / K, (b[2] + d * math.sin(a)) / K
        end,
    }
end

return M
