-- games/clashdoz/cd_mini.lua — CLASHDOZ 小棋盘渲染器（2026-10-28）：用真 sim 在任意 GUI 里跑一局并画出来。
-- 准备页技能演示（选中技能循环放一遍）和封面中间的红蓝对战动画共用。
-- 节点在 new() 时建好常驻（1024 格 + 格线 + 球池 + 几个特效节点），之后只改颜色/位置；同帧删旧建新会撞 max_nodes，所以不重建。
-- 用法：
--   local mini = require("games.clashdoz.cd_mini")
--   local m = mini.new(parent_node, cx, cy, cell_px)           -- 棋盘中心 (cx, cy)（parent 坐标）、每格像素
--   m:start(seed, sim_opts, { bots = { 2 }, eager = 0.7 })     -- 开一局：sim_opts 原样给 cd_sim.new；bots = 哪些队交给 AI
--   m:cast(team, slot, x, y)                                   -- 手动放技能（演示用）
--   m:update(dt)  → true 表示这局打完                            -- 每帧推进 + 画
--   m:set_enabled(on)
local C = require("games.clashdoz.cd_config")
local sim = require("games.clashdoz.cd_sim")
local ai = require("games.clashdoz.cd_ai")

local GRID = C.GRID
local TEAMS = C.TEAMS
local WHITE = vmath.vector4(1, 1, 1, 1)
local NEUTRAL = vmath.vector4(0.93, 0.93, 0.96, 1)
local FROZEN = vmath.vector4(0.55, 0.6, 0.7, 1)
local SLOWED = vmath.vector4(0.55, 0.75, 1, 1)
local LINE_COLOR = vmath.vector4(0.04, 0.04, 0.1, 1)
local TINT = {
	freeze = vmath.vector4(0.6, 0.9, 1, 1), split = vmath.vector4(0.5, 0.95, 0.55, 1), accel = vmath.vector4(0.3, 0.9, 1, 1), bomb = vmath.vector4(1, 0.5, 0.25, 1),
	giant = vmath.vector4(1, 0.75, 0.4, 1), fire = vmath.vector4(1, 0.55, 0.2, 1), lightning = vmath.vector4(1, 0.95, 0.6, 1), teleport = vmath.vector4(0.85, 0.6, 1, 1),
}
local function v3(x, y) return vmath.vector3(x, y, 0) end

local M = {}
M.__index = M

local ATLAS = "clashdoz"
local function mk_box(parent, x, y, w, h, color, anim)
	local n = gui.new_box_node(v3(x, y), v3(w, h))
	gui.set_parent(n, parent, false)
	if anim then gui.set_texture(n, ATLAS); gui.play_flipbook(n, anim) end
	if color then gui.set_color(n, color) end
	return n
end

--- 建常驻节点。opts.line_w 格线宽（默认 cell/5，至少 2）；opts.frame_color 棋盘底色；opts.atlas 该 gui 里 clashdoz 图集的名字（默认 "clashdoz"）；
--- opts.ball_mult 球放大倍数（封面演示用大一点）
function M.new(parent, cx, cy, cell, opts)
	opts = opts or {}
	ATLAS = opts.atlas or "clashdoz"
	local self = setmetatable({ cell = cell, cx = cx, cy = cy, on = false }, M)
	local W = GRID * cell
	local line_w = opts.line_w or math.max(2, cell / 5)
	self.frame = mk_box(parent, cx, cy, W + cell, W + cell, opts.frame_color or vmath.vector4(0.04, 0.04, 0.1, 1))
	gui.set_clipping_mode(self.frame, gui.CLIPPING_MODE_STENCIL)   -- 冰冻波环 / 闪电光柱不许画到棋盘框外（封面上会飘到标题区）
	self.cells = {}
	for j = 1, GRID do for i = 1, GRID do
		local x, y = self:cell_pos(i, j)
		self.cells[sim.cell_index(i, j)] = mk_box(self.frame, x, y, cell, cell, NEUTRAL)   -- 贴齐无缝
	end end
	-- 格线：独立软边线盖在格子上（主棋盘同款，粗细均匀）
	local span, half = W + line_w, W / 2
	for n = 0, GRID do
		local at = n * cell - half
		mk_box(self.frame, at, 0, line_w, span, LINE_COLOR, "gridline_v")
		mk_box(self.frame, 0, at, span, line_w, LINE_COLOR, "gridline_h")
	end
	-- 球池：每队 MAX_BALLS_PER_TEAM（球 + 内光 + 底影）
	self.balls = {}
	local d = cell * 2.8 * (opts.ball_mult or 1)
	for t = 1, #TEAMS do
		self.balls[t] = {}
		for k = 1, C.MAX_BALLS_PER_TEAM do
			local sh = mk_box(self.frame, 0, 0, d * 1.3, d * 1.3, vmath.vector4(0.05, 0.05, 0.12, 0.55), "skill_btn"); gui.set_enabled(sh, false)
			local b = mk_box(self.frame, 0, 0, d, d, TEAMS[t].color, "ball"); gui.set_enabled(b, false)
			local l = mk_box(b, 0, 0, d, d, WHITE, "ball_light"); gui.set_blend_mode(l, gui.BLEND_ADD)
			self.balls[t][k] = { node = b, light = l, shadow = sh }
		end
	end
	-- 特效池：环 ×4、光柱 ×4、闪光、整盘罩
	self.rings, self.beams = {}, {}
	for k = 1, 4 do local r = mk_box(self.frame, 0, 0, d, d, WHITE, "ring"); gui.set_enabled(r, false); self.rings[k] = r end
	for k = 1, 4 do local b = mk_box(self.frame, 0, 0, 1, 1, WHITE, "beam"); gui.set_blend_mode(b, gui.BLEND_ADD); gui.set_pivot(b, gui.PIVOT_W); gui.set_enabled(b, false); self.beams[k] = b end
	self.flare = mk_box(self.frame, 0, 0, cell * 4, cell * 4, WHITE, "flare"); gui.set_blend_mode(self.flare, gui.BLEND_ADD); gui.set_enabled(self.flare, false)
	self.glow = mk_box(self.frame, 0, 0, cell * 4, cell * 4, WHITE, "halo"); gui.set_enabled(self.glow, false)
	self.overlay = mk_box(self.frame, 0, 0, W, W, vmath.vector4(0.6, 0.85, 1, 0)); gui.set_enabled(self.overlay, false)
	self.ring_i = 0
	gui.set_enabled(self.frame, false)
	return self
end

--- 格 (i, j) 中心 → frame 局部坐标
function M:cell_pos(i, j) return (i - 0.5) * self.cell - GRID * self.cell / 2, (j - 0.5) * self.cell - GRID * self.cell / 2 end
function M:pt(x, y) return x * self.cell - GRID * self.cell / 2, y * self.cell - GRID * self.cell / 2 end   -- 球坐标（格单位）→ 局部

function M:set_enabled(on) gui.set_enabled(self.frame, on) end

local function cell_color(s, i, j, idx)
	local v = s.grid[i][j]
	return (v == 0) and NEUTRAL or TEAMS[v].color
end

function M:fx_hide()
	for _, n in ipairs(self.rings) do gui.cancel_animations(n, gui.PROP_SCALE); gui.cancel_animations(n, "color.w"); gui.set_enabled(n, false) end
	for _, n in ipairs(self.beams) do gui.cancel_animations(n, "color.w"); gui.set_enabled(n, false) end
	for _, n in ipairs({ self.flare, self.glow, self.overlay }) do gui.cancel_animations(n, gui.PROP_SCALE); gui.cancel_animations(n, "color.w"); gui.set_enabled(n, false) end
end

--- 开一局：sim_opts 原样给 cd_sim.new；ctl.bots = 交给 AI 的队号列表，ctl.eager = AI 放技能积极度
function M:start(seed, sim_opts, ctl)
	ctl = ctl or {}
	self:fx_hide()
	self.sim = sim.new(seed, sim_opts)
	self.bots = {}
	for _, t in ipairs(ctl.bots or {}) do self.bots[#self.bots + 1] = ai.new(t, seed + t * 7919, { eager = ctl.eager or 0.6 }) end
	self.acc, self.t, self.on = 0, 0, true
	local s = self.sim
	local bc = s.level and s.level.board
	if bc then gui.set_color(self.frame, vmath.vector4(bc[1], bc[2], bc[3], 1)) end
	for j = 1, GRID do for i = 1, GRID do
		local idx = sim.cell_index(i, j); local cell = self.cells[idx]
		gui.cancel_animations(cell, gui.PROP_COLOR); gui.set_enabled(cell, s.grid[i][j] ~= false)
		if s.grid[i][j] ~= false then gui.set_color(cell, cell_color(s, i, j, idx)) end
	end end
	s.changed = {}; s.flips = {}; s.events = {}
	for t = 1, #TEAMS do for _, p in ipairs(self.balls[t]) do gui.set_enabled(p.node, false); gui.set_enabled(p.shadow, false) end end
	gui.set_enabled(self.frame, true)
	return s
end

function M:cast(team, slot, x, y) if self.sim then return sim.command(self.sim, team, { type = "cast", slot = slot, x = x, y = y }) end end

function M:ring(x, y, color, to_scale, dur)
	self.ring_i = self.ring_i % #self.rings + 1
	local n = self.rings[self.ring_i]
	gui.set_enabled(n, true); gui.set_position(n, v3(x, y)); gui.set_color(n, color)
	gui.cancel_animations(n, gui.PROP_SCALE); gui.cancel_animations(n, "color.w")
	gui.set_scale(n, vmath.vector3(1, 1, 1)); gui.animate(n, gui.PROP_SCALE, vmath.vector3(to_scale, to_scale, 1), gui.EASING_OUTQUAD, dur)
	gui.animate(n, "color.w", 0.05, gui.EASING_OUTQUAD, dur, 0, function() gui.set_enabled(n, false) end)
end

function M:events()
	local s, cell = self.sim, self.cell
	for _, e in ipairs(s.events) do
		local ex, ey = self:pt(e.x, e.y)
		local c = TEAMS[e.team].color
		if e.skill == "freeze" then
			self:ring(ex, ey, vmath.lerp(0.5, c, SLOWED), (e.max_r or 40) * 2 * cell / (cell * 2.8), (e.max_r or 40) / C.WAVE_SPEED)
			if (e.level or 1) >= 3 then
				gui.set_enabled(self.overlay, true); gui.set_color(self.overlay, vmath.vector4(0.6, 0.85, 1, 0.3))
				gui.animate(self.overlay, "color.w", 0, gui.EASING_OUTQUAD, 1.5, 0, function() gui.set_enabled(self.overlay, false) end)
			end
		elseif e.skill == "fire" and e.phase == "aim" then self:ring(ex, ey, TINT.fire, (e.radius or 2) * 2 * cell / (cell * 2.8) * 1.2, C.FIRE_DELAY)
		elseif e.skill == "fire" then
			self:ring(ex, ey, WHITE, (e.radius or 2) * 2 * cell / (cell * 2.8) * 1.6, 0.45)
			gui.set_enabled(self.glow, true); gui.set_position(self.glow, v3(ex, ey)); gui.set_color(self.glow, vmath.vector4(1, 0.5, 0.15, 0.9))
			gui.set_scale(self.glow, vmath.vector3((e.radius or 2) * 1.2, (e.radius or 2) * 1.2, 1))
			gui.animate(self.glow, "color.w", 0, gui.EASING_OUTQUAD, 0.5, 0, function() gui.set_enabled(self.glow, false) end)
		elseif e.skill == "lightning" then
			local ox, oy = self:cell_pos(e.i, e.j)
			for k, d in ipairs(e.dirs or {}) do
				local b = self.beams[k]
				if b then
					local len = (e.lens and e.lens[k] or GRID) * cell
					local back = (k % 2 == 0) and cell or 0
					gui.set_enabled(b, true); gui.set_position(b, v3(ox + d[1] * back, oy + d[2] * back))
					gui.set_size(b, v3(len, (e.width or 1) * cell * 1.2)); gui.set_rotation(b, vmath.quat_rotation_z(math.atan2(d[2], d[1])))
					gui.set_color(b, vmath.lerp(0.3, c, TINT.lightning)); gui.animate(b, "color.w", 0, gui.EASING_INQUAD, 0.5, 0.05, function() gui.set_enabled(b, false) end)
				end
			end
		elseif e.skill == "teleport" then
			local fx, fy = self:pt(e.from_x, e.from_y)
			self:ring(fx, fy, TINT.teleport, 0.1, 0.3)
			gui.set_enabled(self.flare, true); gui.set_position(self.flare, v3(ex, ey)); gui.set_color(self.flare, WHITE); gui.set_scale(self.flare, vmath.vector3(1.5, 1.5, 1))
			gui.animate(self.flare, gui.PROP_SCALE, vmath.vector3(0.1, 0.1, 1), gui.EASING_INQUAD, 0.4, 0, function() gui.set_enabled(self.flare, false) end)
		elseif e.skill == "giant" then self:ring(ex, ey, c, 8, 0.6)
		elseif e.skill == "split" then self:ring(ex, ey, c, 3, 0.5)
		elseif e.skill == "accel" then self:ring(ex, ey, TINT.accel, 5, 0.5)
		elseif e.skill == "bomb" then if e.phase == "hit" then self:ring(ex, ey, TINT.bomb, 2.5, 0.3) else self:ring(ex, ey, TINT.bomb, 4, 0.6) end
		end
	end
	for _, idx in ipairs(s.changed) do
		local i = (idx - 1) % GRID + 1; local j = math.floor((idx - 1) / GRID) + 1
		gui.set_color(self.cells[idx], cell_color(s, i, j, idx))
	end
	s.changed = {}; s.flips = {}; s.events = {}
end

--- 每帧：推进（AI + 固定步长）+ 画；返回 sim.over
function M:update(dt)
	if not self.on or not self.sim then return false end
	local s = self.sim
	self.t = self.t + dt
	self.acc = self.acc + math.min(dt, 0.1)
	while self.acc >= C.FIXED_DT and not s.over do
		for _, b in ipairs(self.bots) do ai.update(b, s, C.FIXED_DT) end
		sim.step(s, C.FIXED_DT); self.acc = self.acc - C.FIXED_DT
	end
	self:events()
	for t, team in ipairs(s.teams) do
		local frozen, slowed = sim.is_frozen(s, team), (team.slow_left or 0) > 0
		local accel = (team.accel_left or 0) > 0
		for k, p in ipairs(self.balls[t] or {}) do
			local b = team.balls[k]
			if b then
				local x, y = self:pt(b.x, b.y)
				gui.set_enabled(p.node, true); gui.set_enabled(p.shadow, true)
				gui.set_position(p.node, v3(x, y)); gui.set_position(p.shadow, v3(x, y))
				local sc = sim.ball_radius(team, b) / C.BALL_RADIUS * (accel and 1.3 or 1)
				gui.set_scale(p.node, vmath.vector3(sc, sc, 1)); gui.set_scale(p.shadow, vmath.vector3(sc, sc, 1))
				local col = TEAMS[t].color
				gui.set_color(p.node, frozen and FROZEN or (slowed and vmath.lerp(0.5, col, SLOWED) or col))
				gui.set_color(p.light, frozen and vmath.vector4(0, 0, 0, 0) or vmath.vector4(col.x, col.y, col.z, 0.8))
			elseif gui.is_enabled(p.node) then gui.set_enabled(p.node, false); gui.set_enabled(p.shadow, false) end
		end
	end
	return s.over
end

return M
