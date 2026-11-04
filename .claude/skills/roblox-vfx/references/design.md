# VFX design

What experienced Roblox VFX artists do and why: what the effect is for, colour, value and
brightness, layers, timing and motion. Read it with `recipes.md` before designing an effect.
Where it disagrees with other files in this skill (including `style-guide.md` and the
"Oscar's corrections" list in `recipes.md`), follow this file (`SKILL.md`, Precedence). It
is a set of observations, not a style: depart from it when the effect calls for it.

Adapted from Roqer's VFX skill (https://github.com/S4US/Roqer, `roblox-animation-vfx`
references `vfx-design.md` and `vfx-craft.md`, AGPL-3.0-or-later), rewritten for our
`ctx` / `VFXPlayer` contract.

How far to trust a number:
- *(measured)*: from Roqer's studies of published effects by experienced Roblox VFX artists:
  49 effects (5,010 particle emitters and 1,215 of their textures), their videos, a
  hand-drawn texture set, a 1,108-texture community kit and a tutorial by the artist snaliel.
- *(verified)*: checked in Studio by Roqer's authors. Where an engine gotcha in
  `structure.md` disagrees, follow this file.
- *(starting point)*: common practice; tune it by looking.

In our modules a Roqer "EmitDelay" is a `ctx.Wait` (or a `task.spawn` + `ctx.Wait` branch)
before the layer, and "EmitCount" is the `n` in `ctx.Emit(emitter, n)`.

## 1. Start from what the effect is

- **Name the move before drawing anything:** a frequent basic skill, an ultimate, a summon,
  a buff, a pickup, an aura, a showcase piece. Its role sets its scale *(measured)*:
  - **A basic skill** with a one-second cooldown (a water barrage) is small, one hue and
    short. Its hits last about 1 s and are cleaned up by 3 s.
  - **An ultimate** is staged. It roots the caster for seconds, charges, uses camera and
    screen work (`camera-world.md`), and leaves craters and scorch marks.
- **Size the payoff for where the player sees it.** A projectile's impact lands at the end of
  its range, so a 40-stud throw is watched from about 50 studs. At 50 studs a 16:9 screen at
  the default field of view is about 125 studs wide. In 26 studied impacts the largest layer
  is usually a flash, a flare or a shockwave that reaches its size for a fraction of a second
  while it fades *(measured)*:
  - **One hit of many** (a barrage, an arrow rain, a missile salvo): 10-13 studs. Most peak
    at once and halve within 0.1-0.25 s.
  - **One projectile that is the whole skill** (a fireball, a star, a beam's end): 70-360
    studs. A meteor slam's smoke grows to 237.
  - **A skill's finishing explosion:** 40-275 studs. Seven of nine explosions and slams kept
    growing for 0.25-1.35 s after the hit (section 6).

  The solid bodies are smaller: a practice explosion's crescents grow to 19 studs, and a
  fireball skill's crescents and lightning to 125.

  A charge reads easily: it is near the camera, against the caster's dark body, and moving
  inward. An impact has the opposite problem: far away, on a bright floor, spreading flat.
  Give it the size, brightness and height to make up for that. In a test, an ice spear's
  13-stud shatter was a speck from the caster's camera; at 2.5 times the size, with its hot
  layers at Brightness 12-60, it read as a burst *(verified)*, though still as a splash rather
  than an eruption: size and brightness are not the whole fix.
- **Borrow the rhythm and silhouette of a reference, not its colour.** The studied fan pieces
  (Gojo's Reversal Red, a Kamehameha, Ayato's sword kit) keep their move's beats, shape and
  scale, and may change colour: the Ayato piece is amber, not Hydro blue.
- **Decide the dominant shape.** A wide spiral on the ground reads instantly as an area
  attack, a vertical column as a pillar, a forward cone as a directed blast. An impact that
  stays flat (a ring, a patch, a low splash) shrinks to a smear on the floor from the caster's
  camera. The studied explosions throw something up as well: flame tongues, crystal spires, a
  smoke column or rising debris.
- **Ask for the game's style** when it is not clear (`style-guide.md`). An effect that fits
  the game beats a busy one.

## 2. Colour

**Pick a palette before anything else** *(measured: the tutorial)*:
- Choose about five colours. Use them on every part, emitter, beam and decal, and put them
  in `Defaults` (`Color`, `CoreColor`, `RimColor`...).
- Add nothing outside them. One orange spark in a purple effect reads as a mistake, even to
  a viewer who cannot say why.
- Colour is seen before timing or shape. It decides whether a move reads as hot or cold,
  physical or magical, and whose it is.

**How the palettes are built** *(measured)*:
- **One hue is common** for elemental skills: water `#7ba5ff`, heal `#40ff40`, fire
  `#ff3c22`, rust `#aa4923`. Value comes from Brightness, LightEmission and a dark stop in the
  gradient. A screen tint can add the saturation the particles hold back.
- **Two analogous hues** about 45-50 degrees apart (lime with gold, peach with magenta). Two
  ways to use them: twin each layer, one copy per hue, 0.01 apart in `ZOffset`; or run a
  gradient through the second hue over a twin held at the first (`#5e76ff` to `#ff55ff` and
  back).
- **A complementary accent** stays small: about 10% of layers (purple lightning in orange
  fire, blue rings around an orange beam). A full complementary clash (orange against cobalt)
  is kept for impacts, with a black layer between the two.
- **Saturated energy, desaturated matter.** Energy (rings, flames, beams) is saturated.
  Debris, rocks, dust and smoke are grey or low-saturation. The contrast sells weight: pure
  energy feels weightless, and debris without energy feels like an accident. Pair the two.

**Gradients carry value as well as hue** *(measured)*:
- A layer can run light and warm, then saturated, then dark, then nearly black over its
  life: `#ffcb47` to `#71ff54` at 0.24, `#143b16` at 0.45 and `#031107`.
- At `LightEmission` 0 the dark tail renders as solid dark shapes, so the effect gets its
  darks without a separate black layer. It suits a sheet that has broken into fragments by
  then, as 82% of the studied ones have. On a whole puff it is a black blob.
- Fire mostly stays in its hue and deepens to red (87% of 1,391 fire layers), and may start
  blue or violet for the first 10-25% of life.
- `#2b190c` at Brightness 15-65 is a glowing brown, not black: read a colour as
  Color x Brightness.

**Smoke and white:**
- **Smoke beside fire takes the fire's colour** where the fire lights it: a `Color`
  sequence through the fire's orange (grey, `#ff5500`, grey), or a puff with its colours
  baked in. One flat dark tone reads as a cut-out.
- **Smoke away from fire** comes in warm and grey pairs. Most studied smoke is self-lit,
  mid-grey and about half transparent; dark smoke is a faint veil, never a dense black puff
  (`explosions.md`).
- **White is kept** for thin shapes: rings, flares, winds, crescents and the hottest core
  (section 3).
- **Lights take the palette too.** One PointLight per hue tints the character in both
  colours of a two-hue effect.

## 3. Value

The bright parts read only against something darker *(measured)*. Ways the studied artists
get it:
- **Black layers:** 7% of all emitters in the first study, 10-35% in value-focused pieces.
  - **Backing:** behind the colour (`ZOffset` -1 to -3), 1.1-4.5 times its size.
  - **Accents:** in front and smaller: ink lines, a dark pupil, cuts through a crescent.
  - **Black twins** *(measured: 56 pairs)*: a copy of the coloured emitter made black
    (`Color` black, or `Brightness` 0-0.01).
    - Most keep its texture, size curve, lifetime, `Rotation` range and timing exactly (45-51
      of the 56), at the same `ZOffset` or a step in front.
    - Where they differ, the black one moves differently (its own `Acceleration`, `Speed` or
      count), so it breaks the bright shape up instead of muting it.
    - None was both smaller than its colour and behind it. Shrunk, set behind and fired later,
      the black copy of a crescent burst read as separate dark brush strokes floating in the
      effect *(verified)*.
    - **The same settings do not give the same angle.** Each particle draws its own angle from
      the `Rotation` range, so a dark copy of a lopsided shape (a crescent, a slash, a blade)
      lines up with its bright one only when both lock `Rotation` to one value and share
      `RotSpeed`. With a random range it shows as a dark crescent of its own *(verified)*. A
      random range suits a shape that looks alike at any angle, such as a round burst.
- **Black without black:**
  - a white sprite at Brightness 0-0.01;
  - a dim twin of the same hue at Brightness 0.05-0.6, one `ZOffset` step behind a
    Brightness 3-6 copy, living a tenth to a fifth longer; its angle follows the black twin's
    rule above. Much longer and it is left alone on screen: a dim crescent copy that lasted
    2.6 times as long as the bright one hung in the sky as dull arcs after the colour had gone
    *(verified)*;
  - the dark tail of a gradient (section 2).
- **Stacked copies for an inner gradient.** Three copies of one flame sheet, each a little
  wider and longer-lived than the one above it, give a core-to-halo value step inside flat
  shapes:

  | Copy | Brightness | ZOffset | Squash | Lifetime |
  | --- | --- | --- | --- | --- |
  | Top | 5 | 0 | 0.3 | 0.6 |
  | Middle | 2 | -0.1 | 0.2 | 0.7 |
  | Back | 1 | -0.2 | 0.1 | 0.8 |

- **Glow that cools.** One copy at `LightEmission` 1 that dies first, and one at 0 that lives
  longer, so sparks cool from glow to solid.
- **A white base under additive colour.** Semi-transparent white smoke at `LightEmission` 0
  (Transparency 0.6-0.95) under coloured additive smoke keeps the core readable on a bright
  sky.
- **Inverted value for dark energy.** A black beam core (width 2-4, `ZOffset` +1) in front of
  a white additive halo (width 12, Transparency 0.5), with black and white twins of the same
  particles. The only colour is one accent.
- **The three-value stack on impacts:** colour at `ZOffset` z, its black twin at z or
  z + 0.25, white at z + 1, all short-lived.
- **White is a thin shape, not a fill.** The short-lived pure-white layers are rings,
  crescents, winds and spiky stars, at Brightness 1-2 *(measured: 67 layers)*. The hot centre
  comes from a coloured layer at high Brightness. A filled white disc, or several bright layers
  stacked over the core, is a white blob that hides the shapes: additive layers add up, so
  three overlapping glows go white.
- **Pickups and icons.** A near-black disc (Brightness 0.01) framed by a bright ring keeps an
  icon readable on any background. Glow, rays and fire around it carry the colour code.

How black renders *(verified)*:

| Setting | Result |
| --- | --- |
| `LightEmission` 0 | Solid ink |
| `LightEmission` 0.55 | A faint dark veil |
| `LightEmission` 1 | Invisible |

## 4. Brightness and blending

`Brightness` multiplies `Color`. In the first study the median Brightness was 9 and a quarter
were above 25; in the second, most layers sat at 3-10 *(measured)*. Those medians include
trails, auras and smoke. In the hit itself the hottest layer runs higher: Brightness 15 at the
median of 26 impacts, and 50 or more in a third of them *(measured)*.

The difference is the place's bloom:
- The first study's places had Bloom Threshold 2, as a new place does.
- The second study's ran Threshold 1 to 2 and Intensity 1 to 1.5. At Threshold 1,
  Brightness 5 already blooms.
- **Read the place's `Lighting.Bloom` (BloomEffect) before choosing Brightness**, and note it
  in `style-guide.md`.

How one orange shape renders under a new place's lighting *(verified)*:

| Setting | Over a dark background | Over a bright background |
| --- | --- | --- |
| `LightEmission` 0, Brightness 1 | Flat orange | Flat orange |
| `LightEmission` 0, Brightness 5-25 | Hot yellow-orange, blooming | Pale, toward white |
| `LightEmission` 0, Brightness 150 | White-hot core | White |
| `LightEmission` 1 (additive), Brightness 1 | Lighter, pale | Washes out, nearly gone |
| `LightEmission` 1 (additive), Brightness 5 | White glow | White glow |
| `LightEmission` -1 to -3 | Saturated, solid | Saturated, solid, with a dark rim |

- **Hard cel shapes:** `LightEmission` 0 or negative with Brightness 5-55. Fire bodies sit
  near Brightness 5 at `LightEmission` 0-0.5; two studied pieces push them to 25-100 at -1 to
  -5.
- **Glows and halos:** `LightEmission` 1 at Brightness 1-6, often below 1. Soft ones are about
  two-thirds transparent: the sharp shapes carry the brightness (median 4), the glow only
  blooms around them. Four-point flares run at 5-12 *(measured)*.
- **Colour in daylight is solid.** Additive layers only lighten what is behind them: over a
  bright sky violet goes pastel, then white. 58% of studied saturated layers are solid
  (`LightEmission` 0.3 or less); additive is for thin highlights and small glows. A mostly
  additive magic effect came back 74-85% pale; studied videos are 2-21% *(measured)*. Check
  with `node tools/vfx/clip.mjs tone` (`structure.md`, testing).
- **Glow-first** (`LightEmission` 1 on most layers, one studied artist's style) works in a
  dark scene.
- **The white-hot core:** one or two front layers at Brightness 50-150, with a shape (spikes,
  a star or a ring), lasting 0.03-0.1 s.
- **Neon mesh flashes** run hotter: Brightness 78 falling to 27 by 7% of life, with the colour
  going white to black as the ring expands *(measured)*.
- **A Decal's `Color3` above 1** is overbright and blooms *(verified)*: `Color3.new(4, 6, 8)`.
  Artists use 2-20 on shockwave and slash decals. **A glowing crack that cools:** a decal at
  `Color3` around 10, tweened to black over about 1.3 s.

Brightness numbers are relative to the place's bloom and background: read the Bloom, follow
the numbers above, and confirm them in captures with the colour check.

## 5. Layers and orientation

- **Many layers, usually one sprite each** *(measured)*: one hit in the studied slashes has
  40-60 distinct layers; a small orb is 17 layers on one attachment; the median burst is 1
  particle, and 37% of emitters have Speed near 0: sprites stacked and timed in place. 20 of
  48 files add glowing meshes too (`meshes.md`). Most of an effect's emitters
  can share a few attachments.
- **Big counts are for scatter:** sparks, droplets, debris and dots at 10-160 a burst.
  Sustained beams and trails use `Rate` 15-2000.

| Orientation | Used for | Share in the first study |
| --- | --- | --- |
| `FacingCamera` | Puffs, glows, flares, impact stars | 40% |
| `VelocityPerpendicular` | Flat rings, sigils, crescents in a fixed plane, ground marks | 34% |
| `VelocityParallel` | Streaks: sparks, flame tongues, speed lines, debris | 23% |
| `FacingCameraWorldUp` | Rising columns, upright specs | 3% |

- **A flat sprite needs a direction.** `VelocityPerpendicular` lays a sprite across its
  direction of travel, so give it a tiny `Speed` (0.001; we use ~0.01). At Speed 0 it does not
  show at all *(verified)*. Aim a flat crescent with `Rotation` and sweep it with `RotSpeed`.
- **Streaks:** `VelocityParallel` with `Squash` (often ramped, up to ±3, or -18 for extreme
  lines) and `Rotation` -90, so the texture's long axis follows the motion.
- **Which way a `VelocityParallel` sprite points** *(verified, from both sides)*: at
  `Rotation` -90 the image's top leads the motion, at 90 its bottom leads, and at 0 the image
  lies across the motion. A lance or shard drawn point up takes -90; at 0 a volley of them
  flies sideways, like fins. It follows the particle's own velocity, not the part's: at
  `Speed` 0 it has none, and heads emitted that way stood upright whichever way they flew.
- **Mirrored pairs:** two copies at `Rotation` -90 and +90 make symmetric wings.
- **`ZOffset`** moves a layer toward the camera without changing its size. Scale it with the
  effect: about ±1 for a 10-stud orb, 0-3 for an impact, tens of studs for a huge explosion
  *(measured)*.

## 6. Timing: the intensity curve

From the tutorial *(measured)*:
- **Fire once, die at different times.** An effect is usually one burst in which the elements
  have different lifetimes. The order in which they disappear creates the feeling of
  progression.
- **Intensity only goes down.** It peaks at the hit and only falls. Place key poses along
  that line, each readable and each less intense than the last:
  1. the big flashy energy, with wind;
  2. the scatter: debris, shards and energy fragments moving outward, the flash gone;
  3. the residue: dust settling, a faint glow, the last smoke.

  Nothing in the middle or at the end gets brighter again.

  **Brightness falls, but an explosion's mass can still grow.** Measured as the screen area
  of every live particle, seven of nine explosions and slams kept growing for 0.25-1.35 s
  after the hit: the flash dies while flames, spires, smoke and debris swell, rise and spread.
  Only the small hits peak at once *(measured)*. A finisher that is biggest at its flash and
  then only shrinks reads as a pop, not an explosion.

  **The mass comes from body layers that outlive the flash.** In the studied explosions,
  crescents, flame tongues and puffs carry the effect from 0.1 to 0.6 s, as flipbooks, never
  one image scaling *(measured)*: a practice explosion's crescents grow from 2 to 19 studs
  over 0.36-0.55 s and its smoke holds 20 studs for 0.6-1.2 s; a fireball skill's crescents
  grow to 125 studs over 0.35-0.55 s. Shards, sparks and glints are accents, not mass: an ice
  shatter whose body layers died by 0.2 s became 40 shards of 2 studs by 0.25 s, and read as a
  sparkler from the caster's camera *(verified)*.
- **Stagger cause and effect.** Nothing fires at the same time. In the tutorial the wall
  launches, then the dragon appears 0.4 s later, then the hit, then the cracks, then the
  debris. Simultaneous layers read as noise.
- **Shockwave rings are the cheapest strong trick:** a thin flat Neon disc mesh that grows
  from small to massive in 0.2 s while its Transparency goes from 0 to 1.

Typical lifetimes *(measured)*:

| Layer | Lifetime |
| --- | --- |
| Flash, impact frames | 0.03-0.15 s |
| Crescents and slashes | 0.15-0.4 s |
| An explosion's body (crescents, tongues, puffs) | 0.35-1.2 s |
| Rings and debris | 0.4-1.4 s |
| Smoke | 0.5-1.5 s in a hit; 3-7 s for a slam's last cloud |
| Ground marks | 1-3 s, scorch up to 6 s |

**Before the hit:**
- **Anticipation:** 0.1-0.6 s before the hit, up to 1.35 s for a bigger move. Energy gathers
  inward: converging trails from a 16-stud circle over 0.5 s; particles at negative Speed or
  `ShapeInOut` Inward; an implosion (a spiky ring shrinking from 11 to 0 in 0.15-0.2 s, once or
  twice); or a tiny charge that then releases about ten times bigger.
- **Fire the hit slightly early.** Projectiles trigger their impact 0.01-0.1 s before arrival,
  and accelerate into it (Quad In).

**The hit:**
- **Layer order:** the flash at 0, everything else at +0.03 s or later, in steps 0.025-0.05 s
  apart.
- **The flash itself** is a growing sprite, a shrinking one (7 to 0 in 0.1 s), and a thin
  squashed flare line (`Squash` -2 to -5, 0.04-0.12 s). In its frames it is the biggest thing
  on screen, larger than the burst that follows. Its body is a filled spiky shape covering
  most of its cell, solid at the centre (`drawing-textures.md`); the thin flare is an
  addition. A thin four-ray flare used as the whole flash shows as two white beams in a V once
  it is rotated *(verified)*.
- **A held contact point** (a beam hitting a wall) strobes its flash: Lifetime 0.1 at Rate 50.

**After the hit:**
- **Hit, hold, hit bigger.** A second hit about 1.4 s after the first, scaled 1.6-1.8 times in
  size and speed, with a camera punch. A held aura bridges the gap.
- **Lingering layers run slower:** emitter `TimeScale` 0.6-0.95 on smoke and wind while the
  core stays at 1. `ctx.Emit` sets `emitter.TimeScale` to the play's time scale, so multiply
  after it: `ctx.Emit(smoke, 5); smoke.TimeScale *= 0.75` (check the result in VFXScrub; this
  is not yet used in our effects).
- **A linger can grow about 20%** over 2 s while it fades.
- **Combos:** duplicate a whole impact, move and rotate each copy, and stagger the copies
  0.1-0.15 s apart.
- **Tie it to the animation.** Without markers, keep one table of delays in `Defaults`, and
  make the last event match the clip's length (`WindSword` keeps its timings in
  `src/shared/WindSword/init.luau`).

## 7. Motion and curves

- **Burst, then hang.** High `Speed` with strong `Drag` so pieces shoot out and stop: Speed
  45-75 at Drag 16; 25-60 at Drag 6; streaks at 1000-2000 lasting 0.1-0.2 s. `Drag` is the
  half-life of speed in seconds. Constant slow drift reads as floaty. Light bits fall at an
  `Acceleration` of -15 to -27, rocks at -60 to -200.
- **Size pops.** `0:0, 0.1:peak, 1:0` for debris. A flash starts big and shrinks. Rings grow on
  an ease-out. A one-frame `Squash` pop at spawn (2 to 0 by 2% of life) gives an orb a snap.
- **Each particle its own size.** 51% of studied emitters, in 37 of 39 files, give their Size
  keys an envelope, a random ± per particle, a median third of the peak *(measured)*:
  `NumberSequenceKeypoint.new(0.1, 6, 2)` spreads 4-8. Without one, a layer's particles match
  in size at every age, which looks machine-made.
- **Hold, then snap.** Transparency held at 0 for the first 27-30% of life, then snapping to
  0.8 by about 36%. For held sprites: 1 to 0 by 20% of life, held to 80%, then back to 1.
- **Transparency keys above 1** make a particle vanish before its lifetime ends *(verified)*.
  Negative Transparency does not make a soft texture solid *(verified)*.
- **Glitch frames:** flip `Squash` from +3 to -3 partway through a short flash.
