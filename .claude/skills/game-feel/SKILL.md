---
name: game-feel
description: >
  Make a game feel good to play: feedback for every action, readable status, eased motion,
  sound and VFX used deliberately, satisfying flows, onboarding, and failure that fits the
  target feel. Use for "make it feel better", "more satisfying", polish passes, juice,
  onboarding, adding feedback to an action, or when a feature works but feels flat,
  confusing or stressful.
---

# Game feel

Start from the target feel in the design doc (`game-design-plan`). "Calm and satisfying" and
"punchy and frantic" need opposite choices: a calm game uses soft, certain feedback, and an
action game can shake the screen. Pair this skill with `roblox-ui` (screens), `roblox-vfx`
(effects) and `sound-effects` (audio cues).

## The feedback ladder

Every action gets an instant response, then a confirmation. Use the lowest rung that makes
the change clear:

1. **The state itself is visible.** Items slide along, a pipe fills, a crop changes stage, a
   status line changes. This is the most satisfying feedback, so build it first.
2. **An instant local response.** The client predicts the result (the inventory moves at
   once, the ghost turns green or red), and the server's snapshot corrects it if it was
   wrong.
3. **A small motion.** Buttons react to hover and press, panels ease open, and a new item
   pulses once. Honour reduced-motion settings (`GuiService.ReducedMotionEnabled` on Roblox).
4. **A sound.** One short cue for a completed action, rate-limited when many happen in a row.
5. **VFX.** Save these for moments that matter: a rare drop, a level up, a world event.

Stop at the first rung that does the job. A cue that only repeats what the screen already
shows is noise.

## Principles

- **Make failure match the feel.** In a relaxed game, nothing is destroyed: a full machine
  stops and its queue backs up, and a blocked action explains itself instead of buzzing. A
  tense game can punish, but it should still say why.
- **Rewards scale with rarity.** Keep common outcomes quiet. Rare ones get their own colour,
  sound and, if rare enough, a server-wide moment. Use a few consistent levels.
- **Flows read at a glance.** Moving things space out evenly, keep one model the whole way and
  never teleport. A queue that backs up explains itself.
- **Status in words.** Use one formatter, so hover text and panels always agree, and say why
  something is idle ("Waiting for coal").
- **Show the wait.** Give a countdown for each timer: the next growth stage, the shop restock,
  the end of an event. A wait the player can see feels fair; one they can't see feels broken.
- **Keep effects consistent.** Use one easing family, one set of durations, and one palette
  for good, bad and rare.

## Onboarding

Teach by doing, in the order of the core loop: the first action, its first reward, spending
that reward, then the first upgrade. Show one prompt at a time, attached to the thing it's
about, and make it skippable. Write hints for the player's current input device, so touch
players never see "Press E".

## Polish checklist

- [ ] Every networked action responds within a frame, through prediction or optimistic UI.
- [ ] Every refusal says why: out of reach, not yours, inventory full, need level N.
- [ ] Every object's state can be read in the world without opening a panel.
- [ ] At most one sound per gesture, rate-limited, with mute for anything that repeats.
- [ ] Rare outcomes are celebrated; common ones stay quiet.
- [ ] Reduced motion is respected, and nothing animates forever unless it shows work
      happening.
- [ ] A new player reaches the first reward without reading a wall of text.
