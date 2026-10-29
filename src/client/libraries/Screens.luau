--!strict
-- Screens: one owner for mutually exclusive HUD windows, without controller cycles.
local Screens = {}
local closers: { [string]: () -> () } = {}
function Screens.register(name: string, close: () -> ())
	closers[name] = close
end
function Screens.claim(name: string)
	for other, close in closers do
		if other ~= name then
			close()
		end
	end
end
return Screens
