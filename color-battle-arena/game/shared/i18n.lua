-- shared/i18n.lua
-- 多语言（2026-10-10，spec docs/superpowers/specs/2026-10-09-foundation-i18n-layout-design.md）
-- gettext 式：英文原文当 key，T("LEVEL CLEAR") 查当前语言表，没有就原样返回。
-- 语言 = 本地保存的手动选择（playdoz/i18n.lang）> 设备语言匹配 > 英文。
-- 桌面单测没有 sys/gui/window 全局，所有 Defold 调用都要守卫。
local M = {}

M.LANGS = { "zh-Hans", "zh-Hant", "ja", "ko", "de", "fr", "es", "it", "pt", "ru", "tr", "vi", "id" }
local AVAIL = {}
for _, tag in ipairs(M.LANGS) do AVAIL[tag] = true end
-- Android 旧语言码（Java Locale）→ 现代码
local ALIAS = { ["in"] = "id", iw = "he", ji = "yi" }

-- 已随包发布的翻译表：bob 只打包 require 字面量能扫到的 Lua 模块，所以每张表都要在这里写一条（子项目 3 加语言时补行）
M.LOADERS = {
    ["zh-Hans"] = function() return require("shared.i18n.zh_hans") end,
    ["zh-Hant"] = function() return require("shared.i18n.zh_hant") end,
    ["ja"] = function() return require("shared.i18n.ja") end,
    ["ko"] = function() return require("shared.i18n.ko") end,
    ["de"] = function() return require("shared.i18n.de") end,
    ["fr"] = function() return require("shared.i18n.fr") end,
    ["es"] = function() return require("shared.i18n.es") end,
    ["it"] = function() return require("shared.i18n.it") end,
    ["pt"] = function() return require("shared.i18n.pt") end,
    ["ru"] = function() return require("shared.i18n.ru") end,
    ["tr"] = function() return require("shared.i18n.tr") end,
    ["vi"] = function() return require("shared.i18n.vi") end,
    ["id"] = function() return require("shared.i18n.id") end,
}

M.lang = "en"
local tbl = {}          -- 当前翻译表：英文 → 译文
local rev = {}          -- 译文 → 英文（apply 幂等用，Task 3）
local inited = false
local warned = {}

function M.module_name(tag)
    local name = tostring(tag):lower():gsub("%-", "_")
    return "shared.i18n." .. name
end

--- 设备语言 → 可用表里的 key。device_lang 如 "zh-Hans-CN"/"pt-BR"，lang 如 "zh"，territory 如 "TW"
---（HTML5/Android 的 device_language 往往只有 "zh"，地区单放在 territory；2026-10-13 网页 zh-TW 曾被归到简中）。
--- 匹配顺序：完整标签 → 逐段去掉区域 → 中文按区域/脚本（含 territory）归到 zh-Hans/zh-Hant → 基础语言。都没有 → nil（英文）
function M.pick_lang(avail, device_lang, lang, territory)
    if type(avail) ~= "table" then return nil end
    local tag = tostring(device_lang or lang or "")
    local parts = {}
    for seg in tag:gmatch("[^%-_]+") do parts[#parts + 1] = seg end
    if parts[1] then
        local b = parts[1]:lower()
        parts[1] = ALIAS[b] or b
        for i = 2, #parts do
            local s = parts[i]
            parts[i] = (#s == 4) and (s:sub(1, 1):upper() .. s:sub(2):lower()) or s:upper()   -- Hans / CN
        end
    end
    for n = #parts, 1, -1 do
        local key = table.concat(parts, "-", 1, n)
        if avail[key] then return key end
    end
    local base = parts[1] or tostring(lang or ""):lower()
    base = ALIAS[base] or base
    if base == "zh" then
        local up = (tag .. "-" .. tostring(territory or "")):upper()
        local script = (up:find("HANT") or up:find("TW") or up:find("HK") or up:find("MO")) and "zh-Hant" or "zh-Hans"
        if avail[script] then return script end
    end
    if avail[base] then return base end
    return nil
end

local function save_path()
    if sys and sys.get_save_file then return sys.get_save_file("playdoz", "i18n") end
end
function M.saved_lang()
    local p = save_path(); if not p then return nil end
    local ok, d = pcall(sys.load, p)
    return (ok and type(d) == "table" and d.lang ~= "" and d.lang) or nil
end

local function load_table(tag)
    tbl, rev = {}, {}
    if tag == "en" then return true end
    local loader = M.LOADERS[tag] or function() return require(M.module_name(tag)) end
    local ok, t = pcall(loader)
    if not ok or type(t) ~= "table" then
        if not warned[tag] then warned[tag] = true; print("[i18n] no table for " .. tostring(tag) .. ", fallback en") end
        return false
    end
    tbl = t
    for k, v in pairs(t) do rev[v] = k end
    return true
end

local function detect()
    -- 网页版只做英文（用户 2026-10-21：网页就是一个页面，多语言起不到引流作用，省字体容量省麻烦）；网页壳的字体也只带 ASCII（SoloGames/web_overrides）
    if sys and sys.get_sys_info then
        local ok, info = pcall(sys.get_sys_info)
        if ok and type(info) == "table" and info.system_name == "HTML5" then
            -- 网页版固定英文（2026-10-21 定案）；只有 debug 引擎认 ?lang=xx（商店多语言截图用网页包渲染，2026-10-22）
            local eok, einfo = pcall(sys.get_engine_info)
            if eok and einfo and einfo.is_debug and html5 and html5.run then
                local qok, q = pcall(html5.run, "location.search")
                local tag = qok and type(q) == "string" and q:match("[?&]lang=([%w%-]+)") or nil
                if tag and (tag == "en" or AVAIL[tag]) then return tag end
            end
            return "en"
        end
    end
    local saved = M.saved_lang()
    if saved and (saved == "en" or AVAIL[saved]) then return saved end
    if sys and sys.get_sys_info then
        local ok, info = pcall(sys.get_sys_info)
        if ok and type(info) == "table" then
            return M.pick_lang(AVAIL, info.device_language, info.language, info.territory) or "en"
        end
    end
    return "en"
end

function M.init()
    if inited then return end
    inited = true
    local tag = detect()
    M.lang = load_table(tag) and tag or "en"
    local ok, info = (sys and sys.get_sys_info) and pcall(sys.get_sys_info) or false, nil
    info = (ok and type(info) == "table") and info or {}
    print("[i18n] lang=" .. M.lang .. " device_language=" .. tostring(info.device_language) .. " language=" .. tostring(info.language) .. " territory=" .. tostring(info.territory) .. " saved=" .. tostring(M.saved_lang()))   -- 真机/网页日志排错用（tools/web_i18n_smoke.py 断言 "[i18n] lang=xx"）
end

--- 翻译。非字符串原样返回；没译文返回原文。
--- 上下文键 "NEXT|step"（2026-10-14）：同一英文在不同场合译法不同（结算页 NEXT=下一关、说明页 NEXT=下一步）时用 "原文|场合"，
--- 表里按整键给专门译文；没有就回落到 "原文" 的译文，英文直接显示 "原文"。
function M.t(key)
    if type(key) ~= "string" then return key end
    if not inited then M.init() end
    local v = tbl[key]
    if v then return v end
    local base = key:match("^(.-)|[%w_]+$")
    if base then return tbl[base] or base end
    return key
end

--- 译文 → 原文（apply 幂等用）；不是译文就返回 nil
function M.source_of(text) return rev[text] end

--- 手动切换（tag = "en" 或 LANGS 之一；nil = 清掉选择回到跟随设备）。立即生效，已显示的文字要各界面自己重建。
function M.set_lang(tag)
    local p = save_path()
    if p then pcall(sys.save, p, { lang = tag or "" }) end
    inited = true
    if tag == nil then tag = detect() end
    if tag ~= "en" and not AVAIL[tag] then tag = "en" end
    M.lang = load_table(tag) and tag or "en"
end

--- 静态 .gui 文本节点：按 id 列表翻译（Defold 没有枚举节点的 API）。各 gui_script 的 init 里调一次；
--- 再调也安全：节点里已是译文时先反查回原文再翻。
function M.apply(ids)
    if not gui then return end
    for _, id in ipairs(ids or {}) do
        local ok, n = pcall(gui.get_node, id)
        if ok and n then
            local cur = gui.get_text(n)
            local src = M.source_of(cur) or cur
            gui.set_text(n, M.t(src))
        end
    end
end

--- 文字节点宽度超过 max_w 时等比缩小 scale（德语/俄语长词塞进固定宽度的胶囊/卡片）。返回最终 scale.x。
--- 注意：引擎 1.13 已删 gui.get_text_metrics，量宽走 resource.get_text_metrics(gui.get_font_resource(...))；量不到就不动（绝不因此报错让界面黑屏）
function M.fit(node, max_w)
    local s = gui.get_scale(node)
    local ok, m = pcall(function() return resource.get_text_metrics(gui.get_font_resource(gui.get_font(node)), gui.get_text(node)) end)
    if not ok then print("[i18n] fit: text metrics unavailable: " .. tostring(m)); return s.x end
    local w = (m and m.width or 0) * s.x
    if w <= max_w or w <= 0 then return s.x end
    local k = max_w / w
    gui.set_scale(node, vmath.vector3(s.x * k, s.y * k, s.z))
    return s.x * k
end

-- require 时就选好语言（sys 不存在的桌面单测里是 "en"）；各 gui_script 不必手动 init
M.init()

return M
