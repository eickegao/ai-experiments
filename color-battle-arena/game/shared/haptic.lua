-- arena stub: web has no haptics
local M = {}
for _, k in ipairs({ "tap", "light", "medium", "heavy", "success", "warning", "error", "init" }) do M[k] = function() end end
return M
