---
name: roblox-vfx
description: Create Roblox visual effects (particles, beams, trails, flashes, lights, tweens, mesh effects, mesh debris) as effect modules for Oscar's VFXPlayer system, including generating and publishing any mesh assets the effect needs. Use this skill whenever the user asks for any visual effect, ability effect, hit effect, aura, projectile, explosion, slash, shockwave, debris, trail, glow, heal, dash, charge-up, or "make this look cooler" in Roblox, even if they don't say "VFX".
---

# Roblox VFX

Every effect is one ModuleScript at `src/shared/VFX/Effects/<EffectName>.luau` on disk,
which Rojo syncs to `ReplicatedStorage.Shared.VFX.Effects.<EffectName>`. It follows the
contract below and is played with `VFXPlayer.Play(name, cframe, overrides)` on the client.
Never write free-form VFX scripts, and never edit synced scripts inside Studio.

## Before you write anything

1. **Read `references/structure.md`.** It covers layout, the full contract and ctx API,
   naming, assets, engine gotchas, rules, testing and the new-effect checklist, and it is
   part of this skill.
2. **Pick the closest example** from the table below and read it. The examples show how
   to build each kind of effect (contract, layer construction, timing, cleanup). Take the
   numbers (sizes, timings, palette) from the references, not from another effect.
3. **Read the design references for the category:** `references/recipes.md` (its
   section), `references/design.md` (palette, value, brightness against bloom, layering,
   timing), plus the topic files the effect needs:

   | Effect has... | Read |
   |---|---|
   | fire, smoke, a blast | `references/explosions.md` |
   | travel, a swing, a trail, a beam, a held orb or aura | `references/motion.md` |
   | camera shake, lights, a crater, screen effects | `references/camera-world.md` |
   | a mesh shape (arc, ring, shard, rock, dome) | `references/meshes.md` |
   | textures to pick or draw | `references/textures.md`, `references/drawing-textures.md` |
   | this game's look | `references/style-guide.md` |

**Precedence.** Where the Roqer-derived references (`design.md`, `explosions.md`,
`motion.md`, `camera-world.md`, `drawing-textures.md`, `review.md`, the "Impact skeleton"
in `recipes.md`, the "Mesh effects" section of `meshes.md`) disagree with other guidance
here, follow Roqer. The contract and rules in `structure.md` are how our code runs, not
design guidance: when a design needs something they forbid, extend `VFXPlayer`/`ctx` first.

## Examples (`examples/`)

Each one is a complete, working effect module. Copy one into `src/shared/VFX/Effects/` to
play it. They show structure and technique; the design numbers come from the references.

| Example | Category | What it shows |
|---|---|---|
| `SlashImpact.luau` | Impact, one hit of many | The impact skeleton: flash, colour/black/white star stack, backing, claw + dim twin, streaks with black twins, flat ring, embers, light. `Layers.Timeline`. |
| `GroundSlam.luau` | Ground slam | Skeleton + shock-ring mesh that flattens and spins, swelling dust body, MeshParticles rocks, wind arcs, crater rocks in the floor's material, mesh template fallbacks. |
| `EnergyBolt.luau` | Projectile | Bezier flight driven per frame, head sprites cleared on hit, sharp + soft textured Trails (`Lifetime / ctx.TimeScale`), shed specks, launch smear, an impact timed from arrival. `Target` runtime override. |
| `CrescentSlash.luau` | Weapon swing | A crescent without a mesh: a pivot swept per frame with ribbons between inner/outer attachments (`FaceCamera = false`), tip sparks one burst per frame, ink flecks, `Roll` for diagonal cuts (keep the low end above the floor). |
| `DashBurst.luau` | Movement | Moved part with a core/wisp trail pair, speed lines shed backwards, flat wind ring, one-frame smear, warm/cool dust at both ends via `Layers.Ground`. |
| `ChargeAura.luau` | Held aura / charge-up | The orb skeleton as cross-fading looping emitters, inward motes from a Sphere-shaped part, breathing ground sigil, hold for `Duration` then stop emitting and release. How looping layers start and end. |
| `HealPulse.luau` | Buff / heal | Spiral motes from attachments moved along a helix, ground ring + glow, Disc-shaped sparkle emission, a `Highlight` on an optional `Character` override, repeated ticks. |
| `IceShards.luau` | Mesh eruption | Cloned shard templates with a `WedgePart` fallback, staggered Back-Out rises built into one Timeline, glints, shatter into MeshParticles (with a recoloured piece template), cold mist. |

Larger effects in `src/shared/VFX/Effects/` (read the closest one for a similar effect;
they are not copied here, so they never go stale): `ChromaticStrike` (spline volleys, star
heads, layered beam trails, screen vignette, `ctx.Shake`, time-sorted event list),
`LavaEruption` (fissure fire curtain, per-frame channel rates, SurfaceGui cracks),
`FireballExplosion` (boiling drawn fire bodies, burn-out, comets), `MagnetPull` (channelled
suction, implosion pulses, orb core), `WindSpinSlash` / `WindBladeTrail` /
`WindSpinSlashCombo` (phased flipbook vortex, weapon trail pair, a composite effect that
plays child effects).

## Effect contract

```luau
-- ModuleScript: ReplicatedStorage/Shared/VFX/Effects/<EffectName>
-- <What it looks like, one line.> Layers: <list>.

local VFX = script.Parent.Parent
local Layers = require(VFX:WaitForChild("Layers"))
local Textures = require(VFX:WaitForChild("Textures")) -- drawn textures, if used

-- Library ids from ReplicatedStorage.Assets.VFX. Comment = <Folder>/<CardName>.
local ASSETS = {
	SoftGlow = "rbxassetid://87365446017300", -- lava_glow (custom)
	Slash = { Id = "rbxassetid://13580352351", Grid = 4 }, -- FlipbookTextures/Glowing Slash
}

local Effect = {}

Effect.Defaults = { -- every tunable; PascalCase; number/boolean/string/Color3/Vector3 only
	Color = Color3.fromRGB(255, 170, 60),
	Scale = 1,
}

Effect.Linger = 0.8 -- effect seconds kept alive after Play returns; covers the longest life

function Effect.Play(ctx)
	local p = ctx.Params
	local att = Layers.Attachment(ctx.Anchor())
	local glow = Layers.Emitter(att, { Texture = ASSETS.SoftGlow, Lifetime = 0.2, Color = p.Color, Size = { { 0, 2 }, { 1, 0 } } })
	Layers.Timeline(ctx, {
		{ 0, function() ctx.Emit(glow, 1) end },
	})
end

return Effect
```

| `ctx` | Use |
|---|---|
| `CFrame` | Where it plays. LookVector points toward the viewer/attacker (or along the throw/dash). |
| `Params` | Defaults merged with overrides. Read every value from here. |
| `Folder` | Parent everything here; destroyed after `Linger`. Check `ctx.Folder.Parent` in loops (nil = cleared early). |
| `TimeScale` | This play's speed (harness slow-mo). Divide `Trail.Lifetime` by it. |
| `Anchor(cf?)` | Invisible anchored part in the folder, for attachments, emitters, lights. |
| `Emit(emitter, n)` | Burst particles. Never call `:Emit()` directly. |
| `Tween(inst, t, props, style?, dir?)` | Tween in effect time (default Quad Out). |
| `Wait(t)` | Yield in effect time. Returns the time that actually passed: add that to loop clocks. |
| `Shake(deg, t, opts?)` | Local camera shake, rotation only, distance-gated. |
| `Forge(template, cf?, opts?)` | Play a VFX Forge template as a layer (runtime only, see structure.md). |

**`Layers`** (`src/shared/VFX/Layers.luau`) builds everything from spec tables. Sequences are
given as `{ { t, v, env? } }`, ranges as `{ min, max }` and enums by name:
`Emitter(parent, spec)` (Rate 0, Speed 0, self-lit; `Flat = true` lies a sprite in the
attachment's plane; a `{ Id, Grid }` texture sets the flipbook), `Twin`, `Black` (ink twin
a step in front), `Dim`, `White`, `Emit(ctx, e, n, slow)`, `Attachment`, `Part`, `Quiet`,
`Light`, `Pop` (flash and fade a light while its range grows), `Apply` (spec onto any
instance, such as Trails), `Timeline(ctx, { { t, fn } })`, `Track`, `Ground` (raycast down,
skipping characters), `Frame` (ground frame, +X = viewer's right).
**`MeshParticles.Burst(ctx, template, count, config)`** simulates MeshParts as debris (config
in `references/properties.md`). **`Textures`** holds drawn sheets as `{ Id, Grid }`, with
library fallbacks until they're uploaded.

## Rules

1. Parent only under `ctx.Folder` (directly or via `ctx.Anchor`).
2. All timing goes through ctx. Never use `task.wait`, `wait`, `task.delay`, raw
   `TweenService` or `emitter:Emit`. `task.spawn` around a `ctx.Wait` loop is fine.
3. **A `Layers.Timeline` clock only advances between events.** Never block inside an event
   (a flight or sweep loop). Run the loop before or after the Timeline, or spawn it.
4. Burst emitters have `Rate = 0`. Looping emitters get `TimeScale = ctx.TimeScale` and
   `Enabled = false` before `Play` returns, and `Linger` covers their last lifetime.
5. Visible parts are anchored, with `CanCollide`, `CanQuery`, `CanTouch` and `CastShadow`
   false (`Layers.Part` / `Layers.Quiet`).
6. Mesh templates come from `ReplicatedStorage.Assets.Meshes` via `FindFirstChild`, with a
   plain-part fallback. No `WaitForChild` into Studio-only folders, and nothing at require
   time may yield or error.
7. Effects may require `Layers`, `Textures`, `MeshParticles` and sibling effects. They must
   never require `MeshFactory` or `VFXScrub` (edit-time tools), `ForgeBridge` or ForgeVFX
   (use `ctx.Forge`).
8. Runtime-only overrides (instances such as `Weapon`, `Character`, `Target`) are
   documented in the header and handled when nil. They are never put in `Defaults`.
9. Effects run on the client only. The server fires a remote with a name and a CFrame, and
   never waits on an effect.

## Design in one screen

The references hold the measured numbers. This is the short version.

- **Size for role and viewer.** A hit of many is 10-13 studs. A finisher or a projectile's
  payoff is 40-300 studs, seen from the player's camera.
- **Palette first.** About five colours: saturated energy, desaturated matter, and a
  complementary accent on 10% of layers at most.
- **Many layers, one sprite each.** A studied hit has 40-60 single-sprite layers, timed in
  place. One emitter alone always looks cheap.
- **Intensity only goes down.** Flash at 0 for 0.03-0.15 s. Other layers follow at +0.03 s
  in 0.025-0.05 s steps and die at different times. A finisher keeps growing in mass for
  0.25-1.35 s while its brightness falls.
- **Value contrast.** A near-white thin core, a saturated mid and dark edges. Darks come
  from black twins and backings.
- **Solid colour, additive highlights.** Colour layers use `LightEmission` 0.3 or less;
  additive is for thin highlights only, or the effect washes out to pastel. Use
  `LightInfluence = 0` on energy and most smoke.
- **Anything that moves carries its speed.** Use streaks, rings shed backwards and a smear
  at launch.
- **Meshes for crisp silhouettes, particles for softness.** It must still read at 40 studs.

**Seen in Studio previews of the examples** (each one was a real bug, now fixed):
- **The floor clips everything.** Particles, trails and tilted sweeps are depth-tested, so a
  flash bigger than its height above the ground or a rolled slash's low end gets cut off flat.
  Lift ground emitters ~0.5-1 stud and keep `OuterRadius * sin(Roll)` above the floor.
- **Mind the body.** Anything orbiting a character needs a radius outside an R15 torso
  (about 2.5 studs or more), or it is hidden inside it.
- **A trail must age within the move.** A trail that outlives the motion (0.3 s over a
  0.12 s dash) never shows its taper and reads as a solid plank. A fast shot's trail should
  be a few heads long, not reach back to the caster.
- **Low-Rate emitters start late.** A `Rate = 1` layer first appears a second in: `ctx.Emit`
  one particle when you enable it.
- **Overlapping additive sprites blow out to white.** Start dense additive layers on the hue,
  not on the hot colour.
- **Flat flipbooks laid over swept ribbons** read as stepped panels. Let the ribbons draw the
  crescent.

## Budget

- Texture particles: a few hundred per one-shot effect. Looping auras stay much leaner
  (they are on screen indefinitely).
- Emitters: 40-60 for a one-second hit. Every emitter is a draw call, and large overlapping
  transparent layers cost the most.
- Mesh particles: under ~60 per play and ~40 alive at once.
- Meshes: under ~1000 triangles each.
- Lights: one PointLight per hue, popped and faded, with Range capped at 60.
- Expose counts and rates in `Defaults`, so replicated or low-quality plays can pass lower
  ones. Pool effects that fire constantly.
- When over budget, cut the least visible layer first.

## Workflow

1. **Classify** the effect (impact, slash, projectile, aura, explosion, movement,
   buff/heal, ambient) and its role, then read what "Before you write anything" lists.
2. **Textures.** Draw your own when the shape matters (`references/drawing-textures.md`,
   `tools/vfx/vfxtex.py`, checked with `tools/vfx/flipbook.mjs`). Otherwise use a library
   texture from `references/textures.md`. Built-in `rbxasset://` textures are for blocking
   out only.
3. **Meshes.** Reuse a template or make one with MeshFactory (`references/meshes.md`). For
   Forge-authored layers, use `ctx.Forge`.
4. **Write the module** from the contract and the closest example, with every tunable in
   `Defaults`.
5. **Test before Studio:** `node tools/luau-test/run.mjs <Name>` (needs the `luau` CLI;
   `--examples` also runs this folder's examples). Then run the rules grep from the
   checklist in `structure.md`.
6. **Look at it:** use VFXHarness in Play mode at 1x and 0.1x, and from about 40 studs. Use
   VFXScrub frames in Edit mode. Judge the captures with `references/review.md`, close up
   and from the player's camera, with the colour check (`tools/vfx/clip.mjs tone`). To
   match a reference video, follow "Matching a reference video" in `structure.md`.
7. **Report** in 2-3 sentences: the layers, which Defaults to tweak first, and any meshes
   or textures you published.

## Reference files

- `references/structure.md`: layout, contract, ctx API, naming, assets, engine gotchas,
  rules, testing, checklist, open issues.
- `references/recipes.md`: layer breakdowns and timings per category, plus Oscar's
  corrections.
- `references/design.md`: palette, value, brightness and bloom, layers, timing and motion
  numbers.
- `references/explosions.md`: fire bodies, burn-out, smoke.
- `references/motion.md`: projectiles, volleys, slashes, dashes, beams, trails, orbs,
  auras.
- `references/camera-world.md`: FOV, blur, impact frames, shake, lights, craters.
- `references/properties.md`: key properties, starting values, MeshParticles config.
- `references/textures.md`: library and uploaded textures, and how to make new ones.
- `references/drawing-textures.md`: drawing, checking and uploading textures and flipbooks.
- `references/meshes.md`: reusing, generating, previewing and publishing meshes, and mesh
  effects.
- `references/review.md`: how to judge a capture.
- `references/style-guide.md`: this game's look (template, not filled yet).
- `scripts/agy_grade.sh`: Gemini grading against reference frames.
- `tools/vfx/` (repo root): `clip.mjs`, `flipbook.mjs`, `vfxtex.py` (AGPL-3.0, ported from
  Roqer, https://github.com/S4US/Roqer).
