--!strict
-- Controls: every key and button the inventory and building respond to, and the hint
-- text that names them, kept together so a rebind is one edit and the hints can't drift.

local Controls = {}

Controls.TOGGLE_BACKPACK = { Enum.KeyCode.B, Enum.KeyCode.ButtonY }
-- Puts a lifted stack back first; closes the backpack on the next press.
Controls.BACK = { Enum.KeyCode.ButtonB }
Controls.ROTATE = { Enum.KeyCode.R, Enum.KeyCode.ButtonX }
-- Drops one of the held item into the world (or onto the conveyor aimed at).
Controls.DROP = { Enum.KeyCode.Q, Enum.KeyCode.Backspace, Enum.KeyCode.DPadDown }
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

local function key(text: string): string
	return `<font color="#FFFFFF">{text}</font>`
end

local HINTS: { [Enum.PreferredInput]: string } = {
	[Enum.PreferredInput.KeyboardAndMouse] = `{key("Click")} a slot, then another, or {key("drag")} to move.\n`
		.. `{key("1-9")} hold  ·  {key("R")} rotate  ·  {key("Q")} drop  ·  {key("B")} close`,
	[Enum.PreferredInput.Touch] = `{key("Tap")} a slot, then tap where it goes.\nTap the hotbar to hold an item.`,
	[Enum.PreferredInput.Gamepad] = `{key("A")} lift / put down  ·  {key("B")} back\n`
		.. `{key("LB RB")} hold  ·  {key("X")} rotate  ·  {key("D-pad down")} drop  ·  {key("Y")} close`,
}

-- Rich text describing the backpack controls for `input`.
function Controls.hint(input: Enum.PreferredInput): string
	return HINTS[input] or HINTS[Enum.PreferredInput.KeyboardAndMouse]
end

return Controls
