-- shared/utils.lua
-- 通用工具模块，对应 Flutter 中各游戏散布的工具函数

local M = {}

--- 限制值在 [min_val, max_val] 范围内
-- @param value number
-- @param min_val number
-- @param max_val number
-- @return number
function M.clamp(value, min_val, max_val)
    if value < min_val then return min_val end
    if value > max_val then return max_val end
    return value
end

--- 线性插值
-- @param a number 起始值
-- @param b number 结束值
-- @param t number 插值因子 [0, 1]
-- @return number
function M.lerp(a, b, t)
    return a + (b - a) * t
end

--- 将 0xAARRGGBB 格式的颜色值转换为 Defold 的 vmath.vector4(r, g, b, a)
-- 对应 Dart 的 Color(0xFFRRGGBB)
-- @param hex number 如 0xFF3366CC
-- @return vector4
function M.hex_to_rgba(hex)
    local a = math.floor(hex / 16777216) % 256 / 255
    local r = math.floor(hex / 65536) % 256 / 255
    local g = math.floor(hex / 256) % 256 / 255
    local b = hex % 256 / 255
    return vmath.vector4(r, g, b, a)
end

--- 两点之间的距离
-- @param x1 number
-- @param y1 number
-- @param x2 number
-- @param y2 number
-- @return number
function M.distance(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

--- Fisher-Yates 洗牌算法
-- 对应 Dart 的 list.shuffle()
-- @param t table 要洗牌的数组（会修改原数组）
-- @return table 返回同一个数组
function M.shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

--- 屏幕坐标转游戏世界坐标
-- Defold 的坐标系原点在左下角，Y轴向上
-- @param screen_x number 屏幕X坐标
-- @param screen_y number 屏幕Y坐标
-- @param screen_width number 屏幕宽度
-- @param screen_height number 屏幕高度
-- @param design_width number 设计宽度 (1080)
-- @param design_height number 设计高度 (1920)
-- @return number, number 世界坐标
function M.screen_to_world(screen_x, screen_y, screen_width, screen_height, design_width, design_height)
    design_width = design_width or 1080
    design_height = design_height or 1920
    local scale_x = design_width / screen_width
    local scale_y = design_height / screen_height
    local scale = math.min(scale_x, scale_y)
    local offset_x = (screen_width - design_width / scale) / 2
    local offset_y = (screen_height - design_height / scale) / 2
    local world_x = (screen_x - offset_x) * scale
    local world_y = (screen_y - offset_y) * scale
    return world_x, world_y
end

--- 深拷贝 table
-- 对应 Dart 的 List.from() / Map.from()
-- @param orig table
-- @return table
function M.deep_copy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for k, v in pairs(orig) do
            copy[M.deep_copy(k)] = M.deep_copy(v)
        end
        setmetatable(copy, M.deep_copy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

--- 检查 table 是否包含某个值
-- 对应 Dart 的 list.contains()
-- @param t table
-- @param value any
-- @return boolean
function M.contains(t, value)
    for _, v in ipairs(t) do
        if v == value then return true end
    end
    return false
end

--- 从 table 中移除第一个匹配的值
-- 对应 Dart 的 list.remove()
-- @param t table
-- @param value any
-- @return boolean 是否找到并移除
function M.remove_value(t, value)
    for i, v in ipairs(t) do
        if v == value then
            table.remove(t, i)
            return true
        end
    end
    return false
end

--- 创建二维数组
-- 对应 Dart 的 List.generate(rows, (_) => List.filled(cols, default))
-- @param rows number
-- @param cols number
-- @param default_value any 默认值
-- @return table 二维数组
function M.create_2d_array(rows, cols, default_value)
    local arr = {}
    for r = 1, rows do
        arr[r] = {}
        for c = 1, cols do
            arr[r][c] = default_value
        end
    end
    return arr
end

return M
