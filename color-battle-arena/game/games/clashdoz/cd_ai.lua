-- games/clashdoz/cd_ai.lua（移植自 github.com/eickegao/clashdoz main/ai.lua 的转向逻辑）
-- Computer opponents. They play by the same rules as a human: every decision is issued as a sim command for their own team.
-- 2026-10-27 八技能改版：技能冷却到了就按 eager 概率放；火焰打敌格最密处，传送跳到离自己球最远的敌格密集处。

local config = require("games.clashdoz.cd_config")
local rng = require("games.clashdoz.cd_rng")
local sim = require("games.clashdoz.cd_sim")

local M = {}

local GRID = config.GRID

--- policy.eager = 每次思考时冷却好的技能放出去的概率（默认 0.6；关卡越高可以越高）
function M.new(team_id, seed, policy)
	return { team = team_id, rng = rng.new(seed), think = 0.5, eager = (policy and policy.eager) or 0.6 }
end

--- 目标意识（用户 2026-11-02：电脑得知道这关要干什么）：格 (i, j) 对本关目标值多少分——染区关目标区里的格 +6（火焰/传送/转向都优先往那儿），
--- 占地关没有特定区域（全盘都是目标）→ 0
function M.goal_bonus(s, i, j)
	local g = s.goal
	if g and g.kind == "zone" and g.rect then
		if i >= g.rect[1] and j >= g.rect[2] and i <= g.rect[3] and j <= g.rect[4] then return 6 end
	end
	return 0
end

-- Random enemy cell, preferring cells that border our own territory. Returns cell-centre coordinates or nil.
local function pick_target(ai, s, prefer_team)
	local best, best_score
	local W, H = s.W or GRID, s.H or GRID
	for _ = 1, 40 do
		local i = rng.range(ai.rng, 1, W)
		local j = rng.range(ai.rng, 1, H)
		local owner = s.grid[i][j]
		if owner ~= ai.team and owner ~= false then   -- false = 关卡棋盘外的空洞，不是目标
			local score = rng.next(ai.rng) + M.goal_bonus(s, i, j)
			if owner == prefer_team then score = score + 1 end
			for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
				local ni, nj = i + d[1], j + d[2]
				if ni >= 1 and ni <= W and nj >= 1 and nj <= H and s.grid[ni][nj] == ai.team then score = score + 2; break end
			end
			if not best_score or score > best_score then best, best_score = { i - 0.5, j - 0.5 }, score end
		end
	end
	return best
end

-- 敌格密度：(i, j) 周围 5×5 里不是自己的、不是空洞的格数
local function enemy_density(s, team, i, j)
	local n = 0
	local W, H = s.W or GRID, s.H or GRID
	for a = i - 2, i + 2 do
		for b = j - 2, j + 2 do
			if a >= 1 and a <= W and b >= 1 and b <= H then
				local o = s.grid[a][b]
				if o ~= false and o ~= team then n = n + 1 end
			end
		end
	end
	return n
end

-- 火焰 / 传送的落点：采样敌格，火焰挑最密的，传送挑"密 + 离自己主球远"的（max_range 以内）
local function pick_area(ai, s, far_from, max_range)
	local best, best_score
	local W, H = s.W or GRID, s.H or GRID
	for _ = 1, 24 do
		local i = rng.range(ai.rng, 1, W)
		local j = rng.range(ai.rng, 1, H)
		local owner = s.grid[i][j]
		local in_range = true
		if far_from and max_range then local dx, dy = (i - 0.5) - far_from.x, (j - 0.5) - far_from.y; in_range = dx * dx + dy * dy <= max_range * max_range end
		if owner ~= ai.team and owner ~= false and in_range then
			local score = enemy_density(s, ai.team, i, j) + rng.next(ai.rng) + M.goal_bonus(s, i, j)
			if far_from then
				local dx, dy = (i - 0.5) - far_from.x, (j - 0.5) - far_from.y
				score = score + math.sqrt(dx * dx + dy * dy) * 0.5
			end
			if not best_score or score > best_score then best, best_score = { i - 0.5, j - 0.5 }, score end
		end
	end
	return best
end

local function leader(s)
	return sim.ranking(s)[1]
end

local LOOKAHEAD = 14
local DIRS4 = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
-- 从 (x0, y0) 到 (x1, y1) 的直线（连同球半径 r 的两侧）不穿墙 / 不出棋盘
local function clear_line(grid, x0, y0, x1, y1, r)
	local dx, dy = x1 - x0, y1 - y0
	local len = math.sqrt(dx * dx + dy * dy)
	if len < 1e-6 then return true end
	local nx, ny = -dy / len * r, dx / len * r
	local steps = math.ceil(len / 0.25)
	for k = 0, steps do
		local t = k / steps
		local px, py = x0 + dx * t, y0 + dy * t
		for _, off in ipairs({ 0, 1, -1 }) do
			local ci, cj = math.floor(px + nx * off) + 1, math.floor(py + ny * off) + 1
			if ci < 1 or ci > GRID or cj < 1 or cj > GRID or grid[ci][cj] == false then return false end
		end
	end
	return true
end
--- 竞速路点：主球所在格起沿距离场下坡走出一条路（最多 LOOKAHEAD 格），取其中离球最远、从球的位置直线看得见（线段连同球半径不穿墙）的那格——
--- 宽道里斜着抄近路、迷宫里走到拐角；返回格中心坐标（球不在路网上 / 没路 → nil）
--- （2026-11-02 改：原来"方向一变就停"在宽道里路点只有一格远，球飞过头后乱弹，第 4 关两条 15 格宽的道电脑 90 s 跑不完）
function M.race_waypoint(s, team)
	local dist = sim.race_dist(s, team.stage or 1)
	if not dist then return nil end
	local grid = sim.team_grid(s, team)
	local b = team.balls[1]
	local i, j = math.floor(b.x) + 1, math.floor(b.y) + 1
	local here = dist[sim.cell_index(i, j)]
	if here == nil then   -- 球压在墙边格上：找四邻里有路的
		for _, d in ipairs(DIRS4) do local ni, nj = i + d[1], j + d[2]; if ni >= 1 and ni <= GRID and nj >= 1 and nj <= GRID and dist[sim.cell_index(ni, nj)] then i, j, here = ni, nj, dist[sim.cell_index(ni, nj)]; break end end
		if here == nil then return nil end
	end
	if here == 0 then return { i - 0.5, j - 0.5 } end
	local path = {}
	for _ = 1, LOOKAHEAD do
		local best, bd
		for _, d in ipairs(DIRS4) do
			local ni, nj = i + d[1], j + d[2]
			if ni >= 1 and ni <= GRID and nj >= 1 and nj <= GRID then
				local v = dist[sim.cell_index(ni, nj)]
				if v and v < here and (not bd or v < bd) then best, bd = d, v end
			end
		end
		if not best then break end
		i, j, here = i + best[1], j + best[2], bd
		path[#path + 1] = { i, j }
		if here == 0 then break end
	end
	if #path == 0 then return nil end
	local r = sim.ball_radius(team, b)
	for k = #path, 2, -1 do
		local tx, ty = path[k][1] - 0.5, path[k][2] - 0.5
		if clear_line(grid, b.x, b.y, tx, ty, r) then return { tx, ty } end
	end
	return { path[1][1] - 0.5, path[1][2] - 0.5 }
end

-- ---------------------------------------------------------------- 道具关（build 模式，2026-11-03）：没有球，只放东西
-- 大炮放"周围敌格最多"的己方格（前线）；放大器放离自己某门炮 1～3 格的己方格；士兵打离自己大炮最近的敌方大炮
local function own_cell_sample(ai, s, kind, pred)
	local best, best_score
	local W, H = s.W or GRID, s.H or GRID
	for _ = 1, 40 do
		local i, j = rng.range(ai.rng, 1, W), rng.range(ai.rng, 1, H)
		if sim.can_place(s, ai.team, kind, i, j) then
			local score = pred(i, j)
			if score and (not best_score or score > best_score) then best, best_score = { i - 0.5, j - 0.5 }, score end
		end
	end
	return best
end
local function build_update(ai, s, team)
	local b = s.build
	-- 出手节奏照原版 BotAiSettings：开局 AI_FIRST 秒后第一件，之后每 AI_EVERY 秒一件（再乘 eager 概率）
	local now = s.elapsed or 0
	if now < (config.BUILD.AI_FIRST or 0) then return end
	if ai.last_play and now - ai.last_play < (config.BUILD.AI_EVERY or 0) then return end
	for slot, sk in ipairs(team.skills) do
		if sim.can_cast(s, team, slot) and rng.next(ai.rng) < ai.eager then
			local at
			if sk.id == "cannon" then
				at = own_cell_sample(ai, s, "cannon", function(i, j) return enemy_density(s, ai.team, i, j) + rng.next(ai.rng) end)
			elseif sk.id == "amp" then
				local mine = {}
				for _, st in ipairs(b.structs) do if st.team == ai.team and st.kind == "cannon" then mine[#mine + 1] = st end end
				if #mine > 0 then
					local c = mine[rng.range(ai.rng, 1, #mine)]
					at = own_cell_sample(ai, s, "amp", function(i, j)
						local d = math.sqrt((i - c.i) ^ 2 + (j - c.j) ^ 2)
						if d < 1 or d > 3 then return nil end
						return 3 - d + rng.next(ai.rng)
					end)
				end
			elseif sk.id == "soldier" then
				local best, bd
				for _, st in ipairs(b.structs) do
					if st.kind == "cannon" and st.team ~= ai.team then
						local d = math.huge
						for _, mine in ipairs(b.structs) do if mine.team == ai.team then d = math.min(d, (st.i - mine.i) ^ 2 + (st.j - mine.j) ^ 2) end end
						if d == math.huge then d = 0 end
						d = d + rng.next(ai.rng) * 4
						if not bd or d < bd then best, bd = st, d end
					end
				end
				if best then at = { best.x, best.y } end
			end
			if at and sim.command(s, ai.team, { type = "cast", slot = slot, x = at[1], y = at[2] }) then ai.last_play = now; return end
		end
	end
end

function M.update(ai, s, dt)
	ai.think = ai.think - dt
	if ai.think > 0 then return end
	-- 竞速关反应快慢按 eager（关卡越高越快）：eager 0.6 → 0.39 s 左右；电脑路点是完美路线，不加反应延迟和瞄偏会 2 s 跑完一盘，人追不上
	local slack = 1 - ai.eager
	ai.think = (s.goal and s.goal.kind == "race") and (0.2 + slack * 1.2 + rng.next(ai.rng) * 0.15) or (0.4 + rng.next(ai.rng) * 0.6)

	local team = s.teams[ai.team]
	if s.over or sim.is_frozen(s, team) then return end
	if s.mode == "build" then return build_update(ai, s, team) end   -- 道具关：只放东西，没有球可转

	local top = leader(s)
	local prefer = top ~= ai.team and top or nil

	-- skills: anything off cooldown goes with probability eager; targeted ones pick a spot first
	for slot, sk in ipairs(team.skills) do
		local hold = sk.id == "freeze" and (s.elapsed or 0) < (config.FREEZE_AI_DELAY or 0)   -- 电脑的冰冻开局先憋着（2026-11-03）
		if not hold and sim.can_cast(s, team, slot) and rng.next(ai.rng) < ai.eager then
			local cmd = { type = "cast", slot = slot }
			if sk.id == "fire" then
				local a = pick_area(ai, s, nil); if a then cmd.x, cmd.y = a[1], a[2] end
			elseif sk.id == "teleport" then
				local a = pick_area(ai, s, team.balls[1], config.SKILLS.teleport.range[sk.level]); if a then cmd.x, cmd.y = a[1], a[2] end
			elseif sk.id == "turret" then   -- 炮台放在自己地盘里"周围敌格最多"的格（前线）
				local a = own_cell_sample(ai, s, "turret", function(i, j) return enemy_density(s, ai.team, i, j) + rng.next(ai.rng) end); if a then cmd.x, cmd.y = a[1], a[2] end
			elseif sk.id == "shock" then   -- 冲击波：前方 10 格里至少 4 格不是自己的才打（别对着自家地盘放）
				local b, n = team.balls[1], 0
				local W, H = s.W or GRID, s.H or GRID
				for d = 1, 10 do
					local i, j = math.floor(b.x + b.dx * d) + 1, math.floor(b.y + b.dy * d) + 1
					if i >= 1 and i <= W and j >= 1 and j <= H and s.grid[i][j] ~= false and s.grid[i][j] ~= ai.team then n = n + 1 end
				end
				if n < 4 then cmd = nil end
			elseif sk.id == "shatter" or sk.id == "snowball" then   -- 分裂球 / 滚雪球：主球在前线或敌区里（5×5 里 ≥ 8 格非己方）才放，撞得到才长得起来
				local b = team.balls[1]
				if enemy_density(s, ai.team, math.floor(b.x) + 1, math.floor(b.y) + 1) < 8 then cmd = nil end
			end   -- 链电：范围内没敌球 command 自己会拒绝
			if cmd and (not config.SKILLS[sk.id].target or cmd.x) then
				if sim.command(s, ai.team, cmd) then return end
			end
		end
	end

	local g = s.goal
	-- 竞速关（2026-11-01 用户：电脑要努力抢）：沿 sim.race_dist 的距离场走——从自己所在格顺着步数递减走 LOOKAHEAD 格（拐弯处停），朝那格转向；冷却一到就转
	if g and g.kind == "race" and g.at and team.turn_cd <= 0 then
		local wp = M.race_waypoint(s, team)
		if wp then   -- 瞄偏：朝路点的方向随机偏 ±(1 - eager) × 40°（低关电脑手抖、高关准）
			local b = team.balls[1]
			local ang = math.atan2(wp[2] - b.y, wp[1] - b.x) + (rng.next(ai.rng) * 2 - 1) * (1 - ai.eager) * 60 * math.pi / 180
			local d = math.max(1, math.sqrt((wp[1] - b.x) ^ 2 + (wp[2] - b.y) ^ 2))
			if sim.command(s, ai.team, { type = "turn", x = b.x + math.cos(ang) * d, y = b.y + math.sin(ang) * d }) then return end
		end
	end
	-- steer toward enemy ground every now and then；染区关大多数时候朝目标区里还不是自己的格去
	if team.turn_cd <= 0 and rng.next(ai.rng) < 0.5 then
		local target
		if g and g.kind == "zone" and #g.cells > 0 and rng.next(ai.rng) < 0.7 then
			for _ = 1, 12 do
				local idx = g.cells[rng.range(ai.rng, 1, #g.cells)]
				local i, j = (idx - 1) % GRID + 1, math.floor((idx - 1) / GRID) + 1
				if s.grid[i][j] ~= ai.team then target = { i - 0.5, j - 0.5 }; break end
			end
		end
		target = target or pick_target(ai, s, prefer)
		if target then sim.command(s, ai.team, { type = "turn", x = target[1], y = target[2] }) end
	end
end

return M
