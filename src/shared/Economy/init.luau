--!strict
-- Economy: level math shared by the server and wallet HUD. XP is lifetime XP; level one
-- starts at zero, and advancing from level n costs round(12 * n^2.15) additional XP, so
-- every level costs more than the last: 12 XP for level 2, about 2,000 for level 10,
-- about 40,000 for level 50. Why this curve and its pacing: docs/economy.md § Balance.

local Economy = {}

function Economy.required(level: number): number
	return math.round(12 * level ^ 2.15)
end

function Economy.progress(xp: number): (number, number, number)
	local level = 1
	local remaining = math.max(0, xp)
	while remaining >= Economy.required(level) do
		remaining -= Economy.required(level)
		level += 1
	end
	return level, remaining, Economy.required(level)
end

-- The XP still to earn before lifetime `xp` reaches level `target`; 0 once it has.
function Economy.toReach(xp: number, target: number): number
	local level, into = Economy.progress(xp)
	local needed = -into
	for each = level, target - 1 do
		needed += Economy.required(each)
	end
	return math.max(0, needed)
end

return Economy
