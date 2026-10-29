---
name: sound-effects
description: Generate a small, coherent sound palette for game moments (UI presses, harvests, sales, machines finishing, rare mutations, ambience) through interchangeable provider adapters, starting with ElevenLabs Sound Effects, then wire it into Roblox and check in a playtest that the cues clarify rather than distract. Use when the game needs interaction sounds, feedback cues, machine or farm sounds, ambience, or audio polish. Triggers on sound effects, SFX, UI sounds, harvest sound, click sound, machine sound, ambience, ElevenLabs sound effects, audio feedback.
---

# Sound Effects

Sound is feedback, not wallpaper. Generate a short cue only when it confirms a change the
player needs to feel: a harvest landing in the inventory, a sale, a machine finishing, a rare
mutation, a panel opening. Never add one just because something moves. This is rung 4 of the
`game-feel` feedback ladder: check that the lower rungs aren't already enough.

## Before generating

1. Name the moment and the change it confirms. If the screen or the world already makes it
   obvious (belt items sliding, a crop changing stage), don't add a sound.
2. Match the game's feel: **calm, soft, warm, satisfying**. Wood, soil, gentle mechanical
   ticks and soft chimes; never harsh alarms, buzzers or arcade fanfare.
3. Sounds never carry meaning on their own, never autoplay loud, and the game must work with
   them muted.

## Generate a palette, not isolated noises

Start with three to five roles. Keep each one short, and quieter than music.

| Moment | Duration | Prompt shape |
| --- | --- | --- |
| UI press / select | 0.50 s | soft dry wooden click, no voice, no melody |
| Harvest / pick up | 0.50 s | gentle leafy pluck with a soft soil thump, warm |
| Sale / coins | 0.50–0.70 s | small soft coin chime, rounded, short decay |
| Machine done | 0.50–0.80 s | muted mechanical clunk and a soft bell tick |
| Rare mutation | 0.80–1.20 s | sparkling upward shimmer, airy, not a fanfare |
| Ambience (loop) | 10–20 s | calm countryside with distant soft machinery, no voice |

Always exclude voice and melody, and generate two or three alternatives per role so the user
can choose by listening side by side.

## Provider adapters

ElevenLabs is the first adapter, not the architecture. The generator takes a `--provider` name
and loads `scripts/providers/<name>.py`; every adapter shares the same prompt, duration, loop,
output and receipt contract. Read `references/provider-adapters.md` before adding one.

The ElevenLabs adapter calls `POST /v1/sound-generation` with `ELEVENLABS_API_KEY` from the
local environment. Never put the key in a prompt, source code, the repo or a committed `.env`.

```bash
python scripts/generate_sound.py --provider elevenlabs --name harvest-pluck --text "A gentle leafy pluck with a soft soil thump; warm, calm, quiet, no voice, no melody" --duration 0.5 --out "<scratchpad>/sounds/harvest-pluck.mp3"
```

Write generated audio to the session scratchpad (or a `sounds/` folder the user names), not
into `src/`, because Rojo doesn't sync audio files. ElevenLabs accepts durations from 0.5 s.
Use `--loop` only for ambience. The script writes the audio plus a JSON receipt with the
prompt and parameters, never the key.

## Wire into Roblox

- **Upload**: the user uploads the chosen files as Audio assets (Creator Hub or Studio's
  Asset Manager). Record each asset id with its role in one module, the `SFX` primitive in
  `Shared/` that `conventions.md` names. Create it if it's missing, and keep the ids in one
  table so a swap is one edit.
- **Play on the client** for the local player's own actions, after the visual change starts.
  A sound that plays before a change the server then rejects is misleading. For other players'
  actions, play spatially at the source (a machine finishing on a neighbour's plot) only if
  it's audible at a distance that makes sense.
- Route everything through SoundGroups (SFX, Ambience, Music), so there can be a volume and
  mute setting per group. Use one sound per completed gesture, and rate-limit repeats such as
  many harvests in a row or a belt of items arriving.
- For the Audio API, emitters and mixing, see `roblox-skills:roblox-audio`.

## Check

Playtest it (`studio-playtest`): do the action normally, quickly over and over, and with
several players near each other. Ask whether each cue makes clear what happened. If one only
repeats what the screen shows, or gets tiring after a minute, remove it.

## Boundaries

- Never generate speech here; use a speech tool for narration.
- Never spend credits or call the API until the user approves the chosen prompts and the
  number of variations.
