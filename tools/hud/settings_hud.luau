--[[
Authors the Gifting row in the Settings window, StarterGui.HUD.Settings.Body.Gifting (the place
file only; conventions.md § UI): a label and an On and an Off button, each with a Selected bar,
cloned from the LightingQuality row so it looks the same (Settings.luau binds it).

The Settings body is laid out by hand in Scale, so the row takes the gap under the lighting note
and the rows below it move down a little; the window grows 40 px to keep them roomy.

Run it through the Studio MCP in the Edit datamodel: fetch this file into a temporary ModuleScript
(or paste it), require it and call the function it returns. Safe to rerun: the row is removed and
rebuilt, and the moves are to fixed places.
]]
local StarterGui = game:GetService("StarterGui")

return function()
	local settings = StarterGui:WaitForChild("HUD").Settings
	local body = settings.Body
	local old = body:FindFirstChild("Gifting")
	if old then
		old:Destroy()
	end
	old = body:FindFirstChild("GiftingNote")
	if old then
		old:Destroy()
	end

	local row = body.LightingQuality:Clone()
	row.Name = "Gifting"
	row.Position = UDim2.new(0, 20, 0.62, 0)
	row.Size = UDim2.new(1, -40, 0.08, 0)
	row.Label.Text = "Gifting"
	row.Medium:Destroy()
	row.Low.Name = "On"
	row.On.Text = "On"
	row.High.Name = "Off"
	row.Off.Text = "Off"
	row.Off.Position = row.On.Position + UDim2.fromOffset(110, 0)
	-- FindFirstChild: a button's own Selected property would win over the child of that name.
	row.On:FindFirstChild("Selected").Visible = true
	row.Off:FindFirstChild("Selected").Visible = false
	row.Parent = body

	local note = body.LightingNote:Clone()
	note.Name = "GiftingNote"
	note.Text = "Walk up to a player to give what you hold  •  both need it on  •  saved"
	note.Position = UDim2.new(0, 20, 0.7, 0)
	note.Parent = body

	settings.UISizeConstraint.MaxSize = Vector2.new(530, 510)
	body.GraphicsDivider.Position = UDim2.new(0, 20, 0.765, 0)
	body.ControlsHeading.Position = UDim2.new(0, 20, 0.77, 0)
	body.ControlsHeading.Size = UDim2.new(1, -40, 0.06, 0)
	body.ControlsHint.Position = UDim2.new(0, 20, 0.825, 0)
	body.ControlsHint.Size = UDim2.new(1, -40, 0.08, 0)
	body.SaveQuit.Position = UDim2.fromScale(0.5, 0.915)
	body.SaveQuit.Size = UDim2.new(0, 220, 0.075, 0)
	return "Settings: Gifting row"
end
