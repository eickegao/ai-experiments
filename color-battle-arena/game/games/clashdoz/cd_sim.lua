-- games/clashdoz/cd_sim.lua（移植自 github.com/eickegao/clashdoz main/sim.lua 的球/格子/布局规则）
-- Game rules, independent of rendering and input.
--
-- All player and AI actions enter through M.command(), and the world only advances through M.step() with a fixed dt.
-- Together with the seeded RNG this keeps the simulation deterministic.
--
-- 2026-10-27 晚 八技能改版（设计稿 docs/superpowers/specs/2026-10-27-clashdoz-eight-skills-design.md）：
--   没有能量、没有 BOOST、没有天赋；每队带 ≤ 3 种技能 team.skills = { {id, level} }，每种各自冷却 team.cd[id]。
--   主球 = team.balls[1]。2026-10-31 护盾整个删掉，换成炸弹（ball_hit：主球撞换色时连带十字邻格）。

local config = require("games.clashdoz.cd_config")
local rng = require("games.clashdoz.cd_rng")

local M = {}

local GRID = config.GRID
local SKILLS = config.SKILLS
local ITEMS = config.ITEMS   -- 道具关三样（大炮 / 放大器 / 士兵，2026-11-03）：和技能同一套 skills / cd / can_cast
local BUILD = config.BUILD
local function def(id) return SKILLS[id] or ITEMS[id] end
local remove_struct   -- 前置声明（set_cell 里敌方染掉放大器脚下的格要用）
local TRACK = config.TRACK   -- 跑道格：不挡、不染、不计数（竞速关）
local MAX_STEP = 0.25      -- max distance (in cells) a ball moves per sub-step

-- 8 probe directions around a ball used for collision checks
local PROBES = {}
for k = 0, 7 do
	local a = k * math.pi / 4
	PROBES[#PROBES + 1] = { math.cos(a), math.sin(a) }
end

-- 开局布局（quad 与原型一字不差；duel / nine 为 2026-10-26 关卡制试玩加）：
--   region(i, j) → 开局时格子归哪队；bounds(t) → 队 t 的出生区 x0, y0, w, h（球随机落在区内）
local HALF = GRID / 2
local THIRD_X0, THIRD_W = { 0, 11, 21 }, { 11, 10, 11 }   -- 32 = 11 + 10 + 11
local function third(v) if v <= 11 then return 0 elseif v <= 21 then return 1 else return 2 end end
local NINE_TEAM = { 2, 3, 4, 5, 1, 6, 7, 8, 9 }            -- 3×3 区索引 (r*3+c, 从 0) → 队；正中 = 玩家 1
local NINE_RC = {}
for idx, t in ipairs(NINE_TEAM) do NINE_RC[t] = { (idx - 1) % 3, math.floor((idx - 1) / 3) } end
M.LAYOUTS = {
	quad = { n = 4,
		region = function(i, j) if j > HALF then return i > HALF and 2 or 1 else return i > HALF and 4 or 3 end end,
		bounds = function(t) return (t == 2 or t == 4) and HALF or 0, (t == 1 or t == 2) and HALF or 0, HALF, HALF end },
	duel = { n = 2,
		region = function(i, j) return i > HALF and 2 or 1 end,
		bounds = function(t) return (t == 2) and HALF or 0, 0, HALF, GRID end },
	nine = { n = 9,
		region = function(i, j) return NINE_TEAM[third(j) * 3 + third(i) + 1] end,
		bounds = function(t) local c, r = NINE_RC[t][1], NINE_RC[t][2]; return THIRD_X0[c + 1], THIRD_X0[r + 1], THIRD_W[c + 1], THIRD_W[r + 1] end },
}
--- solo（2026-10-28 封面演示）：一队、只有正中 n×n 是棋盘（其余空洞当墙；n 按设备撑满，手机/iPad 不同）、正中 2×2 基地，不计时
function M.solo_layout(n)
	n = math.max(6, math.min(GRID, math.floor(n or 16)))
	local lo = HALF - math.floor(n / 2) + 1
	local hi = lo + n - 1
	return { n = 1, time = 1e9, size = n,
		region = function(i, j)
			if i < lo or i > hi or j < lo or j > hi then return false end
			return ((i == HALF or i == HALF + 1) and (j == HALF or j == HALF + 1)) and 1 or 0
		end,
		spawn = function() return HALF, HALF end }
end
M.LAYOUTS.solo = M.solo_layout(16)

-- 试验场（用户 2026-10-28 改）：四象限 4 人一局 60 s，每人随机 2 种一级技能，玩家第一位换成三级巨球（看巨球穿透效果）
local LAB_GIANT_LEVEL = 3
local function lab_setup(seed)
	local r = rng.new(seed * 13 + 5)
	local function two(exclude, ids)
		local pool = {}
		for _, id in ipairs(ids or config.SKILL_IDS) do if id ~= exclude then pool[#pool + 1] = id end end
		for i = #pool, 2, -1 do local k = rng.range(r, 1, i); pool[i], pool[k] = pool[k], pool[i] end
		return pool[1], pool[2]
	end
	local a = two("giant")
	local loadout = { { id = "giant", level = LAB_GIANT_LEVEL }, { id = a, level = 1 } }
	local enemies = {}
	for t = 2, 4 do local x, y = two(nil, config.ENEMY_SKILL_IDS); enemies[t] = { skills = { { id = x, level = 1 }, { id = y, level = 1 } } } end
	return loadout, enemies
end

function M.cell_index(i, j)
	return (j - 1) * GRID + i
end

function M.is_frozen(s, team)
	return (team.frozen_left or 0) > 0
end

--- 棋盘每边格数：s.N（道具关 16，球关 32；cell_index 的步长永远是 config.GRID = 32，只是键）
local function in_board(s, i, j) return i >= 1 and i <= (s.W or GRID) and j >= 1 and j <= (s.H or GRID) end

local function set_cell(s, i, j, team_id)
	local old = s.grid[i][j]
	if old == team_id or old == false or old == TRACK then return end   -- false = 空洞（关卡棋盘形状之外）、TRACK = 跑道，永远不变
	if old and old > 0 then s.counts[old] = s.counts[old] - 1
	elseif old == 0 then s.counts[0] = s.counts[0] - 1 end
	s.counts[team_id] = s.counts[team_id] + 1
	s.grid[i][j] = team_id
	local idx = M.cell_index(i, j)
	s.changed[#s.changed + 1] = idx
	s.flips[#s.flips + 1] = { idx = idx, from = old, to = team_id }   -- 换色记录：渲染层做闪白+碎片（2026-10-31）
	if s.build then s.build.dmg[idx] = nil; s.build.dmg_team[idx] = nil end   -- 道具关：格子翻了伤害清零（装置脚印锁定，走不到这里）
end

--- 队 team_id 打格 (i, j)：敌格 / 中立格换色；自己的格 / 空洞 / 出界不变。返回 true = 换色了。
function M.hit_cell(s, i, j, team_id)
	if not in_board(s, i, j) then return false end
	local owner = s.grid[i][j]
	if owner == false or owner == TRACK or owner == team_id then return false end
	if s.locked and s.locked[M.cell_index(i, j)] then return false end   -- 道具关：大炮脚下的格只有士兵能占
	set_cell(s, i, j, team_id)
	return true
end
local hit_cell = M.hit_cell

local BOMB_DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
--- 球撞格 (i, j)（反弹路径 / 传送落点）：换色；炸弹在场且是主球 → 十字四邻里非己方的格再换 extra 个，
--- 优先前进方向那侧（2026-10-31 替代护盾，用户口述：一级连 1 格、二级 2 格、三级 3 格，不够就有几个换几个）。返回 true = 撞的格换色了。
local function ball_hit(s, team, ball, i, j)
	if not hit_cell(s, i, j, team.id) then return false end
	if ball == team.balls[1] and (team.snow_left or 0) > 0 then   -- 等离子球：主球每撞一次别的颜色大一圈（≤ steps；撞墙 / 棋盘边 / 空洞 hit_cell 不换色，上面已 return，不算）；长满后再撞 → 爆（技能随之结束）
		local T = SKILLS.snowball
		if (team.snow_n or 0) < T.steps[team.snow_level] then
			team.snow_n = team.snow_n + 1
			s.events[#s.events + 1] = { team = team.id, skill = "snowball", phase = "grow", x = ball.x, y = ball.y, n = team.snow_n, level = team.snow_level }
		else   -- 爆雪（用户 2026-11-05）：撞点周围半径 burst 格的圆全染（格数刻意少：5/9/13），缩回 0 圈重新滚
			local r = T.burst[team.snow_level]; local reach = math.ceil(r); local cells = 1
			for ci = i - reach, i + reach do
				for cj = j - reach, j + reach do
					local dx, dy = ci - i, cj - j
					if (dx ~= 0 or dy ~= 0) and dx * dx + dy * dy <= r * r and hit_cell(s, ci, cj, team.id) then cells = cells + 1 end
				end
			end
			team.snow_n, team.snow_left = 0, 0   -- 炸完技能直接结束、球回普通（用户 2026-11-05：不要炸完又重新长）
			s.events[#s.events + 1] = { team = team.id, skill = "snowball", phase = "burst", x = ball.x, y = ball.y, i = i, j = j, radius = r, cells = cells, level = team.snow_level }
		end
	end
	if (team.bomb_left or 0) > 0 and ball == team.balls[1] then
		local cand = {}
		for _, d in ipairs(BOMB_DIRS) do
			local ni, nj = i + d[1], j + d[2]
			if in_board(s, ni, nj) and s.grid[ni][nj] ~= false and s.grid[ni][nj] ~= TRACK and s.grid[ni][nj] ~= team.id then
				cand[#cand + 1] = { ni, nj, d[1] * ball.dx + d[2] * ball.dy }
			end
		end
		table.sort(cand, function(a, b) return a[3] > b[3] end)
		local cells = {}
		for k = 1, math.min(SKILLS.bomb.extra[team.bomb_level], #cand) do
			set_cell(s, cand[k][1], cand[k][2], team.id)
			cells[#cells + 1] = M.cell_index(cand[k][1], cand[k][2])
		end
		if #cells > 0 then
			s.events[#s.events + 1] = { team = team.id, skill = "bomb", level = team.bomb_level, phase = "hit", x = i - 0.5, y = j - 0.5, i = i, j = j, cells = cells }
		end
	end
	return true
end
M.ball_hit = ball_hit

-- 巨球作用全部球（含分身副球；用户 2026-10-30：分身可与巨球叠加）；三级穿透只给主球，副球只是大球照常反弹
local function is_giant(team, ball) return (team.giant_left or 0) > 0 end
local function giant_pierces(team, ball) return SKILLS.giant.pierce[team.giant_level] and ball == team.balls[1] end   -- 只有三级巨球穿透（用户 2026-10-28：一/二级只是大球，照常反弹）

--- 速度（格/秒）：加速对全队、巨型对全部球（2026-10-30）、被减速对全队
local function ball_speed(team, ball)
	local v = config.BALL_SPEED * (team.speed_k or 1)   -- 跑道关可整体放慢（layout.speed，2026-11-02 长坡接力迷宫：镜头放大后 22 格/s 太快）
	if (team.accel_left or 0) > 0 then v = v * team.accel_mult end
	if is_giant(team, ball or team.balls[1]) then v = v * SKILLS.giant.mult[team.giant_level] end
	if (team.slow_left or 0) > 0 then v = v * team.slow_factor end
	if ball and (ball.boost_left or 0) > 0 then v = v * config.BOOST_MULT end   -- 踩了加速装置（只这颗球）
	return v
end
M.ball_speed = ball_speed

function M.ball_radius(team, ball)
	if is_giant(team, ball) then return SKILLS.giant.radius[team.giant_level] end
	if (team.snow_left or 0) > 0 and ball == team.balls[1] and (team.snow_n or 0) > 0 then   -- 滚雪球：按圈数线性长到 max_r
		local T = SKILLS.snowball
		return config.BALL_RADIUS + (T.max_r[team.snow_level] - config.BALL_RADIUS) * math.min(1, team.snow_n / T.steps[team.snow_level])
	end
	return config.BALL_RADIUS
end

-- Unit direction that avoids near-horizontal or near-vertical angles, which would make the ball slide along a wall forever.
--- min = 方向分量下限（默认 config.MIN_SLOPE；跑道关传 0 允许纯横 / 纯竖直线，用户 2026-11-03）
local function set_direction(ball, dx, dy, min)
	local len = math.sqrt(dx * dx + dy * dy)
	if len < 1e-6 then return end
	dx, dy = dx / len, dy / len
	min = min or config.MIN_SLOPE
	if min > 0 then
		if math.abs(dx) < min then dx = (dx < 0 and -min or min) end
		if math.abs(dy) < min then dy = (dy < 0 and -min or min) end
		len = math.sqrt(dx * dx + dy * dy)
	end
	ball.dx, ball.dy = dx / len, dy / len
end
--- 跑道关玩家自己下的转向近乎直线（TRACK_MIN_SLOPE，用户 2026-11-03：窄道里来回撞墙不爽）；电脑和反弹仍守 MIN_SLOPE
local function slope_min(s, team) return (s.track and team.id == config.PLAYER_TEAM) and config.TRACK_MIN_SLOPE or nil end

local function rotate(ball, a, min)
	local c, sn = math.cos(a), math.sin(a)
	set_direction(ball, ball.dx * c - ball.dy * sn, ball.dx * sn + ball.dy * c, min)
end

--- 球所在格有装置就触发：传送阵 → 瞬移到另一端（PORTAL_CD 内不再被吸）；加速装置 → 这颗球提速 BOOST_DUR 秒
local function touch_devices(s, team, ball)
	local ci, cj = math.floor(ball.x) + 1, math.floor(ball.y) + 1
	if not in_board(s, ci, cj) then return end
	local idx = M.cell_index(ci, cj)
	local st = s.stages and s.stages[team.stage or 1]
	if st then   -- 跑道接力：踩到本盘出口 → 全队切到下一盘起点（事件给渲染层切棋盘）；本盘加速装置
		local to = st.exit_to[idx]
		if to and to ~= team.stage and s.stages[to] then   -- 任一个出口都算（分道盘每道一个）；出口可指定去哪一盘（含退回去的死胡同口，2026-11-02）
			team.stage = to
			local nst = s.stages[team.stage]
			local sp = M.stage_spawn(nst, team.id)   -- 下一盘这队自己的起点（分道盘各道、共同盘同一个）
			local ox, oy = ball.x, ball.y   -- 事件里的 x, y = 踩口时的位置（渲染层在这里放"吸走"特效）
			for _, b in ipairs(team.balls) do b.x, b.y = sp[1] - 0.5, sp[2] - 0.5; b.portal_cd = config.PORTAL_CD; b.boost_left = 0 end
			s.events[#s.events + 1] = { device = "stage", team = team.id, stage = team.stage, x = ox, y = oy }
			return
		end
		if st.boosts[idx] and (ball.boost_cd or 0) <= 0 then
			ball.boost_left, ball.boost_cd = config.BOOST_DUR, config.BOOST_CD
			s.events[#s.events + 1] = { device = "boost", team = team.id, x = ball.x, y = ball.y, dur = config.BOOST_DUR }
		end
		return
	end
	local dest = s.portals[idx]
	if dest then
		if (ball.portal_cd or 0) <= 0 then
			s.events[#s.events + 1] = { device = "portal", team = team.id, x = ball.x, y = ball.y, to_x = dest[1] - 0.5, to_y = dest[2] - 0.5 }
			ball.x, ball.y = dest[1] - 0.5, dest[2] - 0.5
			ball.portal_cd = config.PORTAL_CD
		end
	elseif s.boosts[idx] and (ball.boost_cd or 0) <= 0 then
		ball.boost_left, ball.boost_cd = config.BOOST_DUR, config.BOOST_CD
		s.events[#s.events + 1] = { device = "boost", team = team.id, x = ball.x, y = ball.y, dur = config.BOOST_DUR }
	end
end

--- 接力关第 k 盘里队 t 的起点格 {i, j}（分道盘每队一个，共同盘大家一个；不够按队号轮用）
function M.stage_spawn(st, t)
	local sp = st.spawns
	return sp[(t - 1) % #sp + 1]
end

--- 队现在所在的棋盘格子表（跑道接力关每队各在自己的那一盘；其他关 = s.grid）
local function team_grid(s, team)
	local st = s.stages and s.stages[team.stage or 1]
	return st and st.grid or s.grid
end
M.team_grid = team_grid

--- 分裂球：任何一颗球（主球 / 小球 / 分身）撞格换了色就从撞点弹出一颗小球（沿反射的另一侧 57°～92° 飞），活 life 秒；同时 ≤ max 颗且全队 ≤ MAX_BALLS_PER_TEAM（用户 2026-11-05 夜：小球也分裂，到上限为止）
local function spawn_shard(s, team, ball)
	local T = SKILLS.shatter
	local lv = team.shatter_level
	local n = 0
	for _, b in ipairs(team.balls) do if b.shard then n = n + 1 end end
	if n >= T.max[lv] or #team.balls >= config.MAX_BALLS_PER_TEAM then return end
	local child = { x = ball.x, y = ball.y, dx = ball.dx, dy = ball.dy, temp = true, shard = true, life = T.life[lv] }
	local side = rng.next(s.rng) < 0.5 and -1 or 1
	rotate(child, side * (1.0 + rng.next(s.rng) * 0.6))
	team.balls[#team.balls + 1] = child
	s.events[#s.events + 1] = { team = team.id, skill = "shatter", phase = "spawn", x = ball.x, y = ball.y, level = lv }
end

local function step_ball(s, team, ball, dt)
	if (ball.stun_left or 0) > 0 then return end   -- 被链电劈 / 被冲击波撞：原地停住
	local giant = is_giant(team, ball)
	local r = M.ball_radius(team, ball)
	local grid = team_grid(s, team)
	local speed = ball_speed(team, ball)
	ball.x = ball.x + ball.dx * speed * dt
	ball.y = ball.y + ball.dy * speed * dt

	local bounced = false
	local N = s.N or GRID
	if ball.x < r then ball.x = r; ball.dx = math.abs(ball.dx); bounced = true
	elseif ball.x > N - r then ball.x = N - r; ball.dx = -math.abs(ball.dx); bounced = true end
	if ball.y < r then ball.y = r; ball.dy = math.abs(ball.dy); bounced = true
	elseif ball.y > N - r then ball.y = N - r; ball.dy = -math.abs(ball.dy); bounced = true end

	if giant and giant_pierces(team, ball) then
		-- 三级巨球：压到的格子全部染色，不反弹，只在棋盘边反弹；一/二级巨球走下面的普通路径（只是球大、撞到的格多）
		local lo_i, hi_i = math.floor(ball.x - r), math.floor(ball.x + r)
		local lo_j, hi_j = math.floor(ball.y - r), math.floor(ball.y + r)
		for i = lo_i, hi_i do
			for j = lo_j, hi_j do
				local dx, dy = (i + 0.5) - ball.x, (j + 0.5) - ball.y
				if dx * dx + dy * dy <= r * r then hit_cell(s, i + 1, j + 1, team.id) end
			end
		end
		for _, p in ipairs(PROBES) do   -- 空洞当墙：巨球也穿不过关卡棋盘之外
			local i = math.floor(ball.x + p[1] * r) + 1
			local j = math.floor(ball.y + p[2] * r) + 1
			if in_board(s, i, j) and grid[i][j] == false then
				if p[1] > 0.5 then ball.dx = -math.abs(ball.dx) elseif p[1] < -0.5 then ball.dx = math.abs(ball.dx) end
				if p[2] > 0.5 then ball.dy = -math.abs(ball.dy) elseif p[2] < -0.5 then ball.dy = math.abs(ball.dy) end
				bounced = true
			end
		end
		if bounced then rotate(ball, (rng.next(s.rng) - 0.5) * 0.3) end
		touch_devices(s, team, ball)
		return
	end

	-- enemy / neutral cells: hit them (bomb: main ball also takes neighbours) and bounce away; void cells (false) are walls
	local flipped = false
	for _, p in ipairs(PROBES) do
		local i = math.floor(ball.x + p[1] * r) + 1
		local j = math.floor(ball.y + p[2] * r) + 1
		if in_board(s, i, j) and grid[i][j] ~= team.id and grid[i][j] ~= TRACK then   -- 跑道格不挡球
			if ball_hit(s, team, ball, i, j) then flipped = true end
			if p[1] > 0.5 then ball.dx = -math.abs(ball.dx) elseif p[1] < -0.5 then ball.dx = math.abs(ball.dx) end
			if p[2] > 0.5 then ball.dy = -math.abs(ball.dy) elseif p[2] < -0.5 then ball.dy = math.abs(ball.dy) end
			bounced = true
		end
	end
	if bounced then rotate(ball, (rng.next(s.rng) - 0.5) * 0.3) end
	if flipped and (team.shatter_left or 0) > 0 then spawn_shard(s, team, ball) end
	touch_devices(s, team, ball)
end

-- ---------------------------------------------------------------- 前瞻（终结慢镜头用，2026-11-03 用户：一定要判断出这球一定会撞到那个地方才放慢镜头）
--- 球沿现在的方向直走最多 dist 格（只算棋盘边反弹，和 step_ball 一样用 8 个探针），返回它第一下会撞到的格 {i, j}（非己方、非跑道，含空洞）和走到那里的格数；dist 内没撞到返回 nil
function M.first_hit(s, team, ball, dist)
	local r = M.ball_radius(team, ball)
	local grid = team_grid(s, team)
	local x, y, dx, dy = ball.x, ball.y, ball.dx, ball.dy
	local step = 0.05
	local n = math.ceil(dist / step)
	for k = 1, n do
		x, y = x + dx * step, y + dy * step
		local N = s.N or GRID
		if x < r then x = r; dx = math.abs(dx) elseif x > N - r then x = N - r; dx = -math.abs(dx) end
		if y < r then y = r; dy = math.abs(dy) elseif y > N - r then y = N - r; dy = -math.abs(dy) end
		for _, p in ipairs(PROBES) do
			local i, j = math.floor(x + p[1] * r) + 1, math.floor(y + p[2] * r) + 1
			if in_board(s, i, j) and grid[i][j] ~= team.id and grid[i][j] ~= TRACK then return { i, j }, k * step end
		end
	end
	return nil
end
--- 染区终结判定（用户 2026-11-03）：目标区只剩一格不是 team 的，某颗该队的球前瞻 dist 格第一下撞到的就是它，
--- 并且在它撞到之前没有别队的球会先撞到目标区里该队的格（按各自球速折算同一段时间里别队球能走多远）、也没有别队的火焰要落在目标区里
--- → 返回最后一格 i, j；否则 nil（那就还不是最后一个动作）
function M.zone_final_hit(s, team_id, dist)
	local g = s.goal
	if not g or g.kind ~= "zone" or not g.cells or (g.owned and g.owned[team_id] or 0) ~= g.total - 1 then return nil end
	local in_zone = {}
	local li, lj
	for _, idx in ipairs(g.cells) do
		local i, j = (idx - 1) % GRID + 1, math.floor((idx - 1) / GRID) + 1
		in_zone[idx] = true
		if s.grid[i][j] ~= team_id and not li then li, lj = i, j end
	end
	if not li then return nil end
	local team = s.teams[team_id]
	local best
	for _, b in ipairs(team.balls) do
		local h, d = M.first_hit(s, team, b, dist)
		if h and h[1] == li and h[2] == lj and (not best or d < best.d) then best = { d = d, speed = ball_speed(team, b) } end
	end
	if not best then return nil end
	local t_hit = best.d / math.max(1e-6, best.speed)   -- 我方撞到最后一格要多久
	for _, other in ipairs(s.teams) do
		if other.id ~= team_id then
			for _, ob in ipairs(other.balls) do
				local reach = ball_speed(other, ob) * t_hit + 0.6   -- 同一段时间里它能走多远（多留半格余量）
				local h = M.first_hit(s, other, ob, reach)
				if h and in_board(s, h[1], h[2]) and in_zone[M.cell_index(h[1], h[2])] and s.grid[h[1]][h[2]] == team_id then return nil end
			end
		end
	end
	for _, f in ipairs(s.fires or {}) do   -- 别队落下的火焰圈压到目标区任一格 → 不是最后一下
		if f.team ~= team_id then
			for _, idx in ipairs(g.cells) do
				local i, j = (idx - 1) % GRID + 1, math.floor((idx - 1) / GRID) + 1
				if (i - 0.5 - f.x) ^ 2 + (j - 0.5 - f.y) ^ 2 <= (f.radius + 0.5) ^ 2 then return nil end
			end
		end
	end
	return li, lj
end
--- 竞速：球沿现在的方向直走最多 dist 格，中途不碰墙 / 空洞就进到星星（球心离星星 ≤ goal.r）→ true
function M.will_reach_star(s, team, ball, dist)
	local g = s.goal
	if not g or not g.at then return false end
	local tx, ty = g.at[1] - 0.5, g.at[2] - 0.5
	local r = M.ball_radius(team, ball)
	local grid = team_grid(s, team)
	local x, y, dx, dy = ball.x, ball.y, ball.dx, ball.dy
	local step = 0.05
	for _ = 1, math.ceil(dist / step) do
		x, y = x + dx * step, y + dy * step
		if (x - tx) ^ 2 + (y - ty) ^ 2 <= g.r * g.r then return true end
		if x < r or x > (s.N or GRID) - r or y < r or y > (s.N or GRID) - r then return false end   -- 碰到棋盘边要反弹：不算"一定到"
		for _, p in ipairs(PROBES) do
			local i, j = math.floor(x + p[1] * r) + 1, math.floor(y + p[2] * r) + 1
			if in_board(s, i, j) and grid[i][j] == false then return false end
		end
	end
	return false
end

-- ---------------------------------------------------------------- 开局
--- build = true 只收道具（ITEMS），否则只收技能（SKILLS）——球关里混进道具 / 道具关里混进技能都会放不出来或索引不到主球
local function copy_skills(list, cap, build)
	local t, seen = {}, {}
	local table_ = build and ITEMS or SKILLS
	for _, c in ipairs(list or {}) do
		if #t >= (cap or config.SLOTS_MAX) then break end
		if table_[c.id] and not seen[c.id] then
			seen[c.id] = true
			t[#t + 1] = { id = c.id, level = math.max(1, math.min(config.SKILL_MAX_LEVEL, math.floor(c.level or 1))) }
		end
	end
	return t
end

--- opts.layout = "quad"（默认）| "duel" | "nine"；opts.level = 关卡表（cd_levels）；opts.lab = 试验场
--- opts.loadout = { {id=, level=}, … } 玩家带进场的技能；opts.enemies = { [team_id] = { skills = {…} } } 电脑的技能
--- s.n = 队数，s.layout = 布局名（关卡为 "level"），s.total = 非空洞格数，s.counts[0] = 中立格数
function M.new(seed, opts)
	local layout_name = (opts and opts.layout) or config.DEFAULT_LAYOUT or "quad"
	local layout = M.LAYOUTS[layout_name] or M.LAYOUTS.quad
	if layout_name == "solo" and opts and opts.solo_n then layout = M.solo_layout(opts.solo_n) end
	if opts and opts.level then
		layout = require("games.clashdoz.cd_levels").layout(opts.level)
		layout_name = "level"
	end
	local lab = opts and opts.lab
	if lab then
		layout, layout_name = M.LAYOUTS.quad, "lab"
		local lo, en = lab_setup(seed)
		opts = { lab = true, loadout = lo, enemies = en }
	end
	local s = {
		n = layout.n,
		layout = layout_name,
		level = opts and opts.level or nil,
		total = 0,
		rng = rng.new(seed),
		grid = {},
		counts = {},
		teams = {},
		changed = {},       -- cell indices changed since the renderer last looked
		flips = {},         -- 换色记录 { idx, from, to }，渲染层读完清
		events = {},        -- skills cast since the renderer last looked
		elapsed = 0,
		time_left = layout.untimed and math.huge or (layout.time or config.ROUND_TIME),
		untimed = layout.untimed and true or nil,   -- 染区关不计时（用户 2026-11-02）
		lab = lab and true or nil,
		waves = {},         -- 冰冻波
		fires = {},         -- 已点下、还没落地的火焰
		shocks = {},        -- 冲击波（2026-11-04 晚）
		chains = {},        -- 链电：{ team, level, x0, y0, hx, hy（链头）, targets, k（下一颗）, hits, left（打完后再挂多久）}
		over = false,
		mode = layout.mode or "ball",   -- "ball" 球关 | "build" 道具关（大炮 / 放大器 / 士兵，没有球）
		W = layout.cols or layout.cells or GRID,   -- 棋盘宽 / 高（格）：球关 32×32；道具关 16×16；1v1 场地 24×48（原版）
		H = layout.rows or layout.cells or GRID,
	}
	s.N = math.max(s.W, s.H)
	-- 装置状态（道具关的大炮 / 门 / 士兵，球关里炮台技能也用）：永远有
	s.build = { structs = {}, by_cell = {}, bullets = {}, soldiers = {}, next_id = 1, dmg = {}, dmg_team = {} }   -- dmg[idx] = 格子已吃的伤害、dmg_team[idx] = 打它的队（原版格子有血量，打过的格先"介于两色之间"）
	s.locked = {}        -- 格 idx → true：装置脚下，子弹 / 球染不掉

	s.counts[0] = 0
	for t = 1, s.n do s.counts[t] = 0 end
	for i = 1, s.W do
		s.grid[i] = {}
		for j = 1, s.H do
			local v = layout.region(i, j)   -- 队号 | 0 中立 | false 空洞 | TRACK 跑道
			s.grid[i][j] = v
			if v ~= false and v ~= TRACK then
				s.total = s.total + 1
				s.counts[v] = s.counts[v] + 1
			end
		end
	end

	-- 过关方式 + 装置（关卡表给；其他布局 = 占地）
	local g = layout.goal or { kind = "area" }
	s.goal = { kind = g.kind or "area", rect = g.rect, at = g.at, r = g.r or config.RACE_R, cells = {}, total = 0, owned = {} }
	if s.goal.kind == "zone" and g.rect then
		for j = g.rect[2], g.rect[4] do for i = g.rect[1], g.rect[3] do
			if in_board(s, i, j) and s.grid[i][j] ~= false then s.goal.cells[#s.goal.cells + 1] = M.cell_index(i, j) end
		end end
		s.goal.total = #s.goal.cells
	end
	s.portals, s.boosts = {}, {}
	s.devices = { portals = layout.portals or {}, boosts = layout.boosts or {} }
	for _, p in ipairs(s.devices.portals) do
		s.portals[M.cell_index(p[1][1], p[1][2])] = { p[2][1], p[2][2] }
		s.portals[M.cell_index(p[2][1], p[2][2])] = { p[1][1], p[1][2] }
	end
	for _, b in ipairs(s.devices.boosts) do s.boosts[M.cell_index(b[1], b[2])] = true end
	s.winner = nil
	s.track = layout.track and true or nil   -- 跑道关：禁技能（传送一跳就到星星），纯比操控
	-- 跑道接力（2026-11-01 用户：竞速做成多个棋盘，到传送点整盘切换；2026-11-02 分道盘：每队自己的起点/出口）：
	-- s.stages[k] = { grid, boosts(idx 表), spawns = {{i,j}…}, exits = {{i,j}…}, exit_set(idx 表), devices }
	if layout.stages then
		s.stages = {}
		for k, def in ipairs(layout.stages) do
			local region = layout.stage_region(k)
			local grid = {}
			for i = 1, s.N do grid[i] = {}; for j = 1, s.N do grid[i][j] = region(i, j) end end
			local boosts = {}
			for _, b in ipairs(def.boosts or {}) do boosts[M.cell_index(b[1], b[2])] = true end
			local spawns = def.spawns or { def.spawn }
			local exits = def.exits or (def.exit and { def.exit }) or {}
			local exit_set, exit_to = {}, {}
			for _, e in ipairs(exits) do local idx = M.cell_index(e[1], e[2]); exit_set[idx] = true; exit_to[idx] = e.to or (k + 1) end   -- 出口不写 to 就是下一盘
			s.stages[k] = { grid = grid, boosts = boosts, spawns = spawns, exits = exits, exit_set = exit_set, exit_to = exit_to,
			                devices = { boosts = def.boosts or {}, portals = {} } }
		end
		s.grid = s.stages[1].grid
		-- 目标盘（星星所在，默认最后一盘）+ 每盘到目标盘还要切几次（倒着沿出口算；死胡同 = 岔口 + 1）——AI 距离场和到时排名都按这个
		s.goal_stage = layout.goal_stage or #s.stages
		local depth = { [s.goal_stage] = 0 }
		local changed = true
		while changed do
			changed = false
			for k, st in ipairs(s.stages) do
				for _, e in ipairs(st.exits) do
					local to = e.to or (k + 1)
					if depth[to] and (depth[k] == nil or depth[k] > depth[to] + 1) then depth[k] = depth[to] + 1; changed = true end
				end
			end
		end
		s.stage_depth = depth
	end
	s.view = layout.view   -- 镜头窗口格数（渲染层用：只露 view×view 格、跟着玩家的球滚；格子不放大）
	s.maze = layout.maze and true or nil   -- 迷宫接力（有死胡同盘）：开局说明板多一行、顶上不写 STAGE k / n
	s.deck_n = layout.deck and #layout.deck or nil   -- 对决关：关卡固定给的卡数（4，超过平时的 3 位上限，copy_skills 按它放行）
	if s.mode == "build" then s.deck_n = #config.ITEM_IDS end   -- 道具关三样都带，不受第 3 位是否花钱开限制
	s.speed_k = layout.speed   -- 球速倍率（建队时写进 team.speed_k）

	for t = 1, s.n do
		local ball
		if layout.spawn then
			local x, y = layout.spawn(t, function() return rng.next(s.rng) end)
			ball = { x = x, y = y, dx = 1, dy = 0 }
		else
			local qx, qy, qw, qh = layout.bounds(t)
			ball = { x = qx + 3 + rng.next(s.rng) * (qw - 6), y = qy + 3 + rng.next(s.rng) * (qh - 6), dx = 1, dy = 0 }
		end
		local a = rng.next(s.rng) * math.pi * 2
		set_direction(ball, math.cos(a), math.sin(a))
		local list = (t == config.PLAYER_TEAM) and (opts and opts.loadout) or (opts and opts.enemies and opts.enemies[t] and opts.enemies[t].skills)
		s.teams[t] = {
			speed_k = layout.speed,
			id = t,
			balls = s.mode == "build" and {} or { ball },        -- 道具关没有球
			skills = s.track and {} or copy_skills(list, s.deck_n, s.mode == "build"),
			stage = 1,                                -- 跑道接力：现在在第几盘
			cd = {},                                  -- 技能 id → 剩余冷却秒
			turn_cd = 0,
			accel_left = 0, accel_mult = 1,           -- 加速
			bomb_left = 0, bomb_level = 0,            -- 炸弹在场 / 等级（只主球；见 ball_hit）
			giant_left = 0, giant_level = 0,          -- 巨型（全部球；穿透只主球）
			split_left = 0,                           -- 分身窗口（到时副球消失）
			shatter_left = 0, shatter_level = 0,      -- 分裂球窗口（2026-11-04 晚）
			snow_left = 0, snow_level = 0, snow_n = 0,  -- 滚雪球窗口 / 等级 / 长了几圈
			slow_left = 0, slow_factor = 1,           -- 被冰冻波减速
			frozen_left = 0,                          -- 被三级冰冻冻住
		}
		if s.mode == "build" then   -- 道具关：每队出生区中央自带一门大炮（球的出生点就是出生区里，取它所在格）
			local lv = 1
			for _, sk in ipairs(s.teams[t].skills) do if sk.id == "cannon" then lv = sk.level end end
			local h = math.floor(BUILD.CANNON_SIZE / 2)
			local lo_ = 1 + math.floor((BUILD.CANNON_SIZE - 1) / 2)
			local ci = math.max(lo_, math.min(s.W - math.floor(BUILD.CANNON_SIZE / 2), math.floor(ball.x) + 1))
			local cj = math.max(lo_, math.min(s.H - math.floor(BUILD.CANNON_SIZE / 2), math.floor(ball.y) + 1))
			M.add_struct(s, t, "cannon", ci, cj, lv)
		end
	end
	return s
end

-- ---------------------------------------------------------------- 道具关（build 模式，用户 2026-11-03；设计稿 docs/superpowers/specs/2026-11-03-clashdoz-build-mode-design.md）
-- s.build.structs = { { id, kind = "cannon"|"amp", team, i, j, x, y, level, angle, fire_t, mult } }，by_cell[idx] = struct
-- s.build.bullets = { { team, x, y, dx, dy, left（剩余秒）, bounce（剩余反弹次数）, amped = { [amp_id] = true } } }
-- s.build.soldiers = { { team, x, y, dx, dy, target = struct_id } }
local function cell_ok(s, i, j) return in_board(s, i, j) and s.grid[i][j] ~= false end

--- 装置脚印：大炮 3×3（CANNON_SIZE）；放大器是 1×GATE_LEN 的门，horiz = true 横着（格 i-1..i+2 同一行）否则竖着。回调 fn(i, j)
local function footprint(kind, i, j, fn, horiz)
	if kind == "turret" then fn(i, j); return end   -- 球关炮台：1 格
	if kind == "cannon" then   -- n×n，锚点格 (i, j) 在偏左下（n 偶数时 i..i+1、奇数时 i-1..i+1）
		local n = BUILD.CANNON_SIZE
		local lo = -math.floor((n - 1) / 2)
		for di = lo, lo + n - 1 do for dj = lo, lo + n - 1 do fn(i + di, j + dj) end end
	else
		local n = BUILD.GATE_LEN
		for k = 0, n - 1 do
			local off = k - math.floor((n - 1) / 2)
			if horiz then fn(i + off, j) else fn(i, j + off) end
		end
	end
end
M.footprint = footprint

--- 炮口朝向：对着所有非己方格（含中立、空洞除外）的重心；没有非己方格就朝棋盘中心
local function face_enemy(s, team_id, x, y)
	local sx, sy, n = 0, 0, 0
	for i = 1, s.W do
		local col = s.grid[i]
		for j = 1, s.H do
			local v = col[j]
			if v ~= false and v ~= TRACK and v ~= team_id then sx, sy, n = sx + i - 0.5, sy + j - 0.5, n + 1 end
		end
	end
	local tx, ty = s.W / 2, s.H / 2
	if n > 0 then tx, ty = sx / n, sy / n end
	local dx, dy = tx - x, ty - y
	if dx * dx + dy * dy < 1e-6 then dy = 1 end
	return math.atan2(dy, dx)
end

--- 门的朝向：垂直于炮口方向（敌人在上下 → 横门；在左右 → 竖门）
local function gate_horiz(s, team_id, x, y)
	local a = face_enemy(s, team_id, x, y)
	return math.abs(math.sin(a)) >= math.abs(math.cos(a))
end

--- 装置几何中心（格坐标）：n 偶数时在格线上
local function struct_center(kind, i, j)
	local n = kind == "cannon" and BUILD.CANNON_SIZE or 1
	local off = (n - 1) / 2 - math.floor((n - 1) / 2)
	return i - 0.5 + off, j - 0.5 + off
end
M.struct_center = struct_center
--- 能不能把 kind 放在格 (i, j)：脚印全在棋盘里、全是 team_id 的格、没压别的装置；没超每队上限。face（可选）= 玩家拖出来的朝向，门按它定横竖
function M.can_place(s, team_id, kind, i, j, face)
	local b = s.build
	if not b then return false end
	local ok = true
	local horiz = nil
	if kind == "amp" then horiz = face and (math.abs(math.sin(face)) >= math.abs(math.cos(face))) or gate_horiz(s, team_id, i - 0.5, j - 0.5) end
	footprint(kind, i, j, function(a, c)
		if not cell_ok(s, a, c) or s.grid[a][c] ~= team_id or b.by_cell[M.cell_index(a, c)] then ok = false end
	end, horiz)
	if not ok then return false end
	local cap = kind == "cannon" and BUILD.CANNON_MAX or (kind == "turret" and BUILD.TURRET_MAX or BUILD.AMP_MAX)
	local n = 0
	for _, st in ipairs(b.structs) do if st.team == team_id and st.kind == kind then n = n + 1 end end
	return n < cap
end

--- 放一个装置（起始炮 / 放置指令都走这里）；face（可选）= 玩家定的炮口朝向 / 门的朝向；返回 struct
function M.add_struct(s, team_id, kind, i, j, level, face)
	local b = s.build
	local cx, cy = struct_center(kind, i, j)
	local st = { id = b.next_id, kind = kind, team = team_id, i = i, j = j, x = cx, y = cy, level = level or 1 }
	b.next_id = b.next_id + 1
	local def_ = ITEMS[kind] or SKILLS[kind]
	st.hp = def_.hp and def_.hp[st.level] or 1; st.hp_max = st.hp   -- 原版：炮 100 / 门 300 血，敌方子弹打脚印扣血
	if kind == "turret" then   -- 球关炮台：360° 慢转，活 dur 秒
		st.angle = rng.next(s.rng) * 2 * math.pi
		st.fire_t = 0.4
		st.dur = SKILLS.turret.dur[st.level]; st.left = st.dur
	elseif kind == "cannon" then
		st.face = face or face_enemy(s, team_id, st.x, st.y)
		st.sweep = (rng.next(s.rng) * 2 - 1) * ITEMS.cannon.arc[st.level]   -- 扇区里的当前偏角
		st.sweep_dir = rng.next(s.rng) < 0.5 and -1 or 1
		st.angle = st.face + st.sweep
		st.fire_t = 0.3 + rng.next(s.rng) * 0.3
	else
		st.mult = ITEMS.amp.mult[st.level]
		st.horiz = face and (math.abs(math.sin(face)) >= math.abs(math.cos(face))) or gate_horiz(s, team_id, st.x, st.y)
	end
	b.structs[#b.structs + 1] = st
	st.cells = {}
	footprint(kind, i, j, function(a, c) local idx = M.cell_index(a, c); b.by_cell[idx] = st; s.locked[idx] = true; st.cells[#st.cells + 1] = { a, c } end, st.horiz)   -- 脚印锁定：子弹染不掉，打到是扣装置的血
	s.events[#s.events + 1] = { build = "place", kind = kind, team = team_id, x = st.x, y = st.y, level = st.level, id = st.id }
	return st
end

remove_struct = function(s, st, why)
	local b = s.build
	for k, v in ipairs(b.structs) do if v == st then table.remove(b.structs, k); break end end
	footprint(st.kind, st.i, st.j, function(a, c)
		local idx = M.cell_index(a, c)
		if b.by_cell[idx] == st then b.by_cell[idx] = nil end
		s.locked[idx] = nil
	end, st.horiz)
	s.events[#s.events + 1] = { build = why or "die", kind = st.kind, team = st.team, x = st.x, y = st.y, id = st.id }
end

--- 队 team_id 从 (x, y) 朝 (dx, dy) 发一颗子弹（大炮开火 / 放大器复制 / 测试用）；每队同时在飞的上限 BULLET_MAX
function M.add_bullet(s, team_id, x, y, dx, dy, level, left, bounce, amped, dmg)
	local b = s.build
	local n = 0
	for _, bl in ipairs(b.bullets) do if bl.team == team_id then n = n + 1 end end
	if n >= BUILD.BULLET_MAX then return nil end
	local len = math.sqrt(dx * dx + dy * dy); if len < 1e-6 then dx, dy, len = 1, 0, 1 end
	local lv = level or 1
	local bl = { team = team_id, x = x, y = y, dx = dx / len, dy = dy / len, left = left or BUILD.BULLET_LIFE, bounce = bounce or ITEMS.cannon.bounce[lv], dmg = dmg or ITEMS.cannon.damage[lv], amped = amped and setmetatable({}, { __index = amped }) or {} }
	b.bullets[#b.bullets + 1] = bl
	return bl
end

--- 离格 (ti, tj) 最近的 team_id 自己的格（士兵出发点）；没有返回 nil
local function nearest_own_cell(s, team_id, ti, tj)
	local best, bd
	for i = 1, s.W do
		local col = s.grid[i]
		for j = 1, s.H do
			if col[j] == team_id then
				local d = (i - ti) ^ 2 + (j - tj) ^ 2
				if not bd or d < bd then best, bd = { i, j }, d end
			end
		end
	end
	return best
end

--- 放道具（command "cast" 在道具关走这里）：cannon / amp 点己方无装置的格；soldier 点敌方大炮。成功才进冷却。
local function place_item(s, team, sk, x, y, ax, ay)
	if x == nil or y == nil then return false end
	local face = nil   -- 玩家按住拖出来的朝向（用户 2026-11-03 晚：有些角度打不到 → 自己定方向）
	if ax and ay and (ax * ax + ay * ay) > 1e-6 then face = math.atan2(ay, ax) end
	local i, j = math.floor(x) + 1, math.floor(y) + 1
	if not cell_ok(s, i, j) then return false end
	local idx = M.cell_index(i, j)
	local here = s.build.by_cell[idx]
	if sk.id == "soldier" then
		if not here or here.kind ~= "cannon" or here.team == team.id then return false end
		local from = nearest_own_cell(s, team.id, i, j)
		if not from then return false end
		local fx, fy = from[1] - 0.5, from[2] - 0.5
		local dx, dy = here.x - fx, here.y - fy
		local len = math.sqrt(dx * dx + dy * dy); if len < 1e-6 then dx, dy, len = 1, 0, 1 end
		local n = ITEMS.soldier.count[sk.level]
		local px, py = -dy / len, dx / len   -- 横向排开
		for k = 1, n do
			local off = (k - (n + 1) / 2) * 0.5
			s.build.soldiers[#s.build.soldiers + 1] = { team = team.id, x = fx + px * off, y = fy + py * off, dx = dx / len, dy = dy / len, target = here.id }
		end
		s.events[#s.events + 1] = { build = "march", team = team.id, x = fx, y = fy, to_x = here.x, to_y = here.y, count = n }
	else
		if not M.can_place(s, team.id, sk.id, i, j, face) then return false end
		M.add_struct(s, team.id, sk.id, i, j, sk.level, face)
	end
	team.cd[sk.id] = M.skill_cd(team.id, sk.id, sk.level)
	return true
end

--- 子弹走一小步：染经过的格；出棋盘 / 进空洞 → 反弹（还有次数）或消失；飞过己方放大器 → 复制；打中敌方士兵 → 士兵没了。返回 false = 子弹没了
local function bullet_substep(s, bl, step)
	local nx, ny = bl.x + bl.dx * step, bl.y + bl.dy * step
	local ni, nj = math.floor(nx) + 1, math.floor(ny) + 1
	if not cell_ok(s, ni, nj) then
		if bl.bounce <= 0 then return false end
		bl.bounce = bl.bounce - 1
		-- 哪个轴出去就翻哪个轴（两个都出去就都翻）
		local xi = math.floor(bl.x + bl.dx * step) + 1
		local yj = math.floor(bl.y + bl.dy * step) + 1
		local x_bad = not cell_ok(s, xi, math.floor(bl.y) + 1)
		local y_bad = not cell_ok(s, math.floor(bl.x) + 1, yj)
		if x_bad or not y_bad then bl.dx = -bl.dx end
		if y_bad or not x_bad then bl.dy = -bl.dy end
		return true
	end
	bl.x, bl.y = nx, ny
	local b = s.build
	-- 先看有没有打中敌方士兵（一颗子弹打掉一个，子弹也没了）
	if #b.soldiers > 0 then
		local r2 = BUILD.SOLDIER_HIT * BUILD.SOLDIER_HIT
		for k = #b.soldiers, 1, -1 do
			local so = b.soldiers[k]
			if so.team ~= bl.team then
				local dx, dy = so.x - bl.x, so.y - bl.y
				if dx * dx + dy * dy <= r2 then
					table.remove(b.soldiers, k)
					s.events[#s.events + 1] = { build = "die", kind = "soldier", team = so.team, x = so.x, y = so.y }
					return false
				end
			end
		end
	end
	-- 不穿透（用户 2026-11-03 二改，照原版）：进了非己方格 → 伤害记到那格上，累计够 CELL_HP 就染（原版格子有血量）、子弹消失；敌方炮台脚印（锁定）→ 直接消失不染
	if s.grid[ni][nj] ~= bl.team then
		local idx = M.cell_index(ni, nj)
		local painted = false
		local st = s.locked[idx] and b.by_cell[idx] or nil
		if st then   -- 打到敌方装置：扣它的血（原版炮 100 / 门 300），打空就没了
			st.hp = st.hp - (bl.dmg or 1)
			s.events[#s.events + 1] = { build = "hurt", kind = st.kind, team = st.team, by = bl.team, x = nx, y = ny, id = st.id, hp = st.hp, hp_max = st.hp_max }
			if st.hp <= 0 then remove_struct(s, st, "die") end
		elseif not s.locked[idx] then
			local d = (b.dmg_team[idx] == bl.team and b.dmg[idx] or 0) + (bl.dmg or 1)   -- 别队打过的伤害不算（各打各的）
			if d >= (BUILD.CELL_HP or 1) then painted = hit_cell(s, ni, nj, bl.team) else b.dmg[idx] = d; b.dmg_team[idx] = bl.team end
		end
		s.events[#s.events + 1] = { build = "hit", team = bl.team, x = nx, y = ny, painted = painted, i = ni, j = nj }
		return false
	end
	local st = b.by_cell[M.cell_index(ni, nj)]
	if st and st.kind == "amp" and st.team == bl.team and not bl.amped[st.id] then
		bl.amped[st.id] = true
		local base = math.atan2(bl.dy, bl.dx)
		for k = 1, st.mult - 1 do   -- 复制品在原弹两侧交替张开：+1、-1、+2、-2 … 个 AMP_SPREAD
			local a = base + math.ceil(k / 2) * BUILD.AMP_SPREAD * (k % 2 == 1 and 1 or -1)
			M.add_bullet(s, bl.team, bl.x, bl.y, math.cos(a), math.sin(a), nil, bl.left, bl.bounce, bl.amped, bl.dmg)
		end
		s.events[#s.events + 1] = { build = "amp", team = bl.team, x = st.x, y = st.y, mult = st.mult }
	end
	return true
end

local function find_struct(s, id)
	for _, st in ipairs(s.build.structs) do if st.id == id then return st end end
	return nil
end

local function step_build(s, dt)
	local b = s.build
	-- 大炮：自转 + 开火（被冻住的队不开火）
	for k = #b.structs, 1, -1 do
		local st = b.structs[k]
		if st.kind == "turret" then   -- 球关炮台：自转 + 慢慢打 + 到时消失（被冻住的队的炮台也停）
			st.left = st.left - dt
			if st.left <= 0 then remove_struct(s, st, "die")
			elseif not M.is_frozen(s, s.teams[st.team]) then
				st.angle = st.angle + BUILD.TURRET_ROT * dt
				st.fire_t = st.fire_t - dt
				if st.fire_t <= 0 then
					st.fire_t = st.fire_t + 1 / SKILLS.turret.rate[st.level]
					local dx, dy = math.cos(st.angle), math.sin(st.angle)
					M.add_bullet(s, st.team, st.x + dx * 1.1, st.y + dy * 1.1, dx, dy, st.level, nil, nil, nil, SKILLS.turret.damage[st.level])
				end
			end
		elseif st.kind == "cannon" and not M.is_frozen(s, s.teams[st.team]) then
			local arc = ITEMS.cannon.arc[st.level]
			st.sweep = st.sweep + st.sweep_dir * BUILD.CANNON_SWEEP * dt   -- 扇区里来回扫（三角波，原版 maxAngle / rotationSpeed）
			if st.sweep > arc then st.sweep, st.sweep_dir = arc, -1 elseif st.sweep < -arc then st.sweep, st.sweep_dir = -arc, 1 end
			st.angle = st.face + st.sweep
			st.fire_t = st.fire_t - dt
			if st.fire_t <= 0 then
				st.fire_t = st.fire_t + 1 / ITEMS.cannon.rate[st.level]
				local dx, dy = math.cos(st.angle), math.sin(st.angle)
				local r = BUILD.CANNON_SIZE / 2 + 0.6   -- 从脚印外沿发出
				M.add_bullet(s, st.team, st.x + dx * r, st.y + dy * r, dx, dy, st.level, nil, nil, nil, ITEMS.cannon.damage[st.level])
			end
		end
	end
	-- 子弹
	local dist = BUILD.BULLET_SPEED * dt
	local sub = math.max(1, math.ceil(dist / 0.4))
	for k = #b.bullets, 1, -1 do
		local bl = b.bullets[k]
		bl.left = bl.left - dt
		local alive = bl.left > 0
		for _ = 1, sub do
			if not alive then break end
			alive = bullet_substep(s, bl, dist / sub)
		end
		if not alive then table.remove(b.bullets, k) end
	end
	-- 士兵：直走；目标炮没了 / 已是自己的 → 散；出棋盘 / 掉洞 → 没了；到了 → 占
	local sd = BUILD.SOLDIER_SPEED * dt
	for k = #b.soldiers, 1, -1 do
		local so = b.soldiers[k]
		local st = find_struct(s, so.target)
		local gone = false
		if not st or st.team == so.team then gone = true
		else
			so.x, so.y = so.x + so.dx * sd, so.y + so.dy * sd
			local ci, cj = math.floor(so.x) + 1, math.floor(so.y) + 1
			if not cell_ok(s, ci, cj) then
				gone = true
				s.events[#s.events + 1] = { build = "die", kind = "soldier", team = so.team, x = so.x, y = so.y }
			else
				local dx, dy = st.x - so.x, st.y - so.y
				if dx * dx + dy * dy <= BUILD.CAPTURE_R * BUILD.CAPTURE_R then
					local from = st.team
					st.team = so.team
					footprint(st.kind, st.i, st.j, function(a, c) if cell_ok(s, a, c) then set_cell(s, a, c, so.team) end end, st.horiz)
					st.face = face_enemy(s, so.team, st.x, st.y); st.sweep = 0; st.angle = st.face   -- 换主人后掉头
					s.events[#s.events + 1] = { build = "capture", kind = st.kind, team = so.team, from = from, x = st.x, y = st.y, id = st.id }
					gone = true
				end
			end
		end
		if gone then table.remove(b.soldiers, k) end
	end
end

-- ---------------------------------------------------------------- 技能效果
local function offsets(width)   -- 闪电带宽 → 垂直于前进方向的偏移：1 → {0}，2 → {0,1}，3 → {-1,0,1}
	if width <= 1 then return { 0 } elseif width == 2 then return { 0, 1 } end
	return { -1, 0, 1 }
end

local function cast_lightning(s, team, level)
	local T = SKILLS.lightning
	local b = team.balls[1]
	local ci, cj = math.floor(b.x) + 1, math.floor(b.y) + 1
	local offs = offsets(T.width[level])
	local dirs = { { 0, 1 }, { 0, -1 } }
	if T.dirs[level] >= 4 then dirs[#dirs + 1] = { 1, 0 }; dirs[#dirs + 1] = { -1, 0 } end
	local done = {}
	local function band(i, j, d)   -- 沿方向 d 走到 (i, j) 时打一整条带
		for _, o in ipairs(offs) do
			local bi, bj = i, j   -- 偏移垂直于 d（上下两道同列、左右两道同行，不随方向翻转）
			if d[1] == 0 then bi = i + o else bj = j + o end
			if in_board(s, bi, bj) then
				local idx = M.cell_index(bi, bj)
				if not done[idx] then done[idx] = true; hit_cell(s, bi, bj, team.id) end
			end
		end
	end
	local lens = {}
	for k, d in ipairs(dirs) do
		local i, j = ci, cj
		if k % 2 == 0 then i, j = ci + d[1], cj + d[2] end   -- 反向那道从中心旁边一格起（沿 d 走一格），中心带由正向那道打。2026-11-01 修：原来写成 ci - d 是往回退一格，主球贴上边/右边时起点出界、整条臂丢失（用户："有时候闪电没把路全挡住"）
		local n = 0
		while in_board(s, i, j) and s.grid[i][j] ~= false do   -- 出界 / 空洞停
			band(i, j, d); n = n + 1
			i, j = i + d[1], j + d[2]
		end
		lens[k] = n
	end
	s.events[#s.events + 1] = { team = team.id, skill = "lightning", level = level, x = b.x, y = b.y, i = ci, j = cj, width = T.width[level], dirs = dirs, lens = lens }
end

local function land_fire(s, f)
	local ci, cj = math.floor(f.x) + 1, math.floor(f.y) + 1
	local reach = math.ceil(f.radius)
	for i = ci - reach, ci + reach do
		for j = cj - reach, cj + reach do
			local dx, dy = i - ci, j - cj
			if dx * dx + dy * dy <= f.radius * f.radius then hit_cell(s, i, j, f.team) end
		end
	end
	s.events[#s.events + 1] = { team = f.team, skill = "fire", level = f.level, x = f.x, y = f.y, radius = f.radius, phase = "hit" }
end

--- 收副球：分身的副球（temp）；all = true 连分裂球的小球（shard）一起收（收局用）——放分身 / 分身到期不碰分裂小球
local function remove_temp(team, all)
	for k = #team.balls, 1, -1 do local b = team.balls[k]; if b.temp and (all or not b.shard) then table.remove(team.balls, k) end end
end

--- 链式闪电目标：场上全部敌球（含分身小球），从主球起贪心最近一颗接一颗排序。返回 { { ball, team }, … }
local function chain_targets(s, team)
	local pool, out = {}, {}
	for _, other in ipairs(s.teams) do
		if other.id ~= team.id then for _, b in ipairs(other.balls) do pool[#pool + 1] = { ball = b, team = other.id } end end
	end
	local fx, fy = team.balls[1].x, team.balls[1].y
	while #pool > 0 do
		local bi, bd
		for i, p in ipairs(pool) do
			local d = (p.ball.x - fx) ^ 2 + (p.ball.y - fy) ^ 2
			if not bd or d < bd then bi, bd = i, d end
		end
		local p = table.remove(pool, bi)
		out[#out + 1] = p
		fx, fy = p.ball.x, p.ball.y
	end
	return out
end

local function cast(s, team, sk, x, y)
	local id, level = sk.id, sk.level
	local T = SKILLS[id]
	local main = team.balls[1]
	local ev = { team = team.id, skill = id, level = level, x = main.x, y = main.y }
	if id == "freeze" then
		local far = 0
		local N = s.N or GRID
		for _, c in ipairs({ { 0, 0 }, { N, 0 }, { 0, N }, { N, N } }) do
			far = math.max(far, math.sqrt((c[1] - main.x) ^ 2 + (c[2] - main.y) ^ 2))
		end
		s.waves[#s.waves + 1] = { team = team.id, level = level, x = main.x, y = main.y, r = 0, max_r = far + 1, hit = {} }
		ev.max_r = far + 1
	elseif id == "split" then
		remove_temp(team)
		team.split_left = T.window[level]
		local own = 0   -- 只数主球 + 分身，不数分裂小球（用户 2026-11-05 夜：先放分裂球再放分身，分身一颗都不生）
		for _, b in ipairs(team.balls) do if not b.shard then own = own + 1 end end
		local want = T.count[level] - own
		for k = 1, want do
			if #team.balls >= config.MAX_BALLS_PER_TEAM then break end
			local child = { x = main.x, y = main.y, dx = main.dx, dy = main.dy, temp = true }
			rotate(child, k * (2 * math.pi / (want + 1)) + (rng.next(s.rng) - 0.5) * 0.2)
			team.balls[#team.balls + 1] = child
		end
		ev.window = T.window[level]
	elseif id == "accel" then
		team.accel_left, team.accel_mult = T.dur[level], T.mult[level]
		ev.dur = T.dur[level]
	elseif id == "bomb" then
		team.bomb_left, team.bomb_level = T.dur[level], level
		ev.dur = T.dur[level]
	elseif id == "giant" then
		team.giant_left, team.giant_level = T.dur[level], level
		ev.dur = T.dur[level]
	elseif id == "fire" then
		s.fires[#s.fires + 1] = { team = team.id, level = level, x = x, y = y, radius = T.radius[level], left = config.FIRE_DELAY }
		ev.x, ev.y, ev.radius, ev.phase = x, y, T.radius[level], "aim"
	elseif id == "lightning" then
		cast_lightning(s, team, level)
		ev = nil
	elseif id == "teleport" then
		ev.from_x, ev.from_y = main.x, main.y
		main.x, main.y = x, y
		ball_hit(s, team, main, math.floor(x) + 1, math.floor(y) + 1)
	elseif id == "shatter" then
		team.shatter_left, team.shatter_level = T.dur[level], level
		ev.dur = T.dur[level]
	elseif id == "snowball" then   -- 等离子球没有时限（用户 2026-11-05 夜：只有撞够次数炸掉才结束）：snow_left 只是"在场"标志，炸 / 终局才清
		team.snow_left, team.snow_level, team.snow_n = 1, level, 0
	elseif id == "shock" then   -- 以主球为中心朝正前方张开 arc 度的圆弧往外扩（用户 2026-11-05）：弧拆成 n 条射线（最远处相邻 0.5 格），每条碰到第一个非己方格染了就消失
		local a0 = math.atan2(main.dy, main.dx)
		local far = 0
		local N = s.N or GRID
		for _, c in ipairs({ { 0, 0 }, { N, 0 }, { 0, N }, { N, N } }) do far = math.max(far, math.sqrt((c[1] - main.x) ^ 2 + (c[2] - main.y) ^ 2)) end
		local half = math.rad(T.arc[level]) / 2
		local n = math.max(8, math.ceil(2 * half * (far + 1) / 0.5))
		local rays = {}
		for k = 1, n do rays[k] = true end
		s.shocks[#s.shocks + 1] = { team = team.id, level = level, x = main.x, y = main.y, a0 = a0, half = half, r = 0, max_r = far + 1, n = n, rays = rays, alive = n, hit = {}, hit_cells = {} }
		ev.a0, ev.half, ev.max_r, ev.dx, ev.dy = a0, half, far + 1, main.dx, main.dy
	elseif id == "chain" then   -- command 里已保证有目标；链头从主球出发一颗颗飞（step_chains），打中才停
		local pts = chain_targets(s, team)
		s.chains[#s.chains + 1] = { team = team.id, level = level, x0 = main.x, y0 = main.y, hx = main.x, hy = main.y, targets = pts, k = 1, hits = {}, left = nil }
		ev.n, ev.stun = #pts, T.stun[level]
	elseif id == "turret" then   -- 球关炮台：落在点的那格（command 里已校验是自己的空格）
		local st = M.add_struct(s, team.id, "turret", math.floor(x) + 1, math.floor(y) + 1, level)
		ev.x, ev.y, ev.dur = st.x, st.y, st.dur
	end
	if ev then s.events[#s.events + 1] = ev end
end

--- 技能 id 第 level 级的冷却秒数：电脑队（team_id ≠ 玩家）先查 config.BOT_SKILL_CD 覆盖表（冰冻 18/20/24），没列的两边同表
function M.skill_cd(team_id, id, level)
	local bot = team_id ~= config.PLAYER_TEAM and config.BOT_SKILL_CD and config.BOT_SKILL_CD[id]
	return (bot or def(id).cd)[level]
end

--- 位 slot 的技能现在能不能放（有、没结束、没被冻、冷却到了）
function M.can_cast(s, team, slot)
	local sk = team.skills[slot]
	return sk ~= nil and not s.over and not M.is_frozen(s, team) and (team.cd[sk.id] or 0) <= 0
		and not (sk.id == "snowball" and (team.snow_left or 0) > 0)   -- 等离子球在场时不能再放（没时限，炸完才能放下一颗）
end

--- 目标格 (x, y) 是否在棋盘内且不是空洞
local function valid_target(s, x, y)
	if x == nil or y == nil then return false end
	local i, j = math.floor(x) + 1, math.floor(y) + 1
	return in_board(s, i, j) and s.grid[i][j] ~= false
end

-- Applies one command for a team. Returns true if it was accepted.
--   { type = "turn", x = cell_x, y = cell_y }      点一下：全队球直接朝那点（冷却 TURN_COOLDOWN）
--   { type = "steer", x = cell_x, y = cell_y, dt = 秒 }   按住拖动：朝那点限速转，不占冷却
--   { type = "cast", slot = n, x = cell_x, y = cell_y }   放第 n 位技能（火焰 / 传送要 x, y）
function M.command(s, team_id, cmd)
	local team = s.teams[team_id]
	if s.over then return false end
	-- everything below acts on the board, which is impossible while frozen
	if M.is_frozen(s, team) then return false end
	if (cmd.type == "turn" or cmd.type == "steer") and s.mode == "build" then return false end   -- 道具关没有球可转
	if cmd.type == "aim" then   -- 道具关：点自己的炮再点一点 → 炮口转过去（{ x, y = 炮所在格坐标, tx, ty = 目标点 }）
		if cmd.x == nil or cmd.tx == nil then return false end
		local st = s.build.by_cell[M.cell_index(math.floor(cmd.x) + 1, math.floor(cmd.y) + 1)]
		if not st or st.kind ~= "cannon" or st.team ~= team_id then return false end
		local dx, dy = cmd.tx - st.x, cmd.ty - st.y
		if dx * dx + dy * dy < 1e-6 then return false end
		st.face = math.atan2(dy, dx); st.sweep = 0; st.angle = st.face
		s.events[#s.events + 1] = { build = "aim", team = team_id, x = st.x, y = st.y, id = st.id }
		return true
	end
	if cmd.type == "turn" then
		if team.turn_cd > 0 then return false end
		for _, ball in ipairs(team.balls) do set_direction(ball, cmd.x - ball.x, cmd.y - ball.y, slope_min(s, team)) end
		team.turn_cd = s.track and config.TRACK_TURN_COOLDOWN or config.TURN_COOLDOWN   -- 跑道关转向更跟手
		return true
	elseif cmd.type == "steer" then   -- 按住拖动：每帧朝 (x, y) 转，最多 STEER_RATE × dt 弧度；不占急转冷却（用户 2026-11-03）
		local lim = config.STEER_RATE * (cmd.dt or config.FIXED_DT)
		for _, ball in ipairs(team.balls) do
			local tx, ty = cmd.x - ball.x, cmd.y - ball.y
			if tx * tx + ty * ty > 0.09 then
				local want, cur = math.atan2(ty, tx), math.atan2(ball.dy, ball.dx)
				local d = want - cur
				while d > math.pi do d = d - 2 * math.pi end
				while d < -math.pi do d = d + 2 * math.pi end
				d = math.max(-lim, math.min(lim, d))
				set_direction(ball, math.cos(cur + d), math.sin(cur + d), slope_min(s, team))
			end
		end
		return true
	elseif cmd.type == "cast" then
		if not M.can_cast(s, team, cmd.slot) then return false end
		local sk = team.skills[cmd.slot]
		if ITEMS[sk.id] then return s.mode == "build" and place_item(s, team, sk, cmd.x, cmd.y, cmd.ax, cmd.ay) end   -- 道具关：放大炮 / 放大器 / 派兵（ax, ay = 拖出来的朝向，可选）
		if sk.id == "turret" and not M.can_place(s, team_id, "turret", math.floor(cmd.x or -1) + 1, math.floor(cmd.y or -1) + 1) then return false end   -- 炮台只能放自己的空格（没放上不进冷却）
		if team_id ~= config.PLAYER_TEAM and config.PLAYER_ONLY_SKILLS[sk.id] then return false end   -- 炸弹只给玩家（冰冻 2026-11-03 起电脑也能放）
		if sk.id == "chain" and #chain_targets(s, team) == 0 then return false end   -- 链电：场上没敌球放不出（不进冷却）
		if SKILLS[sk.id].target and not valid_target(s, cmd.x, cmd.y) then return false end
		if sk.id == "teleport" then   -- 一/二级限距（平衡实验 2026-10-28）
			local main = team.balls[1]
			local dx, dy = cmd.x - main.x, cmd.y - main.y
			if dx * dx + dy * dy > SKILLS.teleport.range[sk.level] ^ 2 then return false end
		end
		team.cd[sk.id] = M.skill_cd(team_id, sk.id, sk.level)
		cast(s, team, sk, cmd.x, cmd.y)
		return true
	end
	return false
end

-- ---------------------------------------------------------------- 推进
local function step_waves(s, dt)
	for k = #s.waves, 1, -1 do
		local w = s.waves[k]
		w.r = w.r + config.WAVE_SPEED * dt
		local T = SKILLS.freeze
		for _, other in ipairs(s.teams) do
			if other.id ~= w.team and not w.hit[other.id] then
				for _, b in ipairs(other.balls) do
					local dx, dy = b.x - w.x, b.y - w.y
					if dx * dx + dy * dy <= w.r * w.r then
						w.hit[other.id] = true
						if (other.snow_n or 0) > 0 then other.snow_n = 0 end   -- 滚雪球被冰冻波碰到缩回
						if T.freeze[w.level] then other.frozen_left = math.max(other.frozen_left, T.dur[w.level])
						else other.slow_left, other.slow_factor = T.dur[w.level], T.factor[w.level] end
						break
					end
				end
			end
		end
		if w.r >= w.max_r then table.remove(s.waves, k) end
	end
end

local function step_fires(s, dt)
	for k = #s.fires, 1, -1 do
		local f = s.fires[k]
		f.left = f.left - dt
		if f.left <= 0 then land_fire(s, f); table.remove(s.fires, k) end
	end
end

--- 角度差（-π..π）
local function ang_diff(a, b)
	local d = a - b
	while d > math.pi do d = d - 2 * math.pi end
	while d < -math.pi do d = d + 2 * math.pi end
	return d
end
--- 第 k 条射线的角度
function M.shock_ray_angle(w, k) return w.a0 - w.half + (k - 0.5) * (2 * w.half / w.n) end
--- 冲击波圆弧推进（用户 2026-11-05 二改：只吃第一排）：每条还活着的射线从 r0 走到 r（每 0.5 格取样），出界 / 空洞 → 射线没了；
--- 走进第一个非己方格（或这道波已经打过的格）→ 把那格染了、射线没了；己方格照穿。射线全没了这道波就结束。
--- 弧内还活着的射线前面的敌球被沿径向推开 + 停 SHOCK_STUN 秒（每颗只撞一次）——先判球再推射线，站在第一排上的球也会被撞
local function step_shocks(s, dt)
	for k = #s.shocks, 1, -1 do
		local w = s.shocks[k]
		local r0 = w.r
		w.r = math.min(w.max_r, w.r + config.SHOCK_SPEED * dt)
		local da = 2 * w.half / w.n
		for _, other in ipairs(s.teams) do
			if other.id ~= w.team then
				for _, b in ipairs(other.balls) do
					if not w.hit[b] then
						local dx, dy = b.x - w.x, b.y - w.y
						local d = math.sqrt(dx * dx + dy * dy)
						if d > r0 - 0.5 and d <= w.r + 1.2 then   -- 往前多看 1.2 格：站在第一排格上的球，射线在格子边缘就消失了也要撞到它
							local rel = ang_diff(math.atan2(dy, dx), w.a0)
							local idx = math.floor((rel + w.half) / da) + 1
							if idx >= 1 and idx <= w.n and w.rays[idx] then
								w.hit[b] = true
								if d > 1e-6 then set_direction(b, dx, dy) end
								b.stun_left = math.max(b.stun_left or 0, config.SHOCK_STUN)
								if (other.snow_n or 0) > 0 then other.snow_n = 0 end
								s.events[#s.events + 1] = { team = w.team, skill = "shock", phase = "push", x = b.x, y = b.y, victim = other.id }
							end
						end
					end
				end
			end
		end
		for i = 1, w.n do
			if w.rays[i] then
				local a = M.shock_ray_angle(w, i)
				local ca, sa = math.cos(a), math.sin(a)
				local t = r0 + 0.25
				while t <= w.r + 1e-9 and w.rays[i] do
					local ci, cj = math.floor(w.x + ca * t) + 1, math.floor(w.y + sa * t) + 1
					if not in_board(s, ci, cj) or s.grid[ci][cj] == false then
						w.rays[i] = false
					else
						local idx = M.cell_index(ci, cj)
						if w.hit_cells[idx] then w.rays[i] = false
						elseif s.grid[ci][cj] ~= w.team and s.grid[ci][cj] ~= TRACK then
							w.hit_cells[idx] = true
							if hit_cell(s, ci, cj, w.team) then s.events[#s.events + 1] = { team = w.team, skill = "shock", phase = "hit", x = ci - 0.5, y = cj - 0.5 } end
							w.rays[i] = false
						end
					end
					t = t + 0.5
				end
				if not w.rays[i] then w.alive = w.alive - 1 end
			end
		end
		if w.alive <= 0 or w.r >= w.max_r then table.remove(s.shocks, k) end
	end
end

--- 链电推进：链头朝 targets[k] 的当前位置飞（CHAIN_SPEED 格/秒），到了就停住它、记 hit、转向下一颗（一步内够远可以连跳）；
--- 全打完后链只再留 CHAIN_LINGER 秒就消失（被定的球靠自身电笼抖动表现）。目标球已经没了（分身到期）就跳过
local function ball_alive(s, p)
	for _, b in ipairs(s.teams[p.team].balls) do if b == p.ball then return true end end
	return false
end
local function step_chains(s, dt)
	local T = SKILLS.chain
	for k = #s.chains, 1, -1 do
		local c = s.chains[k]
		local budget = config.CHAIN_SPEED * dt
		while c.k <= #c.targets and budget > 0 do
			local p = c.targets[c.k]
			if not ball_alive(s, p) then c.k = c.k + 1
			else
				local dx, dy = p.ball.x - c.hx, p.ball.y - c.hy
				local d = math.sqrt(dx * dx + dy * dy)
				if d <= budget then
					budget = budget - d
					c.hx, c.hy = p.ball.x, p.ball.y
					p.ball.stun_left = math.max(p.ball.stun_left or 0, T.stun[c.level])
					local ot = s.teams[p.team]; if (ot.snow_n or 0) > 0 then ot.snow_n = 0 end
					c.hits[#c.hits + 1] = p
					s.events[#s.events + 1] = { team = c.team, skill = "chain", phase = "hit", x = p.ball.x, y = p.ball.y, victim = p.team, k = #c.hits }
					c.k = c.k + 1
				else
					c.hx, c.hy = c.hx + dx / d * budget, c.hy + dy / d * budget
					budget = 0
				end
			end
		end
		if c.k > #c.targets then   -- 打完：链再留 CHAIN_LINGER 秒就消失（用户 2026-11-05：电不需要一直连着，中了的球自己晃）
			c.left = (c.left or config.CHAIN_LINGER) - dt
			if c.left <= 0 then table.remove(s.chains, k) end
		end
	end
end

local function tick(v, dt) return math.max(0, (v or 0) - dt) end

--- 收局：清掉还在飞的波/火/副球和所有状态
local function finish(s)
	s.waves = {}; s.fires = {}; s.shocks = {}; s.chains = {}
	if s.build then s.build.bullets = {}; s.build.soldiers = {} end
	for _, team in ipairs(s.teams) do
		remove_temp(team, true)
		team.split_left, team.accel_left, team.bomb_left, team.giant_left, team.slow_left, team.frozen_left = 0, 0, 0, 0, 0, 0
		team.shatter_left, team.snow_left, team.snow_n = 0, 0, 0
		for _, b in ipairs(team.balls) do b.stun_left = 0 end
	end
	s.over = true
end

--- 过关方式判定：zone → 目标区全是某队的；race → 某队任一球到星星。返回赢家队号或 nil；顺手更新 s.goal.owned[t]
local function check_goal(s)
	local g = s.goal
	if g.kind == "zone" then
		local owned = {}
		for _, idx in ipairs(g.cells) do
			local i, j = (idx - 1) % GRID + 1, math.floor((idx - 1) / GRID) + 1
			local o = s.grid[i][j]
			if o and o > 0 then owned[o] = (owned[o] or 0) + 1 end
		end
		g.owned = owned
		if g.total > 0 then for t = 1, s.n do if (owned[t] or 0) >= g.total then return t end end end
	elseif g.kind == "race" and g.at then
		local tx, ty = g.at[1] - 0.5, g.at[2] - 0.5
		local last = s.goal_stage or 1
		for _, team in ipairs(s.teams) do
			if (team.stage or 1) == last then   -- 接力：只有到了目标盘才算
				for _, b in ipairs(team.balls) do
					local dx, dy = b.x - tx, b.y - ty
					if dx * dx + dy * dy <= g.r * g.r then return team.id end
				end
			end
		end
	end
	return nil
end

function M.step(s, dt)
	if s.over then return end
	s.elapsed = s.elapsed + dt
	s.time_left = math.max(0, s.time_left - dt)

	-- timers keep running for everyone, frozen or not（冷却照走，冻结是纯损失）
	for _, team in ipairs(s.teams) do
		team.turn_cd = tick(team.turn_cd, dt)
		for id, left in pairs(team.cd) do team.cd[id] = tick(left, dt) end
		team.accel_left = tick(team.accel_left, dt)
		team.bomb_left = tick(team.bomb_left, dt)
		team.giant_left = tick(team.giant_left, dt)
		team.slow_left = tick(team.slow_left, dt)
		team.frozen_left = tick(team.frozen_left, dt)
		if team.split_left > 0 then
			team.split_left = tick(team.split_left, dt)
			if team.split_left <= 0 then remove_temp(team) end
		end
		team.shatter_left = tick(team.shatter_left, dt)
		for k = #team.balls, 1, -1 do   -- 分裂小球到寿命消失
			local b = team.balls[k]
			if b.shard then b.life = b.life - dt; if b.life <= 0 then table.remove(team.balls, k) end end
		end
		for _, b in ipairs(team.balls) do b.boost_left = tick(b.boost_left, dt); b.boost_cd = tick(b.boost_cd, dt); b.portal_cd = tick(b.portal_cd, dt); b.stun_left = tick(b.stun_left, dt) end
	end

	for _, team in ipairs(s.teams) do
		if not M.is_frozen(s, team) then
			local vmax = 0
			for _, b in ipairs(team.balls) do vmax = math.max(vmax, ball_speed(team, b)) end
			local steps = math.max(1, math.ceil(vmax * dt / MAX_STEP))
			local sub_dt = dt / steps
			for _ = 1, steps do
				for _, ball in ipairs(team.balls) do step_ball(s, team, ball, sub_dt) end
			end
		end
	end

	step_waves(s, dt)
	step_fires(s, dt)
	step_shocks(s, dt)
	step_chains(s, dt)
	step_build(s, dt)

	local w = check_goal(s)
	if w then s.winner = w; finish(s) return end
	if s.time_left <= 0 then
		finish(s)   -- 染区 / 竞速到时没达成：无 winner（用户 2026-11-02：没染满不能算过）；排名染区按目标区格数、竞速按路线步数
	end
end

--- 竞速关路线：从目标格 BFS（四邻、只走非空洞格）得到每格到目标的步数表 dist[idx]（到不了 = nil）；按盘缓存在 s 里
--- 跑道接力：第 k 盘目标 = 该盘的出口（分道盘有几个就从几个一起起算），最后一盘 = 星星；非接力竞速：s.grid 上到星星
function M.race_dist(s, k)
	k = k or 1
	s.race_dists = s.race_dists or {}
	if s.race_dists[k] then return s.race_dists[k] end
	local g = s.goal
	if not (g and g.kind == "race" and g.at) then return nil end
	local st = s.stages and s.stages[k]
	local grid = st and st.grid or s.grid
	local tgts = M.forward_exits(s, k) or { g.at }
	local dist, queue, head = {}, {}, 1
	for _, tgt in ipairs(tgts) do dist[M.cell_index(tgt[1], tgt[2])] = 0; queue[#queue + 1] = { tgt[1], tgt[2] } end
	while head <= #queue do
		local c = queue[head]; head = head + 1
		local d = dist[M.cell_index(c[1], c[2])]
		for _, dd in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
			local ni, nj = c[1] + dd[1], c[2] + dd[2]
			if in_board(s, ni, nj) and grid[ni][nj] ~= false then
				local idx = M.cell_index(ni, nj)
				if dist[idx] == nil then dist[idx] = d + 1; queue[#queue + 1] = { ni, nj } end
			end
		end
	end
	s.race_dists[k] = dist
	return dist
end

--- 第 k 盘里通向目标的出口（盘深度比本盘小的；死胡同口不算）；目标盘或没有出口 → nil（目标就是星星）
function M.forward_exits(s, k)
	local st = s.stages and s.stages[k]
	if not st or k == (s.goal_stage or #s.stages) or #st.exits == 0 then return nil end
	local depth, out = s.stage_depth or {}, {}
	for _, e in ipairs(st.exits) do
		local to = e.to or (k + 1)
		if (depth[to] or math.huge) < (depth[k] or math.huge) then out[#out + 1] = e end
	end
	return #out > 0 and out or st.exits
end

--- 队 t 这局算不算过/赢：竞速 = 到了星星、染区 = 染满了（到时没达成就是没过，不能靠"排名第一"混过）；占地 = 排名第一
function M.cleared(s, t)
	local g = s.goal
	if g and (g.kind == "race" or g.kind == "zone") then return s.winner == t end
	return M.ranking(s)[1] == t
end

-- Team ids ordered from most to fewest cells.
function M.ranking(s)
	local order = {}
	for t = 1, s.n do order[t] = t end
	local w = s.winner   -- 染区 / 竞速关：达成目标的队第一，其余按占地
	local g = s.goal
	local dist
	if g and g.kind == "zone" and not w and g.owned then   -- 染区到时没人染满：按目标区里的格数排（没 winner，谁都不算过）
		dist = {}
		for t = 1, s.n do dist[t] = -(g.owned[t] or 0) end
	end
	if g and g.kind == "race" and g.at and not w then   -- 竞速到时没人到：盘数靠前的赢，同盘按路线步数（race_dist，绕墙算进去）最少的赢，同步数按直线
		dist = {}
		local depth = s.stage_depth or {}
		for t = 1, s.n do
			local team = s.teams[t]
			local k = team.stage or 1
			local tgts = M.forward_exits(s, k) or { g.at }
			local field = M.race_dist(s, k)
			local best = math.huge
			for _, b in ipairs(team.balls) do
				local ci, cj = math.floor(b.x) + 1, math.floor(b.y) + 1
				local steps = field and in_board(s, ci, cj) and field[M.cell_index(ci, cj)] or nil
				local e = math.huge
				for _, tgt in ipairs(tgts) do e = math.min(e, (b.x - tgt[1] + 0.5) ^ 2 + (b.y - tgt[2] + 0.5) ^ 2) end
				best = math.min(best, (steps or 1e3) * 1e3 + math.min(e, 999))
			end
			dist[t] = (depth[k] or 0) * 1e9 + best
		end
	end
	table.sort(order, function(a, b)
		if w and (a == w or b == w) then return a == w end
		if dist and dist[a] ~= dist[b] then return dist[a] < dist[b] end
		if s.counts[a] ~= s.counts[b] then return s.counts[a] > s.counts[b] end
		return a < b
	end)
	return order
end

return M
