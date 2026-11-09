-- shared/layout.lua
-- 屏幕适配公共模块（2026-10-10）：设计尺寸、长屏出血、安全区、宽屏（iPad / iPhone Duo）判断。
-- 1.2.0 只收拢公式；各游戏的平板布局表 1.3.0 再填。按宽高比不按机型判断（Apple 对 Duo 的要求也是 size class）。
local safe_area = require("shared.safe_area")
local M = { W = 1080, H = 1920 }

local function size()
    if not window or not window.get_size then return 0, 0 end
    local ok, w, h = pcall(window.get_size)
    if not ok then return 0, 0 end
    return w or 0, h or 0
end

--- 长屏上下出血（设计坐标）：FIT 适配按宽缩放后，屏幕比 1920 多出来的高度的一半；宽屏/未就绪为 0
function M.extra()
    local w, h = size()
    if w <= 0 or h <= 0 then return 0 end
    return math.max(0, (M.W * h / w - M.H) / 2)
end

--- 宽屏：iPad（0.75）、iPhone Duo 内屏（0.70）/外屏（0.69）为 true；iPhone（0.46）为 false
function M.is_wide()
    local w, h = size()
    return w > 0 and h > 0 and (w / h) > 0.6
end

--- 可用设计宽度：宽屏按高 FIT 后横向能用的设计像素 = 1920 * w / h（iPad Pro 11 2018 约 1341、3:4 iPad 1440、Duo 内屏约 1350）；
--- 手机 / 未就绪恒 1080。坐标一律从这里实时取，不写死某一款 iPad 的数（用户 2026-10-19）
function M.width()
    if not M.is_wide() then return M.W end
    local w, h = size()
    return M.H * w / h
end

--- 左右出血（设计坐标）：宽屏每侧比 1080 多出来的宽度；贴左/右边的元素按它平移
function M.extra_x()
    return (M.width() - M.W) / 2
end

--- 全屏遮罩/幕布尺寸：宽 = max(1080, 可用宽度) + 4，高 = 1920 + 上下出血×2 + 4（各留 4 余量防缝）。
--- 节点要放在屏幕中心（顶级节点 (540,960)；挂在居中 root 下则 (0,0)），三种 iPad 尺寸和长屏手机都铺满
function M.cover_size()
    return math.max(M.W, M.width()) + 4, M.H + 2 * M.extra() + 4
end

--- 把一个遮罩节点撑满整屏（用户 2026-10-19：iPad 上 profile 的阴影没铺满）
function M.fill(node)
    local w, h = M.cover_size()
    gui.set_size(node, vmath.vector3(w, h, 0))
end

--- 顶栏贴边元素的 x（用户 2026-10-19：所有游戏的返回/声音键在 iPad 上没按屏幕宽度贴边）：
--- 距中心 ≥ 200 的元素按左右出血外推，离屏幕边的距离与手机版一致；居中元素原样；手机/未就绪不变
function M.edge_x(x)
    if x <= -200 then return x - M.extra_x() end
    if x >= 200 then return x + M.extra_x() end
    return x
end

--- 把一组节点（节点或 .gui 节点 id）按 edge_x 贴边；在顶栏按安全区上下移之后调用（只改 x）
function M.snap_edges(list)
    if not M.is_wide() then return end
    for _, n in ipairs(list) do
        if type(n) == "string" then n = gui.get_node(n) end
        local p = gui.get_position(n)
        p.x = M.edge_x(p.x)
        gui.set_position(n, p)
    end
end

--- 整屏背景图在宽屏上的铺法（iPad 2026-10-19）：手机沿用原 STRETCH 不动（返回 false）；宽屏改成 FIT 节点，
--- 尺寸 = 先最多横向拉伸 max_stretch（默认 1.2，画面不明显变形），还不够宽就按比例放大、上下裁边。
--- img_w/img_h 是贴图像素；节点要挂在居中 root 下的 (0,0)。
--- v_bias（可选，-1..1）：上下裁边的偏向——0 居中裁；+1 底边对齐（只裁顶部，保住画面底部）；-1 顶边对齐（保住顶部标题）；
--- 传了就按偏向把节点 y 挪到 v_bias × 裁掉总高/2（手机不动）
function M.fit_bg(node, img_w, img_h, max_stretch, v_bias)
    if not M.is_wide() then return false end
    max_stretch = max_stretch or 1.2
    local wd, hd = M.width(), M.H + 2 * M.extra()
    local a = img_w / img_h
    local wn = hd * a                                  -- 按高铺满时的自然宽
    local w, h
    if wn >= wd then w, h = wn, hd                     -- 图本来就够宽：左右裁
    else
        local f = math.min(wd / wn, max_stretch)       -- 横向拉伸系数（封顶）
        w, h = wd, wd / (a * f)                        -- 拉伸后仍不够宽的部分靠放大补，上下裁
    end
    gui.set_adjust_mode(node, gui.ADJUST_FIT)
    gui.set_size(node, vmath.vector3(w, h, 0))
    if v_bias and v_bias ~= 0 then
        local p = gui.get_position(node)
        p.y = v_bias * (h - hd) / 2
        gui.set_position(node, p)
    end
    return true
end

--- 一张图所有屏幕通用的铺法（2026-10-20 用户 Ball Sort 3:4 新封面）：任何屏幕都按"短边铺满、多出来的裁掉"
--- （CSS object-fit: cover），手机也生效——这是与 fit_bg 的区别（fit_bg 手机不动、宽屏才改）。
--- 节点改 FIT、挂在居中 root 下的 (0,0)；尺寸 = 盖住 可用宽 × (1920+2×出血) 的最小等比尺寸。
--- 3:4 图：iPad 按高铺左右略裁，手机按高铺左右裁掉约 1/4；给 iPad 画的封面只要两侧 100 内不放重点就能通用。
function M.cover(node, img_w, img_h)
    local wd, hd = M.width(), M.H + 2 * M.extra()
    local a = img_w / img_h
    local w, h
    if hd * a >= wd then w, h = hd * a, hd      -- 图比屏幕宽：按高铺，左右裁
    else w, h = wd, wd / a end                  -- 图比屏幕窄：按宽铺，上下裁
    gui.set_adjust_mode(node, gui.ADJUST_FIT)
    gui.set_size(node, vmath.vector3(w, h, 0))
    return w, h   -- 调用方可据此把图里的像素坐标换算成设计坐标：scale = h / img_h（Pupdoku 2026-10-20）
end

--- 触点增量 → FIT 子节点设计坐标增量的系数 kx, ky（用户 2026-10-21：Spider/FreeCell 拖着的牌、封面滚动列表在 iPad 上不跟手）。
--- action.x/y 是按 1080×1920 分别缩放的（横按 w、竖按 h），而 STRETCH root 下的 FIT 子节点统一按 min(w/1080, h/1920) 缩放：
--- 手机（按宽 FIT）：kx=1、ky=h/1920÷(w/1080)=1/k；iPad（按高 FIT）：kx=k、ky=1；k = 1920*w/(1080*h)。未就绪 1,1。
function M.touch_scale()
    local w, h = size()
    if w <= 0 or h <= 0 then return 1, 1 end
    local k = (M.H * w) / (M.W * h)
    if k >= 1 then return k, 1 end
    return 1, 1 / k
end

--- 绝对触点 → FIT 子节点空间（屏幕中心 540,960 为不动点）；拖动用增量更稳，这个给需要绝对位置的场合
function M.touch_fit(x, y)
    local kx, ky = M.touch_scale()
    return M.W / 2 + (x - M.W / 2) * kx, M.H / 2 + (y - M.H / 2) * ky
end

function M.safe_top() safe_area.init(); return safe_area.top or 0 end
function M.safe_bottom() safe_area.init(); return safe_area.bottom or 0 end

--- 坐标表选择：宽屏且给了 wide 表就用 wide（缺的项回落 phone），否则 phone
function M.pick(phone, wide)
    if not wide or not M.is_wide() then return phone end
    return setmetatable(wide, { __index = phone })
end

return M
