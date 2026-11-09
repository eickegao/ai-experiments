-- games/clashdoz/cd_config.lua
-- CLASHDOZ（原 Colour Battle，github.com/eickegao/clashdoz）规则常量。
-- 2026-10-27 晚 八技能改版（设计稿 docs/superpowers/specs/2026-10-27-clashdoz-eight-skills-design.md）：
--   天赋树 / 卡库 / 三档能量条 / BOOST 全删；只剩 8 种技能 × 3 级，全部冷却制、按钮手动触发。
-- 几何：合集 1080×1920（原型 720×1280 × 1.5）。棋盘竖向位置由 clashdoz_game.gui_script 决定。
local M = {}

M.SCREEN_W = 1080
M.SCREEN_H = 1920

-- Board
M.GRID = 32                -- cells per side
M.CELL = 30                -- pixels per cell (原型 20 × 1.5)
M.BOARD_SIZE = M.GRID * M.CELL
M.BOARD_X = (M.SCREEN_W - M.BOARD_SIZE) / 2   -- left edge（屏幕坐标）

-- Round
M.ROUND_TIME = 60          -- seconds（原型 90；用户 2026-10-26：太紧，改 60）
M.FIXED_DT = 1 / 60        -- simulation step
M.FINAL_RUSH_TIME = 10     -- 最后 10 秒：倒计时变红 + 滴答

-- Balls
M.BALL_SPEED = 22          -- cells per second
M.BALL_RADIUS = 0.45       -- in cells
M.MAX_BALLS_PER_TEAM = 24   -- 主球 + 分身副球（SPLIT III 共 8 个）+ 分裂小球（SHATTER III 16 颗）；sim 真正限制，gui 球池同数（2026-11-05 夜 8 → 24）

-- Player controls
M.PLAYER_TEAM = 1
M.TURN_COOLDOWN = 1.0      -- seconds（点一下的急转冷却）
M.STEER_RATE = 8           -- 按住拖动持续转向：每秒最多转这么多弧度（用户 2026-11-03：按住不放球每帧朝手指修正方向，松手才自由跑）
M.HOLD_STEER_T = 0.15      -- 按下超过这么久算"按住"，开始持续转向（之前那一下仍是普通急转）
M.MIN_SLOPE = 0.25         -- 方向的横 / 纵分量最小值（防球贴线永不换格）
M.TRACK_MIN_SLOPE = 0.08   -- 跑道关玩家转向的下限：近乎直线（4.6°，4 格宽的道要跑 50 格才漂到对面），又不会正对着道壁永远上下弹（0 的话电脑跑不完绕场关）

-- ---------------------------------------------------------------- 八种技能（用户 2026-10-27 口述定案；冷却 2026-10-27 深夜二改：级数越高冷却越长，三级冰冻 30 s 一局只能放一次、三级巨球 24 s 最多两次）
-- 下标 = 等级 1/2/3。target = true 的要先点技能再点棋盘（火焰 / 传送），其余点一下立刻放。
-- 主球 = team.balls[1]：冰冻波 / 闪电 / 传送 / 炸弹只作用主球；加速 / 巨型对全部球；分身只复制主球。
M.SKILL_IDS = { "freeze", "split", "accel", "bomb", "giant", "fire", "lightning", "teleport", "shatter", "shock", "chain", "snowball" }   -- 2026-11-04 晚：炮台 turret 摘掉（定义 / sim / AI / level=84 留着）；加分裂球 / 冲击波 / 链式闪电 / 滚雪球（用户口述）
M.SKILLS = {
	-- 冰冻：以主球为中心放一道圆形波（WAVE_SPEED 格/秒扩到盖满棋盘），波碰到的敌队：一/二级减速 factor 持续 dur；三级整队冻住 dur 秒（= 时间停止，放不了技能）
	freeze    = { name = "FREEZE",    cd = { 12, 15, 20 }, factor = { 0.3, 0.2, 0 }, dur = { 6, 8, 6 }, freeze = { false, false, true } },   -- 2026-10-28 用户：冰冻最弱，一级减速再狠一点（原 0.5/0.4、3/4 s）
	-- 分身：立刻变成 count 个球（副球从主球散开），window 秒后副球消失、主球留下
	split     = { name = "SPLIT",     cd = { 12, 14, 20 }, count = { 3, 4, 5 }, window = { 3, 4, 4 } },   -- 2026-10-30 用户：球数改 3/4/5（含主球）；巨球一/二级作用全部球、三级全部变大只主球穿透（见 cd_sim is_giant / giant_pierces）   -- 平衡实验 2026-10-28：原 cd 10/12/16、窗口 4/5/6 太强（一级胜率 69%、二级 90%）；三级 18 s/5 s 胜率 57% → 用户定 20 s/8 球/4 s（24%）
	-- 加速：己方所有球 ×mult 持续 dur 秒
	accel     = { name = "ACCEL",     cd = { 10, 9, 8 }, mult = { 1.6, 1.8, 2.0 }, dur = { 4, 5, 6 } },
	-- 炸弹（2026-10-31 替代护盾，盾逻辑全删；用户口述）：dur 秒内主球每撞换色一个格，它十字四邻里非己方的格再换 extra 个（不够就有几个换几个）；
	-- 只主球（分身副球没有）；玩家专属（PLAYER_ONLY_SKILLS）。见 cd_sim.ball_hit
	bomb      = { name = "BOMB",      cd = { 12, 14, 16 }, dur = { 5, 6, 7 }, extra = { 1, 2, 3 } },
	-- 巨型：dur 秒内己方全部球（含分身副球，2026-10-30）半径 radius、速度 ×mult；一/二级只是大球（照常反弹，撞到的格更多）、二级外圈闪电能量环（演出）；三级 pierce 穿透只给主球：碾过即染、只在棋盘边反弹
	giant     = { name = "GIANT",     cd = { 14, 18, 24 }, dur = { 4, 5, 3 }, radius = { 0.7, 0.8, 0.8 }, mult = { 1.15, 1.2, 1.0 }, pierce = { false, false, true } },   -- 平衡实验：三级穿透太强（原 6 s / 0.9 / ×1.25 胜率 87%，5 s / 0.85 仍 90%）→ 3.5 s / 0.8 / ×1.2（65%）→ 用户 2026-10-28 定 3 s / ×1.0（57%，穿透期不提速碾的格就少）
	-- 火焰：点棋盘，FIRE_DELAY 后从天而降染 radius 格圆
	fire      = { name = "FIRE",      cd = { 12, 16, 20 }, target = true, radius = { 2, 2.5, 3 } },   -- 2026-11-01 用户：火焰缩小一点，半径 2/2.5/3（原 2.5/3/3.5），冷却不动
	-- 闪电：从主球所在格劈到棋盘边的十字四道，三档都 1 格宽，等级越高冷却越短
	lightning = { name = "LIGHTNING", cd = { 14, 12, 10 }, width = { 1, 1, 1 }, dirs = { 4, 4, 4 } },   -- 2026-11-01 用户：两根线太强（二级胜率 73%），三档全改 1 格宽单线十字，等级只差冷却；冷却 14/12/10 用户定（12/10/8 嫌太密）   -- 2026-10-28：一级也是十字（原只有上下）
	-- 传送：点棋盘，主球瞬移过去并染落点格（副球不动）；不限距（2026-10-30 起，range 99）；等级越高冷却越短
	teleport  = { name = "TELEPORT",  cd = { 28, 24, 20 }, target = true, range = { 99, 99, 99 } },
	-- 炮台（用户 2026-11-04：球关第一个新道具）：点自己的格放下一座，360° 慢转（BUILD.TURRET_ROT），每秒 rate 发往外打子弹（子弹 = 道具关那套：打到第一个非己方格染一格就消失、射程 10 格）；
	-- 活 dur 秒后消失；脚下格锁定（敌球撞上反弹、染不掉）；被敌方子弹打 hp 血打掉；同时最多 BUILD.TURRET_MAX 座
	-- 2026-11-04 晚四个新技能（用户口述定案）：
	-- 分裂球：dur 秒内全队每颗球（含小球、分身）每撞一次敌格从撞点弹出一颗小球（沿反射的另一侧飞），小球活 life 秒、照常染格；同时最多 max 颗（且全队 ≤ MAX_BALLS_PER_TEAM），到上限才不再分裂（用户 2026-11-05 夜：上限 ×2、小球也能分裂）。跟分身的区别：分身一下炸开一圈、几秒收回；分裂球是边打边生
	shatter   = { name = "SHATTER",   cd = { 15, 15, 15 }, dur = { 5, 6, 7 }, max = { 8, 12, 16 }, life = { 2.5, 3, 3.5 } },   -- 2026-11-05 夜用户：12 s 就刷新太短，三级冷却统一 15 s
	-- 冲击波（用户 2026-11-05 改）：以主球为中心、朝正前方张开 arc 度的圆弧（SHOCK_SPEED 格/秒）往外扩到棋盘外，弧扫到的格全染（越远弧越宽、吃的格越多）；弧碰到的敌球被沿径向推开 + 停 SHOCK_STUN 秒
	shock     = { name = "SHOCKWAVE", cd = { 14, 12, 10 }, arc = { 60, 90, 120 } },
	-- 链式闪电（用户 2026-11-05 定案）：从主球出发，链头以 CHAIN_SPEED 格/秒一颗接一颗飞向场上**全部**敌球（含分身小球，贪心最近），打中的原地停 stun 秒（不染格、不停整队）；
	-- 白色闪电链飞完 CHAIN_LINGER 秒就消失，被定的球靠电笼抖动表现（cd_sim s.chains → GUI FX.shock_sync）；场上没敌球放不出（不进冷却）
	chain     = { name = "CHAIN LIGHTNING", cd = { 16, 15, 14 }, stun = { 1.5, 2, 2.5 } },   -- 2026-11-05 夜用户：太频繁，冷却 10/9/8 → 16/15/14
	-- 滚雪球：dur 秒内主球每撞一次敌格大一圈（最多 steps 圈，半径从 BALL_RADIUS 线性长到 max_r），到时缩回；被冰冻波碰到 / 被链电劈到 / 被冲击波撞到缩回 0 圈
	-- 爆雪（用户 2026-11-05："滚大的爆炸效果，只不过爆炸的格子不能太多"）：长满 steps 圈后再撞一次敌格 → 撞点周围半径 burst 格的圆全染（1.2/1.6/2.0 = 5/9/13 格），技能随之结束、球回普通（2026-11-05 晚：用户不要炸完再长）
	snowball  = { name = "PLASMA",     cd = { 16, 15, 14 }, steps = { 5, 5, 5 }, max_r = { 0.85, 1.0, 1.15 }, burst = { 1.2, 1.6, 2.0 } },   -- 没有 dur：撞够 steps 次别的颜色再撞一下才炸、才结束（用户 2026-11-05 夜）
	turret    = { name = "TURRET",    cd = { 16, 15, 14 }, target = true, dur = { 8, 10, 12 }, rate = { 2, 2.5, 3 }, damage = { 10, 11, 12 }, hp = { 100, 120, 140 } },   -- 2026-11-01 用户：冷却加长 28/24/20（一级胜率 81% 太高）   -- 2026-10-30 用户：取消限距（range 机制留着，99 = 不限），冷却 24/20/16   -- 传送反过来：越高级越快（用户 2026-10-27 深夜）；平衡实验 2026-10-28：冷却拉长没用（一级 18→24 s 胜率反升到 91%），强在"跳进敌区深处"，改成一/二级限距 10/16 格、三级不限
}
-- 玩家专属技能（炸弹 2026-10-31 只给玩家）：电脑配技能时跳过，sim 里非玩家队放也直接拒绝。
-- 冰冻 2026-10-30 起曾是玩家专属；2026-11-03 用户改口：减速电脑也可以拥有，但一关里最多一个电脑有（cd_levels.roll 里 FREEZE_BOTS_MAX）
M.PLAYER_ONLY_SKILLS = { bomb = true }
M.FREEZE_BOTS_MAX = 1
M.FREEZE_AI_DELAY = 6      -- 电脑开局这么多秒内不放冰冻（2026-11-03 网页实测：GO 一响三级冰冻把全场冻 6 s，开局就没法玩）
-- 电脑手里的技能冷却覆盖表（没列的技能两边一样）：冰冻电脑拿到 18/20/24，我方仍 12/15/20（用户 2026-11-03：冷却太短）。取值走 cd_sim.skill_cd
M.BOT_SKILL_CD = { freeze = { 18, 20, 24 } }
-- ---------------------------------------------------------------- 道具关（build 模式，用户 2026-11-03：第二种打法，偶数关；设计稿 docs/superpowers/specs/2026-11-03-clashdoz-build-mode-design.md）
-- 没有球、没有能量槽：底栏三个钮 = 三样道具，点钮再点棋盘放下，节奏只靠冷却。cd_sim 里 ITEMS 和 SKILLS 同一套 can_cast / skill_cd。
M.ITEM_IDS = { "cannon", "amp", "soldier" }
M.BUILD_ITEM_IDS = { "cannon", "amp" }   -- 这局实际发的道具：士兵先收起来（用户 2026-11-03 晚：先测大炮；士兵规则待重做——只能走己方格 / 凑人数占 / 炮优先打兵）
M.ITEMS = {
	-- 大炮（用户 2026-11-03 二改，照 Color Clash 原版 CannonCardProduct：maxAngle / rotationSpeed / bounceLimit）：占 3×3 格、脚印锁定（只有士兵能占）；
	-- 炮口朝非己方格的重心，在 face ± arc 的扇区里来回扫（BUILD.CANNON_SWEEP 弧度/秒），每 1/rate 秒打一颗；
	-- 子弹不穿透：穿过己方地盘，打到第一个非己方格就染那一格、消失；碰棋盘边/空洞反弹 bounce 次；BULLET_LIFE 秒兜底
	-- 2026-11-03 晚四改，照拆包出来的原版 CardStatsSettings：hitsPerSecond 10（一串子弹）、damage 10/11/12…、低级 bounceLimit 0、子弹 speed 10；格子血量 CellUpgradeSettings.hpAmounts[0] = 4（一发就翻）
	cannon  = { name = "CANNON",    cd = { 10, 9, 8 }, target = true, rate = { 10, 10, 10 }, damage = { 10, 11, 12 }, hp = { 100, 110, 120 }, arc = { 0.785, 0.785, 0.785 }, bounce = { 0, 0, 0 } },   -- hp：原版 hitPoints 100/110/120，敌方子弹打到脚印扣血，打空炮就没了
	-- 放大器（原版 MultiplierGate：gateWidth 4、platformWidth 6）：一道 1×GATE_LEN 的门，垂直于炮口方向横在己方格上；己方子弹穿过门的任一格一颗变 mult 颗（每颗对同一门只触发一次）；门的格不锁，任一格被敌方染掉门就没了
	amp     = { name = "AMPLIFIER", cd = { 9, 8, 7 },  target = true, mult = { 2, 3, 4 }, hp = { 300, 330, 360 } },   -- hp：原版 MultiplierGate hitPoints 300；脚下格锁定，靠子弹打掉，不再"格子被占门就没"（用户 2026-11-03 深夜）
	-- 士兵：点敌方大炮；从离它最近的己方格冒出 count 个，直线走过去，任一个到了炮就归己方（脚下格换色）；被敌方子弹打中/出棋盘/掉洞就没了；不染格
	soldier = { name = "SOLDIERS",  cd = { 10, 9, 8 }, target = true, count = { 3, 4, 5 } },
}
M.BUILD = {
	BULLET_SPEED = 10,     -- 子弹速度（格/秒），原版 CannonBullet.speed 10
	BULLET_LIFE = 1.0,     -- 子弹飞多久消失（秒）= 射程 10 格：炮只打得到前面 10 格，前线推远了就得往前放新炮（原版 CannonBullet._lifeTime；视频里扇形半径就这么大）
	BULLET_MAX = 100,      -- 每队同时在飞的子弹上限（每秒 10 发 × 5 门 + 放大器）
	CELL_HP = 4,           -- 格子血量（原版新手联赛 hpAmounts[0] = 4，一发伤害 10 → 一发翻；用户 2026-11-03 深夜：两发翻看不懂，去掉）
	AI_FIRST = 3,          -- 电脑开局几秒后放第一件（原版 BotAiSettings.secondsBeforeFirstPlay 3）
	AI_EVERY = 4,          -- 之后每隔几秒放一件（原版 secondsBetweenCardPlayed 4）
	CELLS = 16,            -- 道具关（多人形状关）每边格数；1v1 场地另用 ARENA 24×48（原版 default 场地文件就是 24 列 × 48 行）
	ARENA = { w = 24, h = 48, time = 90 },
	CANNON_SIZE = 2,       -- 炮台占 2×2 格（16 格盘上和原版 24 格盘上的炮比例差不多）
	GATE_LEN = 3,          -- 放大器门长（格），原版 gateWidth 5.2 / 24 格 ≈ 16 格盘上 3 格
	CANNON_SWEEP = 1.2,    -- 炮管扫动角速度（弧度/秒）：45° 半角来回一趟约 2.6 s
	CANNON_MAX = 4,        -- 每队大炮上限（含起始炮）
	TURRET_MAX = 3,        -- 球关炮台技能：每队同时最多几座
	TURRET_ROT = 1.6,      -- 炮台自转（弧度/秒），一圈约 4 s
	AMP_MAX = 3,           -- 每队放大器上限
	AMP_SPREAD = 0.45,     -- 放大后子弹之间的夹角（弧度）
	SOLDIER_SPEED = 6,     -- 士兵速度（格/秒）
	SOLDIER_HIT = 0.6,     -- 子弹离士兵这么近算打中（格）
	CAPTURE_R = 0.7,       -- 士兵离炮这么近算占领（格）
}
M.ENEMY_SKILL_IDS = {}
for _, id in ipairs(M.SKILL_IDS) do if not M.PLAYER_ONLY_SKILLS[id] then M.ENEMY_SKILL_IDS[#M.ENEMY_SKILL_IDS + 1] = id end end
M.SKILL_MAX_LEVEL = 3
--- 技能 / 道具定义（同一套按钮、冷却、瞄准流程）
function M.def(id) return M.SKILLS[id] or M.ITEMS[id] end
M.SLOTS_DEFAULT = 2        -- 一局最多带 2 种
M.SLOTS_MAX = 3            -- 第 3 位金币开（cd_profile.PRICES.slot）
M.DUEL_CARDS = 4           -- 每组第 10 关 1 V 1 对决：关卡固定给 4 种技能，不能改（用户 2026-11-02）；其余关自己选
M.SKILL_POINTS_LEVEL = { 1, 3, 7 }    -- 技能卡累计几点升到几级：解锁 1 点、一升二 2 点、二升三 4 点，升满 7 点（用户 2026-11-04 晚定；收藏页按钮一次扣够，cd_profile.upgrade）
M.FIRE_DELAY = 0.35        -- 火焰落地延时：给"从天而降"演出时间
-- 关卡装置（用户 2026-11-01：棋盘上要有传送阵 / 加速装置，关卡才复杂）
M.PORTAL_CD = 1.0          -- 球被传送后这么久内不再被任何传送阵吸（否则落地立刻被传回去）
M.BOOST_MULT = 1.8         -- 加速装置：踩到的那颗球自己提速倍数
M.BOOST_DUR = 2.0          -- 持续秒
M.BOOST_CD = 2.5           -- 同一颗球再次被同类装置加速的间隔
M.RACE_R = 1.2             -- 竞速关：球心离星星中心这么近算到达（格）
M.TRACK_TURN_COOLDOWN = 0.5   -- 跑道关转向冷却（只比操控，要跟手；普通关 TURN_COOLDOWN 1 s）
M.TRACK = -1               -- 跑道格（竞速关，用户 2026-11-01）：谁也染不了、谁也挡不住，只有墙/边界挡球；不计入占地
M.WAVE_SPEED = 30          -- 冰冻波扩散速度（格/秒）；盖满棋盘（对角 ≈ 46 格）约 1.5 s
M.SHOCK_SPEED = 30         -- 冲击波圆弧扩散速度（格/秒），扩到对角约 1.5 s
M.SHOCK_STUN = 0.4         -- 被冲击波撞到的敌球停这么久
M.CHAIN_SPEED = 60         -- 链电链头飞行速度（格/秒），一颗到下一颗十几格 ≈ 0.2 s
M.CHAIN_LINGER = 0.15      -- 链打完全部目标后再显示多久就消失（用户 2026-11-05：不要一直连着）

--- 点数 → 等级（0..3）
function M.level_for_points(points)
	local lv = 0
	for k, need in ipairs(M.SKILL_POINTS_LEVEL) do if (points or 0) >= need then lv = k end end
	return lv
end

-- Coins
M.START_COINS = 100
M.PLACE_COINS = { 50, 30, 20, 10 }

-- 前 4 色 = 原型四队；5..9 给 1 打 8 布局（nine）用（2026-10-26 关卡制试玩）；第 10 色 2026-11-03 加（关卡最多 9 个电脑 = 10 队）
M.TEAMS = {
	{ name = "RED",    color = vmath.vector4(0.94, 0.33, 0.33, 1) },
	{ name = "BLUE",   color = vmath.vector4(0.25, 0.56, 0.96, 1) },
	{ name = "GREEN",  color = vmath.vector4(0.20, 0.76, 0.46, 1) },
	{ name = "YELLOW", color = vmath.vector4(0.98, 0.78, 0.20, 1) },
	{ name = "PURPLE", color = vmath.vector4(0.62, 0.40, 0.93, 1) },
	{ name = "ORANGE", color = vmath.vector4(0.98, 0.55, 0.20, 1) },
	{ name = "CYAN",   color = vmath.vector4(0.25, 0.82, 0.88, 1) },
	{ name = "PINK",   color = vmath.vector4(0.96, 0.45, 0.72, 1) },
	{ name = "LIME",   color = vmath.vector4(0.68, 0.88, 0.25, 1) },
	{ name = "BROWN",  color = vmath.vector4(0.72, 0.50, 0.30, 1) },
}
M.DEFAULT_LAYOUT = "quad"   -- quad 四象限 4 队 | duel 左右两半 2 队 | nine 3×3 九队（玩家正中）

return M
