# Motion and held forms

Read with `design.md` for anything that travels, sweeps or is held: projectiles, volleys,
trails, beams, slashes, dashes, teleports, orbs, sigils and auras. The category recipes in
`recipes.md` (slash, spin slash, projectile, aura, movement) are the short version; this file
has the studied numbers behind them.

Adapted from Roqer's VFX skill (https://github.com/S4US/Roqer, `roblox-animation-vfx`
reference `vfx-motion.md`, AGPL-3.0-or-later). Marks as in `design.md`.

**Trails and our clock.** `Trail.Lifetime` is real time: set `trail.Lifetime = authored /
ctx.TimeScale` so a trail keeps its length in slow-mo, and capture trail layers while the
effect still plays slowly rather than frozen (`structure.md` "Engine gotchas").

## Projectiles

A projectile has three parts *(measured)*:
- **A head:** one sprite, such as a `VelocityParallel` diamond. Clear it at impact
  (`emitter:Clear()`), so it vanishes in that frame. To point it along a curved path, emit it
  with the projectile's own velocity: not locked to the part, the part turned to face along
  the path each frame, and `Speed` set to the projectile's speed each frame, with `Rotation`
  -90 for a head drawn point up *(verified)*. A `FacingCamera` head that looks alike from
  every angle needs none of this.
- **Ribbons:** 2-3 textured ribbons across a span of about 5 studs:
  - a sharp one: lifetime about 0.6, width tapering to 0, transparent for the first 15% of its
    length so there is a gap behind the head;
  - a soft one that bulges in the middle: lifetime about 0.85;
  - a short tendril: lifetime about 0.3.

  A trail is speed x lifetime long, and at impact all of it is still drawn. These lifetimes
  suit curving missiles: a fireball at 120 studs a second with 0.6-0.85 s ribbons left a
  straight line from the blast back to the thrower *(seen in a Roqer run)*. On a fast,
  straight shot keep the drawn length a few times the head's, fading the tail to Transparency 1
  (27 of 66 studied trails fade, 57 taper to nothing), or clear it at impact.
- **Shed particles:** droplets or specks at 15-60 a second, with gravity or drag, not locked
  to the part.

**Paths and volleys:**
- **Paths:** Bezier curves with 2-3 random control points 10-25 studs up. Give each
  projectile its own flight time (0.65-1.5 s), so the hits drum rather than land together. A
  summoned dragon swirls about 45 studs sideways.
- **Volleys:** 10-15 sources, one every 0.1 s, fanned ±20 studs behind and above the caster.
  Each source's emitters stop after 0.1-0.2 s, and their particles close it over 0.8-1.5 s.

**Anything that moves carries its speed** *(measured)*: `VelocityParallel` streaks shed behind
it, with `Squash`; flat wind rings shed backwards (negative Speed, growing to 7-12 studs over
0.3-0.6 s); curved wind beams from head to tail; a one-frame smear at launch. A projectile
that is only a sprite with a thin trail reads as floating, not thrown.

## Slashes, stabs and dashes

- **Slashes are drawn in time, not only in space.** One crescent sprite (flat, about 6.6
  studs, 0.2-0.3 s) plus about five invisible points along the arc. Each point emits sparks
  0.04-0.05 s after the one before, so the eye follows the blade around the arc. In our
  modules: one attachment moved along the arc, one burst per `ctx.Wait` (moving it twice in
  one frame does not move the spawn point; `structure.md` gotchas).
- **A crescent slash without a mesh:** sweep a ribbon through an arc. Two attachments on a
  part at the blade's inner and outer radius; rotate the part through `Spin` 160 degrees over
  0.14 s (`Quart` Out) with `ctx.Tween`, with a Trail between them (`FaceCamera = false`, width
  tapering to 0). A narrow band reads as a crescent, a wide one as a fan.
- **Roll the whole effect for a diagonal swing.** A flat slash seen from a low camera is
  edge-on and almost invisible, so check it from the game's real camera height.
- **Stabs and dashes:** a one-frame (0.04 s) flash moving at 155-444 studs a second, with
  `Squash` -0.5, reads as a motion smear. Pair it with a real move: about 15 studs in 0.075 s.

## Held beams

Use a few Beams plus many particles:
- **The body:** 2-3 camera-facing Beams, width 5-12. Give each its own `TextureLength`
  (0.75-150) and `TextureSpeed` (1-12), so the scrolls never line up. Fade the ends over 5-10%
  of the length, or make the body a capsule (Transparency `1, 0, 1` along it).
- **Fill:** `VelocityParallel` flame streaks at `Rate` 500-2000, Speed up to 300, Drag 10,
  `Squash` ramping 0 to 3.
- **The muzzle:** a crown of short curved beams, and flat shockwave rings.
- **Duration:** hold the beam 3.5-5 s, then collapse the widths to 0 over 0.5-1 s.
- **A drilling dash:** three beams around one axis that roll 180 degrees while their widths
  fall from 6 to 0 over 0.75 s.

## Beams and trails

- A Beam is a curve between two attachments; `CurveSize0` and `CurveSize1` bend it. Give it
  enough `Segments` to look smooth: at least one fewer than the number of Color and
  Transparency keypoints, and 20 or more for a visible curve. The studied slash beams use
  100-360.
- `TextureSpeed` scrolls the texture along the beam, the one built-in way to scroll a texture.
  Use it for flowing energy, lasers and lightning arcs.
- **Launch beams** *(measured)*: a beam whose width starts at 40-200 and tweens to 0 over
  0.15-0.4 s, with a transparency band that is clear at both ends (`0:1, 0.5:0, 1:1`), reads as
  a streak passing through.
- **Weapon trails come in pairs** *(measured)*: a thin hot core (Lifetime 0.04-0.15,
  Brightness 10-30) and a wide, soft, dark or coloured wisp (Lifetime 0.15-0.4,
  `LightEmission` 0.55-0.75). Both have a `WidthScale` that tapers to 0. Put the attachments at
  the base and tip of the blade, keep the trail disabled and enable it only for the swing.
- **Give every trail a texture** *(measured: 58 of 66 studied trails have one)*. Without one,
  a Trail is an even band of colour: three untextured missile trails read as flat purple tubes
  *(verified)*. The studied textures are streaks: a bright torn or dripping edge with streaks
  running back from it, a tapered shard, or a wisp. Their clear areas also hide part of the
  ribbon, so widen it or raise `Brightness` to keep its weight.
- **Which way a texture lies** *(verified)*: on a Trail or a Beam the image's vertical axis
  runs along its length and its horizontal axis across its width. On a Trail the top of the
  image is at the head and the bottom at the tail, and its left edge is at `Attachment0`
  (our gotcha for Beams: the image's top is at Attachment0). Draw trail and beam textures as
  vertical strips; a drawing made lengthwise comes out turned across the ribbon.

## Sustained forms: orbs, sigils and auras

- **The stack:** stationary billboards on one attachment, `Speed` 0.001 and `LockedToPart`.
- **The cross-fade:** `Rate` x `Lifetime` about 2-4, Transparency `0:1, 0.5:0, 1:1` and a random
  `Rotation`. Copies cross-fade, so the form holds but shimmers.
- **Size ladder:** core 1, rings about 2, halo about 3.5, black backdrop about 4.5.
- **Ground sigils:** 5-7 studs, lifetime 2, spinning 0.5-5 degrees a second, in two or three
  sizes that shrink slightly as they live, so the circle breathes.
- **Healing over time pulses:** a burst every 1.6 s with lifetimes up to 1.25 s, so the pulses
  read as ticks.
- **Teleports and blinks:** an implosion flash (31 to 0 over 0.23 s) with `Squash` glitch
  frames; upward streaks at 45-200 studs a second with Drag 4-9, dying in 0.12-0.4 s; a white
  ground ring growing from 1 to 19 in 0.14 s.

**Orb skeleton** (every layer at Speed 0.001, `LockedToPart`, `Rate` 2-4, Lifetime 0.5-1,
Transparency `0:1, 0.5:0, 1:1`, random `Rotation`; front to back; R = the orb's radius):

| ZOffset | Role | Make |
| --- | --- | --- |
| +0.4 | Black linework | A spiral or rune sheet, 1R, black |
| +0.3 | Hard ring | `LightEmission` 0, Brightness 20-150, 0.9R |
| +0.1 | Black pupil | A small disc pulsing 0.15-0.5R |
| 0 | Core | Rays and fill, `LightEmission` 1, Brightness 5-10, 0.45R, `RotSpeed` ±10-20 |
| -1 | Outer ring | `LightEmission` 1, Brightness 1-4, growing 0.9-1.5R |
| -1.05 | Halo | A soft blob, `LightEmission` 1, Brightness 0.3, 1.6R |
| -1.1 | Black backdrop | A soft black blob, 2R, and a black disc 0.6R behind the core |

Looping forms (`Rate` > 0) need an end: set `Enabled = false` before `Play` returns and let
`Linger` cover the last lifetime.
