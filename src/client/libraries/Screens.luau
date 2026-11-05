--!strict
-- Screens: one owner for mutually exclusive HUD windows, without controller cycles. Each window
-- registers how to close it, and optionally how to open it, so another screen (the Menu) can
-- open it by name without requiring the controller that owns it.
local Screens = {}
local closers: { [string]: () -> () } = {}
local openers: { [string]: () -> () } = {}
function Screens.register(name: string, close: () -> (), open: (() -> ())?)
	closers[name] = close
	openers[name] = open
end
function Screens.claim(name: string)
	for other, close in closers do
		if other ~= name then
			close()
		end
	end
end
-- Opens a registered window; false when no window of that name can be opened.
function Screens.open(name: string): boolean
	local open = openers[name]
	if not open then
		return false
	end
	open()
	return true
end
return Screens
