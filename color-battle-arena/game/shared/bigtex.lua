-- shared/bigtex.lua
-- 大背景图不进图集（2026-09-30 包瘦身）：图集里的纹理按原始像素存、只做 LZ4，实景大图压不动；
-- 改为 PNG 原文件打进包（game.project custom_resources 加 /assets/bigtex），进场时解码成 gui 动态纹理贴上去——
-- 画质零损失，包体约省一半（1080×2340 一张：进包 6 MB → PNG 3 MB），代价是进场多约 0.1–0.2 秒解码。
-- 用法：bigtex.apply(node, "/assets/bigtex/<game>/<name>.png")；同一 gui 场景里重复调用不重复解码。
-- 注意：gui 动态纹理属于该 gui 场景，场景（collection proxy）卸载后要重建；本模块记录的"已建"表只是加速，失效时自动重建。
local M = {}
local created = {}   -- id → true（可能因场景卸载而失效，set_texture 失败即重建）

function M.apply(node, path)
    local id = "bigtex:" .. path
    if created[id] and pcall(gui.set_texture, node, id) then return true end
    local data = sys.load_resource(path)
    if not data then print("[bigtex] missing resource " .. path); return false end
    local pic = image.load(data, { premultiply_alpha = true })
    if not pic then print("[bigtex] decode failed " .. path); return false end
    local ok, code = gui.new_texture(id, pic.width, pic.height, pic.type, pic.buffer, false)
    if not ok and code ~= gui.RESULT_TEXTURE_ALREADY_EXISTS then
        print("[bigtex] new_texture failed " .. path .. " code " .. tostring(code)); return false
    end
    created[id] = true
    gui.set_texture(node, id)
    return true
end

return M
