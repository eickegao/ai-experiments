-- arena stub: no level progress
local M = {}
function M.get_level() return 1 end
function M.set_level() end
function M.load() return { level = 1 } end
function M.save() end
function M.reset() end
return M
