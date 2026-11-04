# Setting up and running effects

How the VFX runtime is installed, how an effect module is shaped, the rules it follows, the
engine behaviour it has to work around, and how to test it. Design guidance (layers, values,
timing) is in `SKILL.md` and the other references. Paths like `runtime/...` and `tools/...`
are relative to this skill's folder (`<skill>`).

## Installing the runtime

Effects run on a small client-side runtime in `<skill>/runtime/VFX/`. If the project already
has an equivalent (a VFXPlayer-style module that builds a `ctx`), use that and adapt the
contract below to it instead.

| Module | Use |
|---|---|
| `VFXPlayer` | Plays effects by name on the client and builds their `ctx` |
| `Layers` | Builds emitters, twins, lights, parts and timelines from compact spec tables |
| `MeshParticles` | Simulates MeshParts as debris on the client |
| `VFXShake` | Camera shake behind `ctx.Shake` |
| `MeshFactory` | Edit-time only: generates and publishes mesh assets (`meshes.md`) |
| `VFXScrub` | Edit-time only: plays an effect and freezes it at an exact time for screenshots |
| `VFXCamera` | Testing only: locks the camera on an effect from fixed angles (`review.md`) |
| `Effects/` | One ModuleScript per effect (empty to start) |

Put the folder where client code can require it, conventionally `ReplicatedStorage.VFX`
(with `VFXPlayer`, `Layers`, ... and `Effects` as its children):
- **Rojo / file sync:** copy `runtime/VFX/` into the synced source tree (e.g.
  `src/shared/VFX/`); each `.luau` file becomes a ModuleScript. Edit files on disk only, and
  keep Studio-only content (mesh templates, art libraries) out of folders the sync owns, or
  it deletes them.
- **Studio only:** create a Folder `VFX` in ReplicatedStorage with a ModuleScript per file
  (same names, each file's source pasted in) and a Folder `Effects`. With the Studio MCP,
  create them with `execute_luau` (`Instance.new("ModuleScript")`, set `.Source`).
- **Test bench:** `runtime/VFXHarness.client.luau` is an optional LocalScript for
  `StarterPlayerScripts` that plays effects with number keys at a target in front of you
  (Studio only). Adjust its `VFX_FOLDER` if the runtime lives elsewhere.

This skill's paths say `ReplicatedStorage.VFX`; substitute wherever you installed it. Effects
find their siblings with `script.Parent.Parent`, so they work anywhere.

## Runtime flow

```luau
local VFXPlayer = require(game:GetService("ReplicatedStorage").VFX.VFXPlayer)
VFXPlayer.Play("SlashImpact", hitCFrame, { Color = Color3.fromRGB(120, 200, 255) })
```

`Play(name, cframe, overrides)` requires `Effects.<name>` once (cached), merges `Defaults`
with `overrides` into `ctx.Params`, and runs `Effect.Play(ctx)` in a new thread. Errors are
caught and warned (`VFXPlayer: effect '<name>' errored`). When `Play` returns, it waits
`Linger` (effect time) and destroys `ctx.Folder`. `VFXPlayer.TimeScale` is read once per
play; `VFXPlayer.Clear()` removes everything. Call it from the client only.

Server-triggered effects need a RemoteEvent: the server decides that something happened and
fires the effect's name and a CFrame; each client plays it. Prefer an `UnreliableRemoteEvent`
for pure presentation: it drops payloads over 1000 bytes, so send names and numbers, never
instances. Never let damage or rewards wait on an effect. To time an effect to an animation,
play it from the track's `GetMarkerReachedSignal("<Marker>")` on the hit keyframe rather than
a fixed delay.

**Instance overrides.** Overrides can carry instances (a weapon part, a character), which
can't be `Defaults` (attributes): `VFXPlayer.Play("HealPulse", root.CFrame, { Character = char })`.
Document such runtime-only keys in the effect's header and always handle them being nil.

**Composite effects.** An effect may require sibling effects and call their `Play` with a
child ctx: `setmetatable({ Params = params }, { __index = ctx })` shares the folder, clock and
helpers. Set `Linger` to the max of the children's. In a real game prefer firing the parts
from animation events (windup start, hit frame) so they stay in sync with the animation.

## Effect module contract

Order: header, requires, `ASSETS`, constants, local helpers, `Effect`, `Defaults`, `Linger`,
`Play`, `return`.

```luau
-- ModuleScript: ReplicatedStorage/VFX/Effects/<EffectName>
-- <What it looks like, one line.> Layers: <core>, <shape>, <secondary>, <residue>.

local VFX = script.Parent.Parent
local Layers = require(VFX:WaitForChild("Layers"))
local MeshParticles = require(VFX:WaitForChild("MeshParticles")) -- only if used

-- Texture/mesh ids. Comment = where it came from and what it is.
local ASSETS = {
	CoreGlow = "rbxassetid://0", -- <source>: soft round glow
	WindSheet = { Id = "rbxassetid://0", Grid = 4 }, -- <source>: wind flipbook (cell 256 -> Grid4x4)
	SwirlMesh = { MeshId = "rbxassetid://0", TextureId = "rbxassetid://0", Scale = Vector3.one },
}

local Effect = {}

Effect.Defaults = {
	Color = Color3.fromRGB(255, 170, 60),
	Scale = 1,
	-- every tunable value: PascalCase keys, attribute-safe types only
}

Effect.Linger = 0.8 -- effect seconds kept alive after Play returns

function Effect.Play(ctx)
	local p = ctx.Params
	local att = Layers.Attachment(ctx.Anchor())
	local stars = Layers.Emitter(att, { -- one sprite per layer, a spec table per emitter
		Texture = ASSETS.CoreGlow,
		Lifetime = { 0.1, 0.15 },
		LightEmission = -1,
		Brightness = 5,
		Color = p.Color,
		Size = { { 0, 4 }, { 0.25, 8, 1.5 }, { 1, 9 } },
	})
	local black = Layers.Black(stars) -- its black twin, a step in front
	Layers.Timeline(ctx, { -- layers fire in steps, in effect time
		{ 0.03, function()
			ctx.Emit(stars, 3)
			ctx.Emit(black, 3)
		end },
	})
end

return Effect
```

The module's top level must not yield on or error over anything Studio-only: a harness may
require every effect at startup, and one bad module stops it.

## ctx API

| Field | Type | Use |
|---|---|---|
| `ctx.CFrame` | CFrame | Where to play. LookVector points toward the viewer/attacker. |
| `ctx.Params` | table | `Defaults` merged with overrides. Always read values from here. |
| `ctx.Folder` | Folder | Parent everything here (`Workspace.ActiveVFX.<Name>`). Auto-destroyed. |
| `ctx.TimeScale` | number | Playback speed for this play (slow-mo). Read-only. |
| `ctx.Anchor(cf?)` | -> Part | Invisible anchored part in `ctx.Folder` (default `ctx.CFrame`) for attachments, emitters, lights. |
| `ctx.Emit(emitter, n)` | | Burst `n` particles; sets `emitter.TimeScale`. Use instead of `:Emit()`. |
| `ctx.Tween(inst, t, props, style?, dir?)` | -> Tween | Tween in effect time. Default `Quad` / `Out`. |
| `ctx.Wait(t)` | -> number | Yield in effect time. Returns the effect time that actually passed (often more than `t`: a 1/60 wait usually takes 1-2 frames). Per-frame loops add the return value, not `t`, to their clock. |
| `ctx.Shake(magnitude, duration, options?)` | | Shake the local camera: rotation only, `magnitude` in degrees, `duration` in effect seconds, distance-gated (`options.Range`, default 250 studs from `options.Position` or the effect). `options`: `Roughness`, `FadeIn`. `VFXPlayer.Clear` stops it, `VFXScrub` skips it. Pass a `Shake = false` override for effects replicated from other players. |

`MeshParticles.Burst(ctx, template, count, config)`: non-blocking mesh debris; config in
`properties.md`. The `Layers` helpers are summarised in `SKILL.md` (full list in the header
of `runtime/VFX/Layers.luau`).

## Naming

- **Effects:** PascalCase, describing what it looks like or does: `CrescentSlash`,
  `GroundSlam`, `SlashImpact`. Not the owner (`RangerUlt`) and no versions (`SlashV2`).
  File name = module name = the name passed to `VFXPlayer.Play`.
- **Locals and helpers:** camelCase verbs for functions (`makeBurstEmitter`, `spawnRing`),
  camelCase nouns for values (`ringTemplate`). Module constants: UPPER_SNAKE (`ASSETS`,
  `RING_SEGMENTS`); keys inside `ASSETS` are PascalCase.
- **Defaults keys:** PascalCase, noun first: `RingSize`, `RingTime`, `SparkCount`,
  `SparkSpeed`, `RockColor`. Suffixes: `Count` (integer), `Time` (effect seconds), `Speed`
  (studs/s; `SpinSpeed`/`RotSpeed` are degrees/s, matching the engine and MeshParticles),
  `Size` (studs), `Color` (Color3). Always include `Color` and `Scale`.
- **Defaults types:** number, boolean, string, Color3, Vector3 only (so they can be shown
  and tuned as attributes). Build NumberRange /
  NumberSequence / ColorSequence / Enum values inside `Play` from scalars
  (`NumberRange.new(p.SparkSpeed * 0.6, p.SparkSpeed)`).
- **Mesh templates:** PascalCase shape names (`CrescentThin170`), per `meshes.md`.
- **Instances in ctx.Folder:** optional PascalCase names (`Flash`, `Ring`) for debugging.

## Assets

**Copy ids into the effect.** Put every texture and mesh id in the `ASSETS` table at the top
of the effect, with a comment saying where it came from and what it is, so it can be found
again. An asset id never changes, and the effect file stays self-contained and reviewable.
Never `WaitForChild` into a Studio-only art folder from an effect, and never read library
"cards" at runtime.

**Flipbooks:** grid = sheet size / cell size (1024 sheet: 512 -> `Grid2x2`, 256 ->
`Grid4x4`, 128 -> `Grid8x8`). Note the grid in the `ASSETS` comment.

**FileMesh library meshes** (`SpecialMesh`): rebuild as Part + `SpecialMesh` from the ids. A
FileMesh is sized by `SpecialMesh.Scale`, not `Part.Size`: tween `mesh.Scale`, and note that
`MeshParticles.Burst` size curves do nothing on these parts (it sets `Part.Size`;
Transparency still works). For shrinking debris, use MeshFactory MeshPart templates.

**MeshFactory templates** live in `ReplicatedStorage.Assets.Meshes` (Studio-only). Look them
up without yielding and keep a plain-Part fallback (pattern in `examples/GroundSlam.luau` and
`examples/IceShards.luau`):

```luau
local meshRoot = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
local meshFolder = meshRoot and meshRoot:FindFirstChild("Meshes")
```

## Layering and timing (summary; details in the skill docs)

- Many single-sprite layers (40-60 in a studied hit), stacked and timed in place; the
  impact skeleton and category breakdowns are in `recipes.md`, the numbers in `design.md`.
- The flash at 0 (0.03-0.15 s), every other layer at +0.03 s or later in 0.025-0.05 s steps;
  intensity only falls after that. Expansion easing: `Quad` or `Exponential` Out
  (`Enum.EasingStyle.Expo` does not exist).
- Typical durations: slash 0.2-0.4 s, impact 0.3-0.6 s, movement 0.3-0.5 s, ground slam
  0.6-1.2 s, buff 0.6-1.2 s, explosion 0.8-1.5 s.
- Sequence layers with `ctx.Wait` or `Layers.Timeline`. For a parallel timeline use
  `task.spawn(function() ctx.Wait(t) ... end)`, never `task.delay` (real time). `Play`
  should return around the last layer's peak; `Linger` covers whatever is still fading.

## Engine gotchas (verified in Studio)

- `ParticleEmitter.Size` is a **half-width**: `Size = 5` draws a 10x10-stud quad.
- A `Beam` samples its `Transparency` (and `Color`) only at **segment vertices**. With
  `Segments = 1` that is just the two ends, so a sequence like `{0:1, 0.15:0, 0.85:0, 1:1}`
  draws nothing at all. Give beams with mid-length keys enough segments (e.g. 12).
- `VelocityParallel` particles run the texture's X along the velocity; an upright texture
  needs `Rotation = -90` to point its tip along the motion.
- Particles are depth-tested against the floor: one centred at ground level loses its lower
  half. Raise the emitter so the quad's bottom sits at the ground.
- Emitters sort by their anchor's distance to the camera plus `ZOffset`. With an elevated
  camera, a higher anchor is nearer, so a dark layer meant to draw over a bright one needs
  a clear margin (e.g. `ZOffset` 3 vs 0.95), not +0.5.
- A dark particle over additive glow needs `LightInfluence = 0`: the effect's PointLight
  otherwise lights it back to orange and it disappears.
- A rate window shorter than a frame (~0.02 s) can emit nothing; use explicit bursts.
- Studio renders only a fraction of particles at low graphics quality. With Editor Quality
  Level on Automatic it can drop to Level 1 (for example when a live-editing session joins),
  and captures show a shorter wall with small bursts missing. Before grading, check
  `settings().Rendering.EditQualityLevel` and keep it at Level 21.
- Moving an `Attachment` (or an emitter's part) between `ctx.Emit` calls in the same frame
  does **not** move the spawn point; every burst lands where it was. To burst clusters at
  different spots from one emitter, give each cluster its own loop step (one burst per
  `ctx.Wait`). To scatter particles, emit
  from an invisible part (`ctx.Anchor()` resized) with `Shape = Disc` (radius = half the
  part's X/Z size; `ShapePartial` < 1 turns it into a ring), or use separate attachments.
- Flat ground/swirl layers: `Orientation = VelocityPerpendicular`,
  `EmissionDirection = Top`, `Speed` ~0.01 → the particle lies in the attachment's XZ
  plane; tilt the attachment to tilt it, spin it with `RotSpeed`.
- Slash flipbooks with dark pixels (e.g. "Medium Glowing Dark Slash") need
  `LightEmission` 0 or 1; values in between render the dark pixels black.
- Additive (`LightEmission = 1`) bright green with `Brightness` > 1 clips to mint/white on
  light ground: carry the green on a solid layer (`LightEmission` 0.3 or less) at higher
  Brightness and keep additive for thin highlights (`design.md` section 4).
- Camera-facing particles near the ground get cut by it (hard straight edge). Raise them
  or shrink them; for flames, spawn ~0.5x their half-size above the ground. Used on purpose, a camera-facing disc centred on the ground reads as a
  dome.
- `Shape = Sphere` with `ShapePartial = 0.5` emits from the upper hemisphere only; with
  `ShapeStyle = Surface` and `ShapeInOut = Inward` particles fly to the centre (suction).
  Lifetime ≈ radius / Speed, slightly less so they vanish before overshooting.
- Streaks flowing inward **across the floor**: put a `Sphere`-shaped emitter on a flattened
  part (e.g. `2R x 0.2 x 2R`) with `ShapeStyle = Surface`, `ShapeInOut = Inward` and
  `VelocityParallel`; particles spawn on the ellipse rim and move radially to the centre.
  A `Disc` with `Inward` does not do this (nothing visible on the floor), and a
  `Cylinder` shape's axis is the part's **X**, so its "inward" streaks all run parallel.
- Ring textures put their ring well inside the quad (e.g. `thick ring 2` centre line at
  ~0.78 of the half-width, `thick ring 3` at ~0.75). Size = wanted ring radius / that
  fraction, or the ring lands inside the shape it should frame.
- Beam-library textures tile vertically, so as particles they show flat cut-off ends.
- A dark-coloured `Neon` part renders flat and unlit: good for translucent dark debris
  that shouldn't turn grey on its sunlit faces.
- A new texture can be blank for the first frames it is used (still loading). For
  screenshots, `ContentProvider:PreloadAsync` it or re-run the scrub.
- Beams and Trails draw their texture with the image's **top at Attachment0** and bottom at
  Attachment1 (TextureMode Stretch). Pick the attachment order to put the right end of a
  shape (e.g. the fanned-out end of grass strands) where you want it.
- `ParticleEmitter.Rotation`: positive values turn the texture counter-clockwise on screen.
- Moving a library effect's emitter through an orbit: set the attachment's CFrame, emit,
  then `ctx.Wait(1/60)` before moving again.
- Library meshes are `SpecialMesh` FileMeshes: size with `SpecialMesh.Scale` (in native
  mesh units; get native size once via `AssetService:CreateMeshPartAsync(id).MeshSize`).
- `MeshPart.TextureID` ignores `Part.Color` (the texture's RGB shows as-is). Don't fade or
  cut a mesh with its texture's alpha (Roqer: the colour covers the whole surface): animate
  the part's `Transparency`, or put a Decal on a part with `Transparency = 1`
  (`meshes.md`, "Mesh effects"). Swapping `TextureID` through dissolve frames with
  `Transparency` just above 0 shows holes; don't rely on it.
- Neon renders colours lighter and yellower: `(255, 145, 35)` reads lemon. Push orange to
  roughly `(255, 110, 25)`. Dark Neon colours read much brighter than their RGB.
- `ForceField` material with a texture gives a shimmering, edge-lit shell whose animation
  speed can't be controlled: a shield or an aura, not a timed wipe (Roqer). It hides what's
  inside at `Transparency` 0. For a timed fresnel rim on a ball, use a camera-facing
  `thick ring 2` particle sized ~1.3x the radius with `ZOffset` = radius.
- Changing an emitter's `Color` / `Size` / `Transparency` applies to particles already
  alive, so one long-lived particle can be animated per frame. `LockedToPart` particles
  follow their attachment when it moves.
- `Trail.Lifetime` is real time. Use textured Trails for ribbons (`motion.md`)
  and set `trail.Lifetime = authored / ctx.TimeScale` so they keep their length in slow-mo
  (Roqer's emit module does the same). A held trail loses its segments during a VFXScrub
  freeze, so capture trail layers while the effect still plays at a very low speed (scrub at
  ~0.04x and capture just before the freeze time) instead of frozen. Even then, Edit-mode
  scrubs render trails inconsistently from run to run (a 0.005x scrub can keep only the
  first segment of a swept ribbon that a 0.02x run showed whole):
  take the screenshot straight after `Scrub.Play` returns, and judge trail layers finally
  in Play mode. A Beam bent into the
  flight parabola (`CurveSize0 = |v0| * t / 3`, `CurveSize1 = -|v(t)| * t / 3`, both
  attachments' X axis along their velocity; verified) is the alternative when a ribbon must
  span the whole flight.
- `Glass` on a dark part renders nearly invisible (it refracts the background). Use
  SmoothPlastic or Neon for dark solid shapes.
- Particles emitted inside an opaque mesh are hidden by it: spawn them above or in front.
- `ParticleEmitter.Squash`: positive values make the particle taller and narrower, and
  negative values make it wider. With `VelocityParallel`, use positive values for streaks
  along the flight.
- A Beam with `FaceCamera = false` spreads its width along its attachments' **Y axis**
  (verified on a fire-wall effect). Rotating the attachments so Y pointed at the viewer
  showed the sheet edge-on. For an upright sheet along a direction D, set the
  attachments to `CFrame.fromMatrix(pos, up, D)`. `Attachment.Position` is in the
  **parent part's** space, not the attachment's own rotated axes, so sway or offset
  rotated attachments in part axes.
- Before you change an emitter or beam property, grep the module for every place that
  writes it. Per-frame loops often reset `Lifetime`, `Speed`, `Size` or `Rotation` each
  frame, which silently undoes a change made only where the emitter is created (a loop that
  reset flame `Lifetime` this way turned a "faster but same height" change into a taller wall).
- How high a rising particle gets ≈ `Speed × Lifetime` (less with `Drag`: `v/k ·
  (1 − e^(−k·t))`). Changing one without the other changes the height.
- Layout frames: `CFrame.lookAt(p, p + towardViewer)` has its RightVector pointing to the
  viewer's left. Build the frame facing away from the viewer
  (`CFrame.lookAt(p, p - towardViewer)`) so that +X = the viewer's right.
- Many flame flipbooks start with tiny frames: as a OneShot burst they stay invisible for
  most of a short lifetime. Use `FlipbookMode = Loop` + `FlipbookStartRandom = true` (and a
  framerate ~16-24) so every particle shows a full-size frame at once.
- A Top-face SurfaceGui runs the image's X along the part's **Z** axis. For a horizontal
  texture (a crack), make the part long on Z and turn it 90 deg about Y so its Z runs
  along the line you want.
- Ground-flat particles (`VelocityPerpendicular`): `Squash = -0.8` at `Rotation = 0`
  stretches the quad ~1.35x along the attachment's X and flattens it to ~0.3-0.4 across,
  giving an ellipse along X. `RotSpeed` turns the whole ellipse, so keep it small. Tilt the
  attachment to tilt the ellipse.
- `VelocityParallel` streaks with any spread toward or away from the camera smear sideways
  into long horizontal blades. For flames that lean, use `FacingCameraWorldUp` and lean
  them with `Rotation` (one emitter per side).
- A circular band (Tube mesh) can't follow a lumpy surface. Paint the band into the
  mesh's own texture instead, or draw the band as a camera-facing arc particle in front
  (a glowing band in front of a gas dome).

### From Roqer (verified in Studio there)

From https://github.com/S4US/Roqer (AGPL-3.0-or-later); details in the files named. These
apply like the gotchas above, and win where one of them disagrees.
- `VelocityPerpendicular` at `Speed` 0 doesn't show at all; give it a tiny Speed (`design.md` 5).
- `VelocityParallel`: `Rotation` -90 puts the image's top first along the motion, 90 its
  bottom, 0 lays it across the motion; it follows the particle's own velocity (`design.md` 5).
- Transparency keys above 1 end a particle before its lifetime; negative Transparency doesn't
  make a soft texture solid (`design.md` 7).
- Black at `LightEmission` 0 is ink, at 0.55 a faint veil, at 1 invisible (`design.md` 3).
- Twins of a lopsided sprite line up only with one fixed `Rotation` and a shared `RotSpeed`
  (`design.md` 3).
- A Decal's `Color3` above 1 is overbright and blooms (`design.md` 4).
- `FlipbookIncompatible` says "must be 1024 by 1024" even for a 1024 sheet that plays
  (`drawing-textures.md`).
- An untextured Trail reads as a flat tube; a Trail's image top is at its head and its left
  edge at `Attachment0` (`motion.md`).
- `RenderFidelity = Automatic` turns a thin crescent into a wedge at distance (`meshes.md`).
- A camera shake applied as `camera.CFrame *= offset` each frame accumulates; undo it before
  the camera scripts run (`camera-world.md`).
- Newer avatars' shoulders are `AnimationConstraint`s, which `Motor6D` code skips silently
  (`camera-world.md`).

## Rules

1. Parent only under `ctx.Folder` (directly or via `ctx.Anchor()`).
2. All timing through ctx: no `task.wait`, `wait`, `task.delay`, raw `TweenService`, or
   `emitter:Emit`. `task.spawn` around a `ctx.Wait` loop is fine.
3. A `Layers.Timeline` clock only advances between events: never block inside an event (a
   flight or sweep loop). Run the loop before or after the Timeline, or spawn it.
4. `Rate = 0` on burst emitters. Looping emitters get `TimeScale = ctx.TimeScale`, and
   `Enabled = false` before `Play` returns.
5. Visible parts: `Anchored`; `CanCollide`, `CanQuery`, `CanTouch`, `CastShadow` false.
6. `Linger` covers the longest particle, trail or mesh-particle lifetime after `Play`
   returns (a slowed layer lives `Lifetime / slow`).
7. Effects may require `Layers`, `MeshParticles` and sibling effects; never `MeshFactory`
   or `VFXScrub` (edit-time tools).
8. No hard runtime dependency on Studio-only folders: ids in `ASSETS`, mesh templates with a
   plain-Part fallback, no `WaitForChild` into them.
9. Defaults: PascalCase keys, attribute-safe types, everything tunable exposed.
10. Stay inside the budget in `SKILL.md`.
11. Effects run on the client only.

## Testing

**Static check.** With luau-lsp (VS Code's Luau extension ships it), run
`luau-lsp analyze --definitions=<globalTypes.d.luau> [--sourcemap=sourcemap.json] <files>` to
catch syntax and type errors. It does not check property names inside `Layers` spec tables:
compare those against the Roblox API, or let the first Studio run's errors tell you.

**In Studio (Play mode).** With the harness installed, press Play, then a number key plays
that effect at the target. Check at 1x for feel, at 0.1x (`[`) for layer order and pops, and
from ~40 studs for readability. Output must show no `VFXPlayer: effect ... errored`.
Effects are required once per session: after editing one, stop and press Play again. With
file sync, first confirm the script in Studio matches the file on disk (sync can be
disconnected).

### Frame-by-frame screenshots (VFXScrub, Edit mode)

```luau
local Scrub = require(game.ReplicatedStorage.VFX.VFXScrub)
local t, count = Scrub.Play("SlashImpact", dummy.HumanoidRootPart.CFrame, nil, 0.1)
-- screenshot now (Studio MCP screen_capture with a fixed camera), then Scrub.Clear()
```

`Play(name, cframe, overrides, stopAt, timeScale?, seed?)` requires a fresh copy of the
effect (picks up edits), seeds `math.random`, advances at `timeScale` (default 0.1) and
freezes particles, tweens and MeshParticles within one frame of `stopAt`. Use a fixed camera
position for every capture and an R15 dummy for scale. Trails keep fading in real time while
frozen: scrub trail-heavy effects at 0.02x and capture straight away. Judge the captures with
`review.md`.

### Matching a reference video (workflow)

`<skill>/tools/clip.mjs` does the frame work (needs Node and ffmpeg on PATH; `node
<skill>/tools/clip.mjs help`). Every time it prints or labels is effect seconds (real game time).

1. Read the clip: `node <skill>/tools/clip.mjs read <video> --from <s> --to <s> [--speed 0.25]`
   (`--speed` for a slowed recording; default output `.vfx-clips/<name>/`). It stores up to
   300 frames, prints measurements and writes `overview.png` (16 frames over where the clip
   changes) and, when the overview steps over the start, `closeup.png`. The measurements:
   - **Timing:** "starts" is when the first layer emits; "peaks" when the flash or core is
     brightest; "falls to half by" places the main layer's fade; "gone by" is the latest any
     layer may still show (its delay plus its lifetime).
   - **Brightness:** a peak near white across the frame is a flash core (short life,
     `LightEmission` 1, high Brightness); a small rise is a glow.
   - **Size:** the share of the frame, and how much it grows from start to largest, is a ratio
     for a `Size` sequence, not studs: the clip's camera is not Studio's.
   - **Colours by phase:** `ColorSequence` keypoints in order (build-up, peak, fade). Fading
     pixels are mixed with the background, so take the hue and lift its brightness rather than
     copying a muddy value.
   - **A moving camera** is reported as such; read the timing from the frame labels instead.
   Compression, bloom and the background shift every number: check each against the frames.
   Before building, name the layers the frames show in the order they appear (anticipation,
   flash or core, main body, secondaries, smoke and fade), each with the times its labels show.
   Then look closer at fast stretches one at a time:
   `node <skill>/tools/clip.mjs span <clip dir> --from 0 --to 0.2 --count 16` (`--crop full` to see
   the ground or the caster around the effect).
   A 0.25x slow-motion recording is far easier to read than 1x; measure real timing from the
   1x one.
   **Analyse every reference very closely: about every 15 ms of real time (10-20 ms), start
   to finish**, not only the onset. A 1x 60 fps video only has a frame every ~16.7 ms, so use
   the slow-motion recording: `clip.mjs read --speed 0.25` on it stores every frame (at 60
   fps, 4.2 ms of real time each; at most 300 frames, so read long effects as several short
   `--from/--to` stretches) and labels each with its real-time offset; `span --count 16` over
   0.25 s gives ~15 ms steps. Crop the frames (`ffmpeg -ss <t> -frames:v 1 -vf crop=...`) to
   see a layer's shape when the sheet is too small to read it.
   **Particle inventory: make sure every particle we use matches the reference's shape and
   type.** For each layer the frames show, write down its shape (crescent strokes, soft glow,
   spike or blade, smoke puff, flipbook boil, continuous streak, dotted streak, ring, star,
   line), whether it faces the camera, lies flat or stretches along its motion, and whether
   it glows or is solid. Then check the texture, `Orientation`, `Squash`, `LightEmission` and
   `TextureMode` we use give that same shape: never swap in a different shape class (a
   spiky ball for a ball of crescent strokes, a puff for a ring of strokes, an upright
   squashed flare for a radial burst, a wrapped beam texture that turns long streaks into
   dashes). Keep the inventory in the effect's header comment and re-check it against the reference and our capture after every change.
   **Track how the particles move from frame to frame.** Compare each frame with the ones
   before it, following the same particle or group: where it spawns, the path it takes
   (straight, arcing, spiralling, drifting), how far it goes per frame (speed, and whether it
   slows: drag; or falls: acceleration), how it spins (`RotSpeed`), how it grows or shrinks
   (the `Size` sequence) and when it fades (`Transparency`, `Lifetime`). For a moving source
   (a projectile, a dash head) record its position along the path at several times and fit
   the easing (e.g. a dash at ~48% of the path 0.18 s after launch, ~70% at 0.28 s, ~86% at
   0.38 s fits `1 - (1 - t)^1.5`). For trails, note which end appears first and which end
   disappears first.
   **Analyse our own capture the same way**: record it at the reference's speed (0.25x),
   read it with `clip.mjs read`, and step both at the same effect times, layer by layer:
   shape, type, size, motion and timing.
2. Build the effect, then capture the same moments with VFXScrub and a fixed camera at
   the reference's elevation, save them named by effect time (`0.10.png`) and put them side
   by side with `node <skill>/tools/clip.mjs compare <clip dir> --captures <folder>` (clip R left,
   ours S right, labelled with effect times; at most 8 moments a sheet). Compare when each layer
   starts, peaks and fades, its size against the frame, its colours and its shape: proportions,
   not position.
   Use 4-6 moments at the clip's own key times (start, peak, half, gone, from the
   measurements), aimed the way the clip frames the effect (side, front or above). Scrub at
   0.05x for t < 0.3 s, since Studio Edit mode can stall ~0.3 s mid-effect and overshoot the
   freeze time at 0.1x. When the reference comes from more than one camera angle, match a
   camera to each: a layer that looks right from the front can be flat, thin or misplaced
   from the side.
3. Grade each round: put the compare sheets in front of a second opinion (a subagent, or
   another model the user has) told that the reference is ground truth, the sheet layout
   (timestamps, which column is the reference), and to return a 0-10 score per moment,
   concrete differences (shape, size, colour, missing or extra layers) and the top fixes in
   order. Check each suggested fix against the sheet before applying it.
   **Compare at most twice** (Roqer): each round is a rebuild plus a capture, and the
   reference can't be copied exactly. After the second round, fix what the pairs show most
   clearly, then report what still differs.
4. Finish with a read-only check of the code: contract, rules grep, Linger maths, budget
   counts.
5. Before every capture, check the Studio module's source matches the file on disk (file
   sync can be disconnected, or a two-way sync can revert edits). A new texture can render blank on
   first use: preload it or re-run the scrub.
6. Say what you approximated. Roblox has no custom shaders, so distortion, heat haze,
   refraction, an engine's bloom strength and textures you cannot see in the frames can only
   be approximated, and particle counts can't be read from frames. Say which parts are
   approximations; don't claim it matches. If the result looks clearly faster or slower than
   the clip and the clip's speed wasn't given, ask.
7. Write down what you learned: new textures in the project's texture list, verified engine
   behaviour and new recipes in the project's notes (or in this skill, if you maintain it).

## New effect checklist

- [ ] Classified; matching recipe, `design.md` and topic files read; closest example read.
- [ ] `Effects/<Name>` created; PascalCase name describes the look.
- [ ] Header comment: path, one-line look, layer list, runtime-only overrides.
- [ ] Every id in `ASSETS` with a comment (and flipbook grid).
- [ ] All tunables in `Defaults` (incl. `Color`, `Scale`), attribute-safe types only.
- [ ] `Linger` covers the longest lifetime.
- [ ] Mesh templates looked up without yielding, with a fallback; no `MeshFactory` require.
- [ ] Rules grep is clean:
      `grep -nE "task\.(wait|delay)|[^.]wait\(|TweenService|:Emit\(|MeshFactory|VFXScrub" <file>`
- [ ] Within budget.
- [ ] Tested in Play mode at 1x and 0.1x and from ~40 studs; captures judged with `review.md`.
- [ ] Drawn flipbooks pass `<skill>/tools/flipbook.mjs`.
