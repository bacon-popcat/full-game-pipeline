--!strict
-- Music: the background tracks MusicController plays, calm instrumentals generated with
-- ElevenLabs Music and uploaded from assets/music. Played one at a time in a shuffled order,
-- with quiet gaps between them so the garden's own sounds have room.

export type Track = { name: string, id: string }

local Music = {}

Music.TRACKS = {
	{ name = "Morning Rows", id = "rbxassetid://98158215745086" },
	{ name = "Slow Harvest", id = "rbxassetid://111362374562794" },
} :: { Track }

-- Track volume, well under the effects, and seconds of fade in and out.
Music.VOLUME = 0.22
Music.FADE = 4
-- Seconds of silence between tracks, picked between these.
Music.GAP_MIN, Music.GAP_MAX = 25, 60

return Music
