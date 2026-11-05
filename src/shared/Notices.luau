--!strict
-- Notices: the kinds of message Remotes.Notify carries and the colour each shows in. The server
-- names a kind with every notice it sends; the client's Toasts stack them above the hotbar in
-- that colour. Only messages worth stopping for are sent at all: a refusal, a reward, a rare
-- harvest, a milestone. Routine income (a Shipping Bin's sales, a common mutation) is not a notice;
-- the wallet and the item cards already show it. Toasts draw in Sarpanch Bold, whose colon
-- renders as one dot, so messages avoid colons.

export type Kind = "Info" | "Success" | "Error" | "Reward" | "Achievement" | "Quest" | "Rare"

local COLORS: { [Kind]: Color3 } = {
	Info = Color3.fromRGB(235, 235, 245),
	Success = Color3.fromRGB(157, 220, 154),
	Error = Color3.fromRGB(240, 140, 130),
	Reward = Color3.fromRGB(255, 214, 102),
	Achievement = Color3.fromRGB(255, 196, 92),
	Quest = Color3.fromRGB(142, 197, 255),
	Rare = Color3.fromRGB(193, 173, 244),
}

local Notices = {}

Notices.DEFAULT = "Info" :: Kind

-- Whether an untrusted value names a kind.
function Notices.isKind(value: unknown): boolean
	return typeof(value) == "string" and COLORS[value :: Kind] ~= nil
end

function Notices.color(kind: Kind): Color3
	return COLORS[kind] or COLORS.Info
end

return Notices
