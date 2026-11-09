-- games/clashdoz/cd_rng.lua（移植自 github.com/eickegao/clashdoz main/rng.lua，规则不改，只改 require 路径）
-- Deterministic pseudo random generator (Park-Miller). Every client that
-- starts from the same seed produces the same sequence, which keeps the
-- simulation reproducible.
local M = {}

local MOD = 2147483647
local MUL = 16807

function M.new(seed)
	local s = math.floor(seed) % MOD
	if s <= 0 then
		s = s + MOD - 1
	end
	return { state = s }
end

-- float in [0, 1)
function M.next(r)
	r.state = (r.state * MUL) % MOD
	return (r.state - 1) / (MOD - 1)
end

-- integer in [lo, hi]
function M.range(r, lo, hi)
	return lo + math.floor(M.next(r) * (hi - lo + 1))
end

return M
