-- arena stub: English only (user 2026-11-09). t() returns the English key unchanged.
local M = { lang = "en", LANGS = {} }
function M.t(s) return s end
function M.init() end
function M.fit(node, max_w) if gui and gui.set_scale then end end
function M.set_lang() end
return M
