--!strict
-- Economy: level math shared by the server and wallet HUD. XP is lifetime XP; level one
-- starts at zero, and advancing from level n costs round(20 * n^2.75) additional XP.

local Economy = {}

function Economy.required(level: number): number
	return math.round(20 * level ^ 2.75)
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

return Economy
