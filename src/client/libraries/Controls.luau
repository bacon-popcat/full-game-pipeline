--!strict
-- Controls: every key and button the inventory, building and prompts respond to, kept
-- together so a rebind is one edit and the hints that name them can't drift.

local Controls = {}

Controls.TOGGLE_BACKPACK = { Enum.KeyCode.E, Enum.KeyCode.ButtonY }
-- Puts a lifted stack back first; closes the backpack on the next press.
Controls.BACK = { Enum.KeyCode.ButtonB }
Controls.ROTATE = { Enum.KeyCode.R, Enum.KeyCode.ButtonX }
-- Drops one of the held item into the world (or onto the conveyor aimed at).
Controls.DROP = { Enum.KeyCode.Q, Enum.KeyCode.Backspace, Enum.KeyCode.DPadDown }
-- Works the nearest ProximityPrompt (PromptController), which is how a machine, router or
-- Crafting Bench opens (BlockPrompts); closes that window again. Touch taps the prompt's card.
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

return Controls
