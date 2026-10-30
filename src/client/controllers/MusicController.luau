-- MusicController: plays Shared/Music's calm tracks in the background, flat to this player.
-- Each track fades in, plays through, fades out, then a quiet gap of a random length before the
-- next; the order is reshuffled every pass and never repeats the track that just played. Tracks
-- with no id are skipped, so the game is whole without music.
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Music = require(ReplicatedStorage.Shared.Music)

local MusicController = {}

local function shuffled(last: string?): { Music.Track }
	local order = {}
	for _, track in Music.TRACKS do
		if track.id ~= "" then
			table.insert(order, track)
		end
	end
	for i = #order, 2, -1 do
		local j = math.random(i)
		order[i], order[j] = order[j], order[i]
	end
	if #order > 1 and order[1].id == last then
		order[1], order[#order] = order[#order], order[1]
	end
	return order
end

local function play(sound: Sound, track: Music.Track)
	sound.SoundId = track.id
	sound.Volume = 0
	sound.TimePosition = 0
	pcall(ContentProvider.PreloadAsync, ContentProvider, { sound })
	if not sound.IsLoaded or sound.TimeLength <= 0 then
		return
	end
	local fade = TweenInfo.new(Music.FADE, Enum.EasingStyle.Sine)
	sound:Play()
	TweenService:Create(sound, fade, { Volume = Music.VOLUME }):Play()
	task.wait(math.max(sound.TimeLength - Music.FADE, 0))
	local out = TweenService:Create(sound, fade, { Volume = 0 })
	out:Play()
	out.Completed:Wait()
	sound:Stop()
end

function MusicController.init()
	local sound = Instance.new("Sound")
	sound.Name = "Music"
	sound.Looped = false
	sound.Parent = SoundService
	task.spawn(function()
		-- a short breath after joining before the first track
		task.wait(3)
		local last: string? = nil
		while true do
			local order = shuffled(last)
			if #order == 0 then
				return
			end
			for _, track in order do
				play(sound, track)
				last = track.id
				task.wait(Music.GAP_MIN + math.random() * (Music.GAP_MAX - Music.GAP_MIN))
			end
		end
	end)
end

return MusicController
