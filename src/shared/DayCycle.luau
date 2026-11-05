--!strict
-- DayCycle: the world's time of day, derived from server time so every client (and any server
-- feature that wants it) agrees without a remote. One full day takes LENGTH real seconds, and
-- the daylight hours (DAWN to DUSK) take DAYLIGHT of it, so most play happens by day and the
-- night passes quickly. Nothing is saved; a fresh server simply picks up the same clock.

local DayCycle = {}

DayCycle.LENGTH = 20 * 60
DayCycle.DAWN = 6
DayCycle.DUSK = 18.5
-- Share of each cycle spent between DAWN and DUSK.
DayCycle.DAYLIGHT = 0.75

-- The ClockTime (0-24) at server time `now` (workspace:GetServerTimeNow()).
function DayCycle.clock(now: number): number
	local phase = (now % DayCycle.LENGTH) / DayCycle.LENGTH
	local dayHours = DayCycle.DUSK - DayCycle.DAWN
	local hour = if phase < DayCycle.DAYLIGHT
		then DayCycle.DAWN + dayHours * (phase / DayCycle.DAYLIGHT)
		else DayCycle.DUSK + (24 - dayHours) * ((phase - DayCycle.DAYLIGHT) / (1 - DayCycle.DAYLIGHT))
	return hour % 24
end

return DayCycle
