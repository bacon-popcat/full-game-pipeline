---
name: game-feel
description: >
  Make a game feel good to play, calm and satisfying rather than noisy: feedback for every
  action, readable status, motion that eases, sounds and VFX used sparingly, pleasing flows,
  onboarding and no harsh fail states. Use for "make it feel better", "more satisfying",
  polish passes, juice, onboarding, adding feedback to an action, or when a feature works but
  feels flat, confusing or stressful.
---

# Game feel

The target is a **calm, satisfying industrial farming game**: watching crops grow and items
flow is the reward. Feedback should feel soft and certain, never loud. Pair this skill with
`roblox-ui` (screens), `roblox-vfx` (effects), `sound-effects` (audio cues) and
`roblox-skills:roblox-audio` (playback).

## Feedback ladder

Every player action answers at once, then gets confirmed. Use the lowest rung that makes the
change clear:

1. **The state itself is visible.** Belt items slide, a tube fills with sap, a crop changes
   stage, the machine's status text changes. This is the most satisfying feedback, so build
   it first.
2. **Instant local response.** The client predicts the result (the inventory moves at once,
   the ghost goes green or red), and the server's snapshot corrects it if it was wrong.
3. **A small motion.** Buttons respond to hover and press through `UI.bindButton`, panels ease
   open, and an item that arrives in the inventory pulses once. Honour
   `GuiService.ReducedMotionEnabled`.
4. **A sound.** One short, quiet cue for a completed action (harvest, sale, machine done), and
   rate-limit it when many happen in a row.
5. **VFX.** Kept for moments that matter: a rare mutation, a level up, a weather change.

Stop at the first rung that does the job. A cue that only repeats what the screen already
shows is noise.

## Calm, not flat

- **No harsh failure.** A full machine stops and its belt backs up, and nothing is destroyed.
  A blocked placement shows a red ghost and an explanation, never just a buzz. Weather is a
  bonus, not a punishment.
- **Rewards scale with rarity.** Common harvests are quiet, and a Golden or Rainbow mutation
  gets its own colour, sound and a server-wide moment if it's rare enough. Keep the steps of
  that scale few and consistent.
- **Flows read at a glance.** Items keep one model across lanes, they space evenly, and they
  never teleport. Belts that back up visibly explain themselves.
- **Status in words.** Hover text and panels share one formatter (`BlockText`), so
  "Waiting for Coal" reads the same everywhere. Explain *why* something is idle.
- **Light, soft visuals** (see `blender-studio-assets`): warm light colours, rounded shapes,
  low contrast. Avoid neon overload, screen shake and flashing.
- **Countdowns for waiting**: the next crop stage, the shop restock, the end of the weather.
  Waiting the player can see is calm; waiting they can't see is frustrating.

## Onboarding

Teach by doing, in the loop's order: plant a seed, harvest it, sell it, buy a seed, place the
first machine. Show one prompt at a time, attached to the thing it's about, and let the player
skip it. Hints come from `Controls` for the current `PreferredInput`, so touch players never
see "Press E".

## Polish pass checklist

- [ ] Every remote-backed action responds within a frame (prediction or optimistic UI).
- [ ] Every refusal says why (out of reach, not your plot, inventory full, need level N).
- [ ] Every machine and crop state can be seen in the world without opening a panel.
- [ ] At most one sound per gesture, rate-limited, with a mute option if sounds repeat.
- [ ] Rare outcomes are celebrated; common ones stay quiet.
- [ ] Reduced motion is respected, and no motion loops forever unless it shows work being done.
- [ ] A new player reaches the first sale without reading anything long.
