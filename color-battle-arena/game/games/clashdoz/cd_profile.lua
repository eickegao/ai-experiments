-- arena stub: no skill cards / shop. Loadouts come from the arena draft.
local M = { PRICES = { point = 100, slot = 500 } }
function M.on_win() return 0 end
function M.loadout() return {} end
function M.slots() return 3 end
return M
