-- games/clashdoz/cd_profile.lua — CLASHDOZ 局外档案 v2（2026-10-27 八技能改版，设计稿 §4）：
--   每种技能一张卡，技能点不能撤：累计 1 点一级、3 点二级、7 点三级满（C.SKILL_POINTS_LEVEL；收藏页 upgrade 一次扣 1 / 2 / 4，add_point 逐点加仍可用）。
--   技能点来源（2026-11-05 夜用户定案）：每关首胜 +WIN_LEVEL（1），Boss 关（每组第 10 关，cd_levels.is_boss）首胜 +WIN_BOSS（2）；重打 0、不按名次；100 金币买一点（无上限）。
--   带进场 ≤ slots 种（默认 2，第 3 位 500 金币开）；0 点技能不能带。
--   v3（2026-10-28）：旧档一律作废从头来（关卡进度也回 1）；2026-11-02 起新档不送技能、给 2 点自己挑。
-- 存档 clashdoz/profile（sys.save，进 shared/cloud_save FILES）。
local C = require("games.clashdoz.cd_config")
local rng = require("games.clashdoz.cd_rng")
local coin = require("shared.coin")

local M = {}
M.VERSION = 5                -- v5（2026-11-04 晚用户：全部恢复到第 1 关、卡全部回锁、第一次进来送 2 点自己解锁两张；v4 2026-11-02 自己挑两种；v3 2026-10-28 从头开始）：低于此版本的档一律清掉重来，关卡进度也回第 1 关
M.PRICES = { point = 100, slot = 500 }   -- 2026-11-04 收藏页：100 金币 1 技能点（原 150）
M.WIN_LEVEL, M.WIN_BOSS = 1, 2   -- 每关首胜 1 点、Boss 关首胜 2 点（用户 2026-11-05 夜；此前只有对决关给 3 点，而 11-03 重定的 100 关里没有对决关 → 玩家拿不到点）
M.STARTER_COUNT = 2          -- 新档送 2 个技能点、不点亮任何技能：第 1 关先到准备页自己挑 2 种（用户 2026-11-02）

local MAX_POINTS = C.SKILL_POINTS_LEVEL[#C.SKILL_POINTS_LEVEL]   -- 16

local pf = nil
local function path() return sys.get_save_file("clashdoz", "profile") end
local function mark_dirty() pcall(function() require("shared.cloud_save").mark_dirty() end) end
local function num(v, lo, hi, d) v = tonumber(v); if not v then return d end; return math.max(lo, math.min(hi, math.floor(v))) end

local function spent_of(p) local n = 0; for _, id in ipairs(C.SKILL_IDS) do n = n + (p.skills[id] or 0) end return n end

local function merge_defaults(d)
	if type(d) ~= "table" then d = {} end
	local out = { v = M.VERSION, skills = {}, drops = {}, loadout = {} }
	local sk = type(d.skills) == "table" and d.skills or {}
	for _, id in ipairs(C.SKILL_IDS) do out.skills[id] = num(sk[id], 0, MAX_POINTS, 0) end
	if sk.shield then out.skills.bomb = math.max(out.skills.bomb, num(sk.shield, 0, MAX_POINTS, 0)) end   -- 2026-10-31 护盾删了：旧档盾上的点转给炸弹
	out.points_free = num(d.points_free, 0, 1e9, 0)
	out.points_bought = num(d.points_bought, 0, 1e9, 0)
	local sl = tonumber(d.slots)
	out.slots = (sl and sl >= C.SLOTS_DEFAULT and sl <= C.SLOTS_MAX) and math.floor(sl) or C.SLOTS_DEFAULT   -- 超范围按默认，不白送位
	if type(d.loadout) == "table" then
		local seen = {}
		for _, id in ipairs(d.loadout) do
			if id == "shield" then id = "bomb" end
			if C.SKILLS[id] and not seen[id] then seen[id] = true; out.loadout[#out.loadout + 1] = id end
		end
	end
	if type(d.drops) == "table" then for k, v in pairs(d.drops) do if tonumber(k) and v then out.drops[tonumber(k)] = true end end end
	out.seen_prep = d.seen_prep == true
	return out
end

--- 新档：不送技能，给 STARTER_COUNT 个可用点让玩家在准备页自己挑（用户 2026-11-02：一开始让他自己选择、告诉他可以选两种）；关卡进度回第 1 关（v3 从头来）
local function fresh_start(p)
	p.loadout = {}
	for _, id in ipairs(C.SKILL_IDS) do p.skills[id] = 0 end
	p.points_free = M.STARTER_COUNT
	pcall(function() require("shared.game_progress").reset("clashdoz") end)
end

function M.save()
	if not pf then return end
	sys.save(path(), pf)
	mark_dirty()
end

function M.load()
	if pf then return pf end
	local okl, raw = pcall(sys.load, path())   -- 文件损坏到 sys.load 直接抛错也不炸准备页
	if not okl then raw = nil end
	local empty = type(raw) ~= "table" or next(raw) == nil
	local old = not empty and (tonumber(raw.v) or 1) < M.VERSION
	if old then raw = nil end   -- v3：旧档（天赋卡 / v2 技能点）全部作废从头来（用户 2026-10-28）
	pf = merge_defaults(raw)
	if empty or old then fresh_start(pf) end
	-- 还没点过任何技能（新档 / 空坏档）：至少保证有 STARTER_COUNT 个点可花（不重置进度）
	if spent_of(pf) == 0 and pf.points_free + pf.points_bought < M.STARTER_COUNT then pf.points_free = M.STARTER_COUNT end
	-- 卡上的点是付过的：已花 > 总点（坏文件/手改）就把总点补齐，不清卡
	local spent, total = spent_of(pf), pf.points_free + pf.points_bought
	if spent > total then pf.points_free = pf.points_free + (spent - total) end
	M.save()
	return pf
end
function M.reset_cache() pf = nil end
--- 整个档案清零从头来（旗标文件 clashdoz/reset_profile 触发，controller 读；用户 2026-11-05 夜：不要有技能、过的关也清空）：卡全锁、送新档 2 点、关卡进度回第 1 关、首胜记录清空
function M.reset_all()
	pf = merge_defaults(nil)
	fresh_start(pf)
	M.save()
	return pf
end

-- ---------------------------------------------------------------- 技能点
function M.points_total() local p = M.load(); return p.points_free + p.points_bought end
function M.points_spent() return spent_of(M.load()) end
function M.points_available() return math.max(0, M.points_total() - M.points_spent()) end
function M.points(id) return M.load().skills[id] or 0 end
function M.level(id) return C.level_for_points(M.points(id)) end
--- 所有卡里最高等级（至少 1）：关卡生成器用它封顶敌人技能等级（2026-10-30）
function M.max_level()
	local best = 1
	for _, id in ipairs(C.SKILL_IDS) do best = math.max(best, M.level(id)) end
	return best
end
--- 到下一级的进度：返回 have, need（满级 have == need）
function M.progress(id)
	local pts = M.points(id)
	local lv = C.level_for_points(pts)
	if lv >= C.SKILL_MAX_LEVEL then local last = C.SKILL_POINTS_LEVEL[lv] - C.SKILL_POINTS_LEVEL[lv - 1]; return last, last end
	local base = lv > 0 and C.SKILL_POINTS_LEVEL[lv] or 0
	return pts - base, C.SKILL_POINTS_LEVEL[lv + 1] - base
end
function M.can_add(id)
	return C.SKILLS[id] ~= nil and M.points(id) < MAX_POINTS and M.points_available() >= 1
end
--- 加 1 点到技能 id（不能撤）。2026-11-04 收藏页：刚点亮（0 → 1 点）且带队还有空位就自动带上，新玩家解锁两张直接能开打
function M.add_point(id)
	if not M.can_add(id) then return false end
	local p = M.load()
	local was = p.skills[id]
	p.skills[id] = was + 1
	if was == 0 and #M.loadout_raw() < p.slots and not M.equipped(id) then p.loadout[#p.loadout + 1] = id end
	M.save(); return true
end
--- 升到下一级还要几点（满级 0）：解锁 1、一升二 2、二升三 4（C.SKILL_POINTS_LEVEL 累计 1/3/7）
function M.cost(id)
	if not C.SKILLS[id] then return 0 end
	local lv = M.level(id)
	if lv >= C.SKILL_MAX_LEVEL then return 0 end
	return C.SKILL_POINTS_LEVEL[lv + 1] - M.points(id)
end
--- 收藏页 Unlock / Upgrade 钮：一次扣够 cost 点升一级。返回 true | "max" | "no_points" | false（未知技能）
function M.upgrade(id)
	if not C.SKILLS[id] then return false end
	local need = M.cost(id)
	if need <= 0 then return "max" end
	if M.points_available() < need then return "no_points" end
	local p = M.load()
	local was = p.skills[id]
	p.skills[id] = was + need
	if was == 0 and #M.loadout_raw() < p.slots and not M.equipped(id) then p.loadout[#p.loadout + 1] = id end   -- 刚点亮、位有空就带上
	M.save(); return true
end
--- 点亮了几张卡（等级 ≥ 1）——收藏页 "Collection n / N"
function M.unlocked_count()
	local n = 0
	for _, id in ipairs(C.SKILL_IDS) do if M.level(id) > 0 then n = n + 1 end end
	return n
end
--- 这张卡带没带进场
function M.equipped(id)
	for _, c in ipairs(M.loadout_raw()) do if c.id == id then return true end end
	return false
end
--- 收藏页点卡：带 ↔ 不带。返回 "on" | "off" | "full"（位满，先取下一张）| false（没点亮）
function M.toggle(id)
	if M.level(id) <= 0 then return false end
	local p = M.load()
	local cur = M.loadout_raw()
	local ids = {}
	for _, c in ipairs(cur) do if c.id ~= id then ids[#ids + 1] = c.id end end
	if #ids < #cur then p.loadout = ids; M.save(); return "off" end
	if #cur >= p.slots then return "full" end
	ids[#ids + 1] = id; p.loadout = ids; M.save(); return "on"
end
--- 买 1 点：true | "no_coins"
function M.buy_point()
	local p = M.load()
	if not coin.deduct(M.PRICES.point, "clashdoz_point") then return "no_coins" end
	p.points_bought = p.points_bought + 1; M.save(); return true
end

--- 调试：八种技能全点满 + 第 3 位开（只给 debug 引擎的直达 level=83 用，controller 判 is_debug；2026-10-31 用户装机测所有特殊球）
function M.debug_unlock_all()
	local p = M.load()
	for _, id in ipairs(C.SKILL_IDS) do p.skills[id] = MAX_POINTS end
	p.slots = C.SLOTS_MAX
	local spent, total = spent_of(p), p.points_free + p.points_bought
	if spent > total then p.points_free = p.points_free + (spent - total) end   -- 补齐总点，不欠账也不多送
	M.save()
	return true
end

--- 调试：存档目录里有旗标文件 clashdoz/unlock_all 就全点满并删掉旗标（真机 devicectl 放文件触发；iOS 26 上 devicectl --payload-url 不触发 iac，深链 83 只网页能用）。返回是否触发
function M.debug_unlock_if_flagged(flag_path)
	flag_path = flag_path or sys.get_save_file("clashdoz", "unlock_all")
	local f = io.open(flag_path, "r")
	if not f then return false end
	f:close()
	M.debug_unlock_all()
	os.remove(flag_path)
	return true
end

-- ---------------------------------------------------------------- 带进场
function M.slots() return M.load().slots end
--- 开第 3 位：true | "no_coins" | "max"
function M.unlock_slot()
	local p = M.load()
	if p.slots >= C.SLOTS_MAX then return "max" end
	if not coin.deduct(M.PRICES.slot, "clashdoz_slot") then return "no_coins" end
	p.slots = p.slots + 1; M.save(); return true
end
--- 玩家自己选的（不自动补）：准备页显示用——全部取下就显示空位，不会一松手又自动塞回两种（用户 2026-10-28）
function M.loadout_raw()
	local p, out, seen = M.load(), {}, {}
	for _, id in ipairs(p.loadout) do
		local lv = M.level(id)
		if lv > 0 and not seen[id] and #out < p.slots then seen[id] = true; out[#out + 1] = { id = id, level = lv } end
	end
	return out
end
--- 带进场的技能：{ {id, level}, … }，过滤 0 点、去重、≤ 位数；一个都没选到时按等级高的自动补满（开局用）
function M.loadout()
	local p = M.load()
	local out = M.loadout_raw()
	if #out == 0 then
		local owned = {}
		for k, id in ipairs(C.SKILL_IDS) do local lv = M.level(id); if lv > 0 then owned[#owned + 1] = { id = id, level = lv, k = k } end end
		table.sort(owned, function(a, b) if a.level ~= b.level then return a.level > b.level end return a.k < b.k end)
		for k = 1, math.min(p.slots, #owned) do out[k] = { id = owned[k].id, level = owned[k].level } end
	end
	return out
end
function M.set_loadout(ids)
	local p, out, seen = M.load(), {}, {}
	for _, id in ipairs(ids or {}) do if C.SKILLS[id] and M.level(id) > 0 and not seen[id] and #out < p.slots then seen[id] = true; out[#out + 1] = id end end   -- 0 点的带不了
	p.loadout = out; M.save()
end

-- ---------------------------------------------------------------- 过关
--- 赢了一关：首胜 +WIN_LEVEL，Boss 关首胜 +WIN_BOSS，重打 0。返回 { points = n, first = bool }
function M.on_win(level_num)
	local p = M.load()
	local first = not p.drops[level_num]
	p.drops[level_num] = true
	local boss = require("games.clashdoz.cd_levels").is_boss(level_num)
	local n = first and (boss and M.WIN_BOSS or M.WIN_LEVEL) or 0
	p.points_free = p.points_free + n
	M.save()
	return { points = n, first = first }
end
function M.on_trial_win() end   -- 1 VS 1 / 1 VS 8：不给点

return M
