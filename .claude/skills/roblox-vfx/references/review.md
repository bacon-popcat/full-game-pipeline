# Reviewing an effect

How to look at an effect and what to ask of every capture. The mechanics (VFXScrub,
VFXCamera, the harness, source checksums) are in `structure.md` "Testing"; this file is the
judging. Effects are judged by eye: tell the user what you checked and ask them to look at it
at full speed.

Adapted from Roqer's VFX skill (https://github.com/S4US/Roqer, `roblox-animation-vfx`
reference `vfx-craft.md` section 6, AGPL-3.0-or-later).

## Two views

Capture each moment from both:
- **Close**, to judge shapes: `VFXCamera.Lock(cf, "ThreeQuarter")` or `"Side"` at a distance
  that fits the effect, an R15 dummy for scale.
- **From where the player sees it.** This view decides whether the effect works. In a
  playtest, the client's own camera behind the character is that view. In Edit mode, put the
  camera behind and a little above the caster's spot, looking at the effect. `ctx.CFrame`'s
  LookVector points toward the attacker, so that is the "Front" side:
  `VFXCamera.Lock(cf, { Yaw = 0, Pitch = 10 }, { Distance = range + 12 })` sits about where
  the player's camera would (Pitch 5-15). A projectile's impact is seen from its whole
  range away: the close view hides an impact that is a speck at range; the far view shows it.
On a character, the character can hide an effect played in front of it: frame it from a side
as well.

## Which moments

Pick the 4-6 moments that matter: anticipation, the flash, the peak, the body at about 0.3 s,
the smoke, and a time just past the effect's end (to see that nothing is left behind, and as
the empty background for the colour check). Use the same times from both views. Save the
captures as image files named by effect time (`0.10.png`) in one folder per view, so the
tools below can read them.

## Tools

- **Colour check:** `node tools/vfx/clip.mjs tone --dir <captures> --empty <capture past the end>`
  reports the share of the effect's pixels that are pale, vivid, deep and blown out. Studied
  effects run 2-21% pale, 35-90% vivid or deep, 0-9% blown out; the tool says what to change
  when it is washed out or blown out.
- **Against a reference clip:** `node tools/vfx/clip.mjs compare <clip dir> --captures <captures>`
  puts each capture beside the clip's frame at the same effect time (`structure.md`,
  "Matching a reference video").
- **Flipbooks you drew:** `node tools/vfx/flipbook.mjs <sheet>` before uploading
  (`drawing-textures.md`).

## Ask of each capture

- From the player's view, does the payoff fill its share of the screen (`design.md` section
  1)? Does it grow taller for a moment, or stay a flat splash on the floor? At 0.3 s, is a body
  (crescents, tongues, puffs) still carrying the mass, or only shards and sparks?
- Do the sharp shapes glow above the bloom threshold while soft glows stay dim? A soft glow
  above it is a white haze; a shape at Brightness 1-3 is flat paint at Threshold 2. Is the
  colour check washed out?
- Does the flash frame read as one sharp, overexposed shape, bigger than what follows it, and
  is it gone by 0.15 s, so the frames after it show the body? A 30-stud flash that held for
  0.2 s without fading whited out the caster for a dozen frames from the player's camera.
- Is there something dark, so the bright parts read?
- Do the drawn shapes have hard silhouettes, or do they look like soft smudges? (Flares and
  glows are soft.)
- Is the centre a white blob? Bring the stacked bright layers down until the coloured shapes
  show through. A pale effect on a light floor needs its darks most (cobalt, navy, black
  accents).
- Does any drawn texture look like clip art or an icon: radially symmetric, evenly spaced, or
  drawn with even outlines? Does a flare have bent or unequal arms or a lumpy core?
- Does everything that moves carry its speed (streaks, wind rings, a smear), or does it float?
- Is a large half-transparent shell covering the view?
- From the player's camera, does a flat ground ring grow wider than its distance from the
  camera? It then passes under the camera, and its far edge is a thin line across the view.
- Does a light tint the whole floor?
- Does the smoke beside the fire take its colour, or is it one flat tone?
- For fire: is the body a boiling mass of sheets, or one image scaling up? Is the darkest
  smoke a brief burn-out, or a dark puff that lingers? (`explosions.md` section 7.)
- Does every layer show? Thin sparks and faint smoke vanish at a normal camera distance.
- Does one layer bury another?
- Does anything stay constant that should change?
- Does it end cleanly, with nothing left behind?
- Does a moving slash's tapered tail trail its direction of travel, rather than point ahead
  of it?
- Does the silhouette still read with post-processing off, against both a dark and a bright
  background?
- Is a warning (telegraph) distinguishable from the hit it warns of?
- With several players repeating the move near the camera, does it still read and stay in
  budget? Budget the simultaneous view, not one effect alone.

From Roqer's general effect reference (`full.md`): break a natural effect into behaviours
rather than one emitter doing everything (a water impact is a surface ring, heavy upward
splashes, fine droplets, then lingering mist, each with its own lifetime, speed, scale and
transparency), and reserve dense spectacle for rare events so routine actions stay legible.

These sit alongside the grading loop in `structure.md` (grader subagent against the
reference, then the file-integrity check).
