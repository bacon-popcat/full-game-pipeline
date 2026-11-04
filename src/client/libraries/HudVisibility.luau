--!strict
-- HudVisibility: whether the HUD shows, and Roblox's own player list and chat, arbitrated from
-- named requests (conventions.md): each feature hides them under its own name and releases only
-- that, so the save menu (HUD only, until a garden is picked) and the full-screen Research view
-- (everything) never fight. Roblox's settings are captured before the first change and given back
-- once nothing asks to hide them.
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")

local HudVisibility = {}

-- Per source: true to hide the HUD and Roblox's UI, false to hide just the HUD.
local requests: { [string]: boolean } = {}
local baseline: { playerList: boolean, chatWindow: boolean?, chatInput: boolean? }? = nil

local function chatConfigs(): (ChatWindowConfiguration?, ChatInputBarConfiguration?)
	return TextChatService:FindFirstChildOfClass("ChatWindowConfiguration"),
		TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
end

local function apply()
	local hud = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local screen = if hud then hud:FindFirstChild("HUD") else nil
	local anything, everything = false, false
	for _, all in requests do
		anything = true
		everything = everything or all
	end
	if screen and screen:IsA("ScreenGui") then
		screen.Enabled = not anything
	end
	local window, input = chatConfigs()
	if everything and not baseline then
		baseline = {
			playerList = StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList),
			chatWindow = if window then window.Enabled else nil,
			chatInput = if input then input.Enabled else nil,
		}
	end
	local saved = baseline
	if not saved then
		return
	end
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, saved.playerList and not everything)
	if window and saved.chatWindow ~= nil then
		window.Enabled = saved.chatWindow and not everything
	end
	if input and saved.chatInput ~= nil then
		input.Enabled = saved.chatInput and not everything
	end
	if not everything then
		baseline = nil
	end
end

-- Hides (or stops hiding) the HUD for `source`; `everything` hides Roblox's player list and chat
-- too.
function HudVisibility.hide(source: string, hidden: boolean, everything: boolean?)
	requests[source] = if hidden then everything == true else nil
	apply()
end

return HudVisibility
