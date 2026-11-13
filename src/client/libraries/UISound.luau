--!strict
-- UISound: when the interface makes a sound. The shared layers call it, so no screen does: UI's
-- buttons (hover, press, a press on a button that is not available), PopupMotion's modal windows
-- and HubWindow's own-animated ones (open, close). The roles are Shared/Sounds' UI* entries.
--
-- Each cue has a gap under which a repeat is dropped, so sweeping the pointer over a grid or
-- hammering a button does not machine-gun. A window closing because another is opening (Screens
-- hands over in one frame) is silent: only the open is heard. The close waits a moment for that,
-- which is why it is deferred.
local Sound = require(script.Parent.Sound)

-- Seconds within which a repeat of the same cue is dropped.
local GAPS: { [string]: number } = { UIHover = 0.06, UIClick = 0.05, UIDeny = 0.25, UIOpen = 0.1, UIClose = 0.1 }
-- How long a close waits to hear whether a window is opening in its place.
local HANDOVER = 0.05

local last: { [string]: number } = {}
local closing = 0

local UISound = {}

local function play(role: string)
	local now = os.clock()
	if now - (last[role] or -math.huge) < GAPS[role] then
		return
	end
	last[role] = now
	Sound.play(role)
end

function UISound.hover()
	play("UIHover")
end

function UISound.click()
	play("UIClick")
end

function UISound.deny()
	play("UIDeny")
end

function UISound.window(show: boolean)
	closing += 1
	if show then
		play("UIOpen")
		return
	end
	local mine = closing
	task.delay(HANDOVER, function()
		if mine == closing then
			play("UIClose")
		end
	end)
end

return UISound
