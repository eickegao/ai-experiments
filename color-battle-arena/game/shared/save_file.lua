-- shared/save_file.lua
-- 存档路径薄壳：sys.get_save_file 的大小写回退（2026-10-22）。
-- 真机（iOS/Android 文件系统区分大小写）"PlayDoz" 与 "playdoz" 是两个目录，各自正常。
-- iOS 模拟器的容器落在 Mac 不分大小写的磁盘上，两个名字撞同一目录，Defold 1.14 用 NSFileManager 建目录
-- 返回失败（-1000），sys.get_save_file 直接抛错，所有读进度的入口（PLAY 键）全部中断。
-- 这里失败时退回小写目录再试一次；小写也失败才把原错误抛出去。真机永远走第一次调用，行为不变。
local M = {}

function M.path(dir, name)
    local ok, p = pcall(sys.get_save_file, dir, name)
    if ok then return p end
    local lower = string.lower(dir)
    if lower ~= dir then
        local ok2, p2 = pcall(sys.get_save_file, lower, name)
        if ok2 then return p2 end
    end
    error(p, 2)
end

return M
