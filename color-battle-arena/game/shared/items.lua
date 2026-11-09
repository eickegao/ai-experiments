-- shared/items.lua
-- 通用道具库存（2026-09-28 用户：统一商店/道具，其他游戏复制推广）。每个游戏一份：
--   local inv = require("shared.items").new("hexmerge", CATALOG, { bomb = 2 })
-- CATALOG[id] = { price = 金币价, icon = 图集里的图名, name = "显示名", desc = "一句说明" }，ORDER 决定商店里的顺序。
-- 库存存在 <game>/items（v=save_ver，默认 1）。buy 走 shared.coin.deduct；看视频接口预留（广告 SDK 接入后实现）。
-- save_ver：游戏改了初始赠送且想让旧存档按新规则重来时 +1（版本不符 → 丢掉旧库存重发 starter；上架后别再动，会清掉玩家买的）。
local coin = require("shared.coin")
local M = {}

function M.new(game_key, catalog, starter, order, save_ver)
    local VER = save_ver or 1
    local self = { game = game_key, catalog = catalog, order = order or {} }
    if #self.order == 0 then for id in pairs(catalog) do self.order[#self.order + 1] = id end; table.sort(self.order) end
    local inv, eq
    local function path() return sys.get_save_file(game_key, "items") end
    local function load()
        if inv then return end
        local d = sys.load(path())
        if d and d.v == VER then inv = d.items or {}; eq = d.eq or {}
        else
            inv, eq = {}, {}
            for k, v in pairs(starter or {}) do inv[k] = v end
            sys.save(path(), { v = VER, items = inv, eq = eq })
        end
    end
    local function save() sys.save(path(), { v = VER, items = inv, eq = eq }) end

    function self.count(id) load(); return inv[id] or 0 end
    function self.add(id, n) load(); inv[id] = (inv[id] or 0) + (n or 1); save() end
    function self.use(id)
        load()
        if (inv[id] or 0) <= 0 then return false end
        inv[id] = inv[id] - 1; save(); return true
    end
    --- 金币买 1 个：成功 true，金币不够 false
    function self.buy(id)
        local it = catalog[id]
        if not it or not coin.deduct(it.price, game_key .. "_buy_" .. id) then return false end
        self.add(id, 1); return true
    end
    --- 装备（2026-09-29 HEXA MERGE 起）：从库存里拿出放到游戏的装备栏，不扣库存，用掉时 use + unequip。
    --- eq = 有序列表 { {id=, n=}, ... }（装备先后决定位置），跨关、跨启动保留。
    function self.equipped() load(); return eq end
    function self.equipped_n(id)
        load()
        for _, e in ipairs(eq) do if e.id == id then return e.n end end
        return 0
    end
    --- 还没装备的数量（抽屉/背包里显示这个）
    function self.available(id) return self.count(id) - self.equipped_n(id) end
    function self.equip(id)
        if self.available(id) <= 0 then return false end
        for _, e in ipairs(eq) do if e.id == id then e.n = e.n + 1; save(); return true end end
        eq[#eq + 1] = { id = id, n = 1 }; save(); return true
    end
    function self.unequip(id)
        load()
        for i, e in ipairs(eq) do
            if e.id == id then
                e.n = e.n - 1
                if e.n <= 0 then table.remove(eq, i) end
                save(); return true
            end
        end
        return false
    end

    --- 看视频换 1 个：广告 SDK 未接入时恒 false；接入后在 watch 里播激励视频，成功回调 self.add(id,1)
    function self.video_available() return false end
    function self.watch(id, cb) if cb then cb(false) end end
    return self
end

return M
