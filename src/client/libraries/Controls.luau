--!strict
-- Controls: every key and button the inventory and building respond to, and the hint
-- text that names them, kept together so a rebind is one edit and the hints can't drift.

local Controls = {}

Controls.TOGGLE_BACKPACK = { Enum.KeyCode.E, Enum.KeyCode.ButtonY }
-- Puts a lifted stack back first; closes the backpack on the next press.
Controls.BACK = { Enum.KeyCode.ButtonB }
Controls.ROTATE = { Enum.KeyCode.R, Enum.KeyCode.ButtonX }
-- Drops one of the held item into the world (or onto the conveyor aimed at).
Controls.DROP = { Enum.KeyCode.Q, Enum.KeyCode.Backspace, Enum.KeyCode.DPadDown }
-- Opens (and closes) the panel of the machine or router aimed at. Touch gets an on-screen
-- button instead, shown while one is aimed at.
Controls.INTERACT = { Enum.KeyCode.F, Enum.KeyCode.DPadUp }
Controls.HOTBAR_PREVIOUS = { Enum.KeyCode.ButtonL1 }
Controls.HOTBAR_NEXT = { Enum.KeyCode.ButtonR1 }
-- Key i selects hotbar slot i.
Controls.HOTBAR_SLOTS = {
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
	Enum.KeyCode.Four,
	Enum.KeyCode.Five,
	Enum.KeyCode.Six,
	Enum.KeyCode.Seven,
	Enum.KeyCode.Eight,
	Enum.KeyCode.Nine,
}

local INTERACT_HINTS: { [Enum.PreferredInput]: string } = {
	[Enum.PreferredInput.KeyboardAndMouse] = `Press {Controls.INTERACT[1].Name} to open its controls.`,
	[Enum.PreferredInput.Touch] = "Tap Open to see its controls.",
	[Enum.PreferredInput.Gamepad] = "Press D-pad up to open its controls.",
}

-- How to open the panel of the machine aimed at, for `input`.
function Controls.interactHint(input: Enum.PreferredInput): string
	return INTERACT_HINTS[input] or INTERACT_HINTS[Enum.PreferredInput.KeyboardAndMouse]
end

return Controls
