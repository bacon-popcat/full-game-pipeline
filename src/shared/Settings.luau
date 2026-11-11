--!strict
-- Settings: the player preferences that are saved per player (not per save file), their
-- allowed values and defaults. SettingsService saves them and mirrors each one as a Player
-- attribute of the same name; the client reads the attribute and applies it.

local Settings = {}

export type Name = "LightingQuality" | "Gifting"

Settings.LIGHTING_QUALITIES = { "Low", "Medium", "High" }
-- Whether other players may hand this player gifts, and this player may hand them out: a gift
-- needs it On for both (Shared/Social).
Settings.GIFTING = { "On", "Off" }

local DEFAULTS: { [Name]: string } = {
	LightingQuality = "High",
	Gifting = "On",
}
Settings.DEFAULTS = DEFAULTS

-- Whether `value` is an allowed value for setting `name`; both come from a client.
function Settings.valid(name: any, value: any): boolean
	if name == "LightingQuality" then
		return typeof(value) == "string" and table.find(Settings.LIGHTING_QUALITIES, value) ~= nil
	elseif name == "Gifting" then
		return typeof(value) == "string" and table.find(Settings.GIFTING, value) ~= nil
	end
	return false
end

return Settings
