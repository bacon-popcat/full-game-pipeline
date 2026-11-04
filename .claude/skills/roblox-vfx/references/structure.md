# VFX code structure

Part of the `roblox-vfx` skill (`.claude/skills/roblox-vfx/references/structure.md`): the
authoritative guide to where VFX code lives, how it is organized, and how to test it. How to
*design* an effect (layers, values, recipes) lives in `SKILL.md` and the other
`references/`. Read both before writing an effect. Paths like `references/x.md` are relative
to the skill folder; `src/...` paths are relative to the repo root.

## Layout

Disk is the source of truth for code. `rojo serve` syncs `src/` into Studio live; edits
made to synced scripts inside Studio are overwritten. Edit files on disk only. If the
Rojo plugin in Studio is not connected, nothing syncs: connect it (or push the changed
module's `Source` yourself and checksum it) before testing. Keep the Rojo plugin's
two-way sync **off**: with it on, Studio's copy of a script is written back to disk every
couple of seconds and silently reverts disk edits Rojo hasn't pushed yet.

```
VFX/                                  (repo root)
├── default.project.json              Rojo tree (below)
├── CLAUDE.md                         project instructions (points here)
├── .claude/skills/roblox-vfx/        skill: SKILL.md, references/*.md (this file:
│                                     references/structure.md), examples/*.luau
├── tools/vfx/                        dev-machine tools (Node/Python, AGPL from Roqer): clip.mjs
│                                     (reference clips, compare, colour check), flipbook.mjs,
│                                     vfxtex.py + examples.py (drawn textures); see its README
├── tools/luau-test/                  runs every effect outside Studio (luau CLI): errors, Linger, budget
├── assets/textures/                  drawn texture sources (<group>.py) and their PNGs
└── src/
    ├── shared/VFX/
    │   ├── VFXPlayer.luau            plays effects by name, builds ctx
    │   ├── Layers.luau               builds emitters/lights/parts from spec tables, twins, timelines
    │   ├── Textures.luau             drawn textures (ids, flipbook grid), library fallbacks until uploaded
    │   ├── MeshParticles.luau        MeshPart "particles" (client sim)
    │   ├── MeshFactory.luau          edit-time mesh generator/publisher
    │   ├── VFXScrub.luau             edit-time freeze-frame player for screenshots
    │   ├── VFXCamera.luau            locks the camera on an effect at fixed angles (side/top/3/4)
    │   ├── ForgeBridge.luau          plays VFX Forge templates for ctx.Forge
    │   ├── ForgeAssets/<Name>.rbxmx  VFX Forge templates (Models), see "VFX Forge layers"
    │   └── Effects/<Name>.luau       one ModuleScript per effect
    ├── shared/Packages/              Wally packages (ForgeVFX), written by `wally install` and committed
    ├── shared/WindSword/             Wind Sword timings (init.luau) + Slash RemoteEvent (Slash.model.json)
    ├── client/
    │   ├── init.client.luau          VFXHarness test bench (Studio + live place)
    │   └── WindSwordReplicator.client.luau   plays other players' Wind Sword slashes
    ├── server/
    │   ├── init.server.luau          placeholder
    │   └── WindSwordServer.server.luau       validates and relays Wind Sword slashes
    └── starterpack/WindSword/        the Wind Sword Tool (init.meta.json, Handle, WindSwordClient)
```

| Disk | Studio | Class |
|---|---|---|
| `src/shared/VFX/VFXPlayer.luau` | `ReplicatedStorage.Shared.VFX.VFXPlayer` | ModuleScript |
| `src/shared/VFX/Layers.luau` | `ReplicatedStorage.Shared.VFX.Layers` | ModuleScript |
| `src/shared/VFX/Textures.luau` | `ReplicatedStorage.Shared.VFX.Textures` | ModuleScript |
| `src/shared/VFX/MeshParticles.luau` | `ReplicatedStorage.Shared.VFX.MeshParticles` | ModuleScript |
| `src/shared/VFX/MeshFactory.luau` | `ReplicatedStorage.Shared.VFX.MeshFactory` | ModuleScript |
| `src/shared/VFX/VFXScrub.luau` | `ReplicatedStorage.Shared.VFX.VFXScrub` | ModuleScript |
| `src/shared/VFX/VFXCamera.luau` | `ReplicatedStorage.Shared.VFX.VFXCamera` | ModuleScript |
| `src/shared/VFX/VFXShake.luau` | `ReplicatedStorage.Shared.VFX.VFXShake` | ModuleScript (camera shake behind `ctx.Shake`) |
| `src/shared/VFX/ForgeBridge.luau` | `ReplicatedStorage.Shared.VFX.ForgeBridge` | ModuleScript |
| `src/shared/VFX/ForgeAssets/<Name>.rbxmx` | `ReplicatedStorage.Shared.VFX.ForgeAssets.<Name>` | Model (Forge template) |
| `src/shared/Packages/ForgeVFX.lua` | `ReplicatedStorage.Shared.Packages.ForgeVFX` | ModuleScript (Wally link to the ForgeVFX package) |
| `src/shared/VFX/Effects/<Name>.luau` | `ReplicatedStorage.Shared.VFX.Effects.<Name>` | ModuleScript |
| `src/client/init.client.luau` | `StarterPlayer.StarterPlayerScripts.Client` | LocalScript |
| `src/server/init.server.luau` | `ServerScriptService.Server` | Script (calls `ForgeVFX.init()` for Forge's collision groups) |
| `src/shared/WindSword/` | `ReplicatedStorage.Shared.WindSword` (+ `.Slash` RemoteEvent) | ModuleScript |
| `src/client/WindSwordReplicator.client.luau` | `StarterPlayer.StarterPlayerScripts.Client.WindSwordReplicator` | LocalScript |
| `src/server/WindSwordServer.server.luau` | `ServerScriptService.Server.WindSwordServer` | Script |
| `src/starterpack/WindSword/` | `StarterPack.WindSword` | Tool (Handle part, `WindSwordClient` LocalScript) |
| (not on disk) | `ReplicatedStorage.Assets.Meshes` | Folder of MeshFactory templates |
| (not on disk) | `ReplicatedStorage.Assets.VFX` | Art library (asset cards) |
| (runtime) | `Workspace.ActiveVFX.<Name>` | `ctx.Folder`, one per play |
| (edit time) | `Workspace.VFXScrub` | `ctx.Folder` of a VFXScrub freeze-frame; `Clear()` removes it |
| (runtime, harness) | `Workspace.VFXHarnessConfig`, `Workspace.VFXTarget`, `PlayerGui.VFXHarness` | |

Rojo rules that matter here:
- File name = instance name. `.luau` = ModuleScript, `.client.luau` = LocalScript,
  `.server.luau` = Script. `init.*.luau` turns its folder into that script, so any other
  file in `src/client/` becomes a child of the `Client` LocalScript (a `.luau` file a child
  ModuleScript, a `.client.luau` file a child LocalScript).
- Folders mapped with `$path` are Rojo-owned: Rojo can delete instances that aren't on
  disk. Never store Studio-made content (mesh templates, assets) under `Shared`,
  `Client`, or `Server`. Studio-only content goes in `ReplicatedStorage.Assets`
  (`Assets.VFX` = art library, `Assets.Meshes` = mesh templates).

## Runtime flow

```luau
local VFXPlayer = require(game:GetService("ReplicatedStorage").Shared.VFX.VFXPlayer)
VFXPlayer.Play("SlashImpact", hitCFrame, { Color = Color3.fromRGB(120, 200, 255) })
```

`Play(name, cframe, overrides)` requires `Effects.<name>` once (cached), merges
`Defaults` with `overrides` into `ctx.Params`, and runs `Effect.Play(ctx)` in a new
thread. Errors are caught and warned (`VFXPlayer: effect '<name>' errored`). When `Play`
returns, it waits `Linger` (effect time) and destroys `ctx.Folder`. `VFXPlayer.TimeScale`
is read once per play; `VFXPlayer.Clear()` removes everything. Call it from the client
only. Server-triggered effects need a RemoteEvent (the Wind Sword's `Slash` is the one
example). The server decides that something happened and fires the effect's name and a
CFrame; each client plays it. Prefer an `UnreliableRemoteEvent` for pure presentation: it
drops payloads over 1000 bytes, so send names and numbers, never instances. Never let damage
or rewards wait on an effect. To time an effect to an animation, play it from the track's
`GetMarkerReachedSignal("<Marker>")` on the hit keyframe rather than a fixed delay.

**Instance overrides.** Overrides can carry instances (e.g. the sword part), which can't
be `Defaults` (attributes): `VFXPlayer.Play("WindBladeTrail", root.CFrame, { Weapon = blade })`.
Document such runtime-only keys in the effect's header and always handle them being nil.

**Composite effects.** An effect may require sibling effects and call their `Play` with a
child ctx (see `WindSpinSlashCombo`): `setmetatable({ Params = params }, { __index = ctx })`
shares the folder, clock and helpers. Set `Linger` to the max of the children's. In a real
game prefer firing the parts from animation events (windup start, hit frame) so they stay
in sync with the animation.

### Wind spin-slash move

| Effect | Plays | Notes |
|---|---|---|
| `WindBladeTrail` | during the windup | `Weapon` override = blade part (`BladeBase`/`BladeTip` attachments optional); `Duration` = time to the hit frame. Without a weapon it builds a stand-in katana. |
| `WindSpinSlash` | on the hit frame | `ctx.CFrame` = caster root. |
| `WindSpinSlashCombo` | both, back to back | Harness preview of the full move. |

The playable version is the **Wind Sword** tool (`src/starterpack/WindSword`, every player
spawns with it). Clicking plays `WindSpinSlashCombo` with `Weapon = Handle` and the
default tool slash animation, then fires `Shared.WindSword.Slash`; the server
(`src/server/WindSwordServer.server.luau`) checks equip + cooldown and relays it, and
`src/client/WindSwordReplicator.client.luau` plays it for everyone else. Timings live in
`src/shared/WindSword/init.luau`. The blade runs along the Handle's -Z axis (tip
attachment `BladeTip`); keep `Tool.Grip` and the attachments in sync if you resize it.

### Magnet pull

`MagnetPull`: purple gravity suction centred on the ground below `ctx.CFrame`, in a
five-colour palette (`Color`, `AccentColor`, `HighlightColor`, `DeepColor`, `InkColor`).
With `BlackHole` (default on), an anticipation (`FlashTime`, `FlashSize`): a spiky star
and its black twin swell while spinning, then implode; the hole tears open with a pop, a
flare and a ring of bolts and black streaks, and a held core (`CoreSize` = R) built like an
orb holds in the centre: black linework, a hard ring, swirling rays, a black pupil (a dark
Neon ball), an outer ring, a soft halo and a black backdrop, each cross-fading (Rate 3,
Transparency 1-0-1) so it shimmers, with arcs flashing each pulse. The pull runs for
`Duration` (1.5 s): a faint dome, a dark ground disc and a magenta band that hands over to a
thin hot ring pop in at `Radius` and shrink into the centre every `PulseInterval`, while dark
shards (MeshParticles), specks, lilac smoke wisps (`WispRate`), floor streaks
(`StreakRate`), lightning with black jagged twins and thin magenta/black lines are pulled in.
`BlackHole = false` gives the suction only.

### Fireball explosion

`FireballExplosion`: a fireball's finishing explosion on the ground below `ctx.CFrame`
(`Radius` = R, 7 studs). Play returns once the comets land (~0.9 s); the scorch and cracks
fade by ~2.7 s.
1. 0 s: a spiky flash (2.5 R), a white-hot core at Brightness 40 and a cross flare, gone by
   ~0.09 s; a light pops and fades while its range grows to `LightRange`.
2. 0.03 s: impact stars (colour/black/white) and the fire body: two drawn fire-burst
   flipbooks (`FireCount` each) and a small hot copy, shooting out and hanging, cooling from
   yellow-white to red; a slower, bigger late wave at 0.1 s keeps the mass growing. Comets
   leave at 0.035 s: a hot head, a sharp and a soft textured Trail (lifetimes divided by
   `ctx.TimeScale`) and shed sparks, along a parabola (`CometSpeed`, `CometGravity`).
3. 0.06 s: a black backing, mottled smoke from the same burst (grey and a fire-tinted twin,
   slowed to 0.75x), streaks with black twins, a ground ring and embers.
4. 0.26 s: a charcoal burn-out shows through as the fire breaks up; 0.3 s: a scorch and lava
   cracks that cool from orange to dark over `CrackTime`, with thin smoke wisps.

### Lava eruption

`LavaEruption`: a lava fissure on the ground below `ctx.CFrame`, running across the view
(along its RightVector). Plain Luau, no Forge. `WallLength` sizes the crack (F = 20 studs
at Scale 1); the curtain, wind, column and smoke use the body size B = 0.72 F. `Scale`
(default 2.5) sizes everything. Play returns when the crack has faded, at ~4.35 s. Matched
frame by frame against two reference camera angles (agy-graded), then given the
Roqer guidance on top without touching the pulse timing.
1. 0.04-0.6 s precursor: one wide burst of orange and dark streaks, grey rocks, upright
   flame bursts (gone by ~0.45 s), 4 bold orange rings (custom `lava_ring`), a grey smoke veil
   (the drawn DustPuff sheet, self-lit, never more solid than 0.5) and embers. The crack (Top-face SurfaceGuis: a branched dark crack, a lumpy lava line and a
   red pool) heats up from 0.3 s.
2. 0.69 s (`EruptTime`): a spiky flash squashed wide along the crack with a white glint
   (gone by ~0.12 s), a spike row, a low radial starburst of wedge flares (custom
   `lava_wedge`) and a curtain of solid-colour flame tongues (LightEmission 0.3,
   Brightness 3) up within ~0.04 s (the opening burst rushes up faster and stands ~20%
   taller). Three tongue bands follow the curtain width: the sides reach ~0.65 B, the
   centre band ~0.95 B. A soft flame body, a boiling base of drawn fire-burst sheets behind
   the tongues (it replaced two scrolling beam veils), wind arcs that rise as they spin,
   and the hot line along the whole crack come with it. The light pops and its range
   spreads 0.6x -> 1x over 0.3 s while it fades.
3. From 0.80 s the centre loops a ~0.49 s pulse (measured on 60 fps strips of both videos):
   a bright soft blob swells at the base (`lava_glow`), then a darker red flame burns up
   through it (custom `lava_hollow2`, unlit, emitted as bursts at 0.85, 1.34, 1.83, 2.32,
   2.81 and 3.30 s), so its rim reads as an arch for ~0.05 s; ~0.2 s later a tall slender
   teardrop flares (`lava_wedge`), and the sides lean into a small V. There is no standing
   ring: the reference's "arch" is these moving layers. ~0.95-1.05 s: the curtain opens
   into a V around the first teardrop. The curtain holds ~0.72 B wide with dark tongues at
   its edges.
4. From 2.85 s (`EruptTime` + `BurnTime`): the sides stop, small flame clumps flare at the
   old edges, and the centre hands over (~3.0-3.15 s) to a die-down fan of straight streaks
   (custom `lava_streak`, two outward-tilted half-boxes plus a bright core) that closes into
   a parallel bundle by 3.4 s and is gone by ~3.67 s.

One per-frame loop (`ctx.Wait(1/240)`) drives the bursts (one per step), channel rates,
emitter box widths, beam widths, the light and the crack. Instances: ~56 (a deliberate
overrun of the ~50 guideline to match the reference); burst particles ~194.

### Chromatic strike

`ChromaticStrike`: a white, prismatic ranged strike, rebuilt from reference videos (1x from
two angles, then 0.25x from far and from behind the caster; the reference's blue variant was
not copied). `ImpactScale` (1.15) sizes the target eruption on top of `Scale`. `WidthScale` (1.35) spreads it sideways
(emitter volumes, smoke jets, base and floor rings) without making it taller. `ctx.CFrame` is the target; the caster stands `CasterDistance` (32) studs along
its LookVector, or pass the runtime-only override `Caster` (a BasePart). `Scale` (2.5) sizes
the target eruption; caster bursts, projectiles and the dash use 0.56x of it. Plain Luau, one
per-frame loop (`ctx.Wait(1/240)`) running a time-sorted event list. Play returns at ~3.95 s;
smoke is gone by ~5.2 s.
1. 0.13-1.25 s: six projectiles in two bursts of three (WIRES): four white sky shots and two
   low smoky streaks. Each is a locked
   4-point star head flown along a Catmull-Rom spline, drawing three camera-facing Trails (a
   white core, a soft white haze `cs_soft_trail` and a dark smoke edge) that stay from the
   caster until they fade. Each trail's width pinches and swells with the distance flown, so
   it reads as a twisting smoky ribbon. As a trail fades its Lifetime shrinks, so it erases
   from the caster end toward the target, as in the reference. They replaced a chain of beam segments, which kinked
   and banded at every joint. The low streaks are chunky smoky plumes with chromatic heads;
   sparkle stars and prismatic flares spray round the caster on each salvo. A steep arch
   over the left, then (0.6 s) one that shoots very high, loops over itself and dives in.
2. 1.10 s: spiky white ball at the target, chromatic ground ring + wind dome at the caster;
   1.30 s black void frame (2 frames); 1.33 s prismatic launch (white mass + radial chromatic
   rays) and the dash (sized by `DashScale`, 1.6x): it rushes ~78% of the way, then grinds
   in (tracked on the far clip: ~48% of the path 0.18 s after the launch, ~70% at 0.28 s,
   ~86% at 0.38 s). Its head is the front of a fireball: a round white front of churning crescent strokes
   with white flame tongues streaming back from it,
   with a dark smoke wedge (`shotHead`) with rainbow slivers on its edges and black debris; a
   thin bright line and a soft white haze run back to the caster, and fading crescent
   afterimages hang along the path. Tunnel rings and
   a rainbow ground streak drawn behind the head: wide with a white centre for ~0.15 s after
   the launch, then a thin twin line that turns orange. Dark shell, bokeh, sparkle stars,
   black ink scribbles and chromatic wisps at the caster (wisps at the size measured on the
   behind-the-caster clip).
3. `ImpactTime` 1.85 s: white-hot core star, jagged V-wing flash (custom `cs_impact_flash`,
   white over red/blue copies for the fringe), a churning black ink heart in the middle
   (Glowing Black Energy, drawn in front of the white glow), blast streaks, a ground flash ring, screen wash
   and magenta/teal edge vignette (camera-locked particles), light pillar, dark shockwave,
   base ring, and a white smoke blast: soft jets and billows sprayed low and flat in every
   direction (again on each surge). The burn runs to `FinaleTime` (3.7 s): rising thin halos
   (`cs_halo_thin`), crystal spike fans with three surges (each a core pop, a ground flash
   ring, more crown spikes, chips and white smoke), a few rainbow spikes, RGB glitch
   bolts (`cs_rgb_bolt`) drawn additive and see-through (light refracting through glass:
   the baked black edges drop out; drawn solid they read as cartoon zigzag decals) with thin
   rainbow streaks beside them, a dense urchin of thin white spikes bursting out of the centre over dark
   churning chunks, a crown of thin white energy spikes shooting up round the base
   (at the hit, each surge and through the burn), dark chips flung out, a thin swirling floor smoke drawn behind the centre (`ZOffset` < 0; the blast smoke is
   clear while still in the middle), since thick smoke turned the burn into a white wall, 4-point star flashes every ~0.06 s plus five big cross stars, blade
   flares, rising motes, leaves, rocks, puffs, smoke, wind rings.
4. `FinaleTime`: a 4-point cross that shrinks to a dot with a ground flash and a blast;
   arched smoke hooks (`cs_smoke_hook`) and floor smoke linger.
Particle inventory (checked against both 0.25x reference clips and a 0.25x Studio capture,
2026-10-21; re-check every layer here after any change). Each line is what the reference
shows -> what we use:
- projectiles: six, in two caster bursts of three (0.13-0.15 s and 0.5-0.54 s): each burst a
  shot over the left, a low smoky streak and a shot over the right; the second burst's
  right shot is the tallest (star glint at its apex). One caster burst per three.
- projectile trails: wobbly smoky white ribbons ~0.5 stud wide (low streak ~1.5) with a black
  outline, glitter -> three camera-facing Trails per projectile (`WireWidth` 0.36; at 0.18 the
  capture showed hairlines). The outline is a near-opaque black ribbon ~1.35x the haze's
  width, placed 0.3 x scale behind the white (away from the camera) so it always draws
  behind: Trails have no ZOffset.
- projectile heads: small bright 4-point stars; the low streak's chromatic -> Star / ChromWisp.
- charge dome: crescent strokes swirling round a hemisphere -> spinning `DashSwirl` quads (a
  Wispy Sphere puff read as a blob).
- void: a black disc ~3 caster heights across, 2 frames -> DarkDisc, 9-10 x caster scale.
- launch: white mass with radial rainbow rays -> ImpactFlash + SunRays turned randomly (world-up
  and squashed they read as a crown of upright spikes).
- dash head: the front of a fireball: a round white front of curled strokes with white
  flame tongues streaming back from it, dark smoke wedge behind -> churning `DashSwirl` + Glow
  core + `lava_streak` tongues locked to the head (VelocityParallel, emitted backward), with a
  black outline (a dark Glow disc just bigger than the ball and dark, wider copies of the
  tongues behind them; a dark SoftTrail beam behind the line's haze) +
  `shotHead` wedge (a Starburst ball with a spike splash did not match; a fast-spinning
  crescent ball alone read as a disc).
- ground streak: thin twin rainbow line under a soft white streak -> RainbowStreak beam + line.
- impact: jagged white flash with red/blue fringes, dark ink heart -> `cs_impact_flash` x3 +
  Glowing Black Energy.
- pillar: wide soft translucent column of long continuous vertical streaks round a dark
  smoky core -> PillarCore (faint, 0.6-0.75 of the width), PillarLines stretched once (wrapped
  every 18 studs they broke into dotted dashes), PillarDark.
- burn spikes: thin translucent white slivers leaning out, sharp tips -> JaggedShard fans
  (Squash 1.8, Transparency 0.4-0.55, barely glowing). At Squash 0.35-0.5 the shard read as
  thick soft arrowheads.
- centre while burning: a dense cluster of thin translucent white spikes standing up,
  many sizes, overlapping like ice, with white 4-point stars flashing all through it and
  little soft glow -> `centerSpikes` (JaggedShard, FacingCameraWorldUp, Squash 1.8,
  Transparency 0.45-0.6, LightEmission 0.25, `CenterSpikeRate`) and `centerStars` (Star,
  `CenterStarRate`). The pillar core stays faint and the floor smoke does not glow: soft
  glows over the centre washed it into a white haze that hid the spikes.
- RGB bolts: thin, a little see-through rainbow-split bolts that spike out of the centre
  fast, mostly sideways, and are gone in a few frames -> `cs_rgb_bolt` VelocityParallel from
  the centre (Speed 60-100 x scale, Drag 20, Lifetime 0.05-0.09, additive), 2-3 at a time
  through the burn and 4 per surge. Placed still in a box they read as stickers.
- no black ink claw slashes: the reference has none (they read as a black crescent behind
  the centre).
- centre see-through: every layer in the middle is translucent (spikes 0.3-0.6, prismatic
  blobs small at 0.5-0.65, pillar lines dim); stacked opaque or glowing layers turned it
  into a white cloud.
- halos: thin crisp rings, the top one about as wide as the base ring -> HaloThin / NeonRing.
- finale: a crisp thin 4-point cross high on the pillar -> Star + thin bars (Squash -0.97).
Camera shake (`ctx.Shake`, `Shake`/`ShakeScale`): 2.2 deg at the launch, 11 deg on the impact
(~6 deg peak measured once it adds up with distance falloff), a 1.8 deg rumble through the
burn, 5.5 deg on the finale.
Budget: a deliberate overrun to match the reference (the user raised it): ~190 instances
(6 projectiles x 3 Trails, ~95 emitters) and ~700 burst particles plus rate channels. Lower
`SmudgeRate`, `SmokeRate`, `SpikeRate`,
`SparkCount`, `SpeckCount`, `BokehCount`, `StreakCount`, `PuffCount` and `MoteRate` for
crowds; `Vignette` and `Shake` should be on only for the caster's own client.
Grading note (2026-10-21): with the default per-frame agy prompt, the reference graded
against its own second playback scored 6/10, so absolute agy scores on this effect are
capped well below 10; compare against that baseline.

## VFX Forge layers

[ForgeVFX](https://github.com/zilibobi/forge-vfx) is the emit module of the VFX Forge
plugin, installed with Wally (`wally.toml`; `wally install` writes `src/shared/Packages`).
It plays effects authored as data: instances whose Forge attributes (`EmitDelay`,
`EmitCount`, `EmitDuration`, `EffectDuration`, `Width0_End`, mesh `Start`/`End` parts,
`BezierParticle`/`LightningBolt`/`Shockwave` tags...) describe the timeline.

**When to use it.** Only when the effect needs something Forge does and our code doesn't:
an effect authored in the Forge plugin (or a Forge reference being reproduced), Forge
mesh VFX (Start/End tweens with decals on the mesh), bezier projectiles, lightning bolts,
ground shockwave rings/lines/debris. Procedural effects stay plain Luau: the existing
effects don't use Forge, and a layer that is simple in Luau shouldn't move to Forge.

**Templates.** A Forge template is a Model saved as `src/shared/VFX/ForgeAssets/<Name>.rbxmx`
(Rojo syncs it to `Shared.VFX.ForgeAssets.<Name>`). Its pivot is the effect origin (on
the ground, LookVector toward the viewer, like `ctx.CFrame`), its children are the Forge
items, and nothing in it is Studio-only. Invisible host parts: `Transparency = 1`,
`Anchored`, and `CanCollide`/`CanQuery`/`CanTouch`/`CastShadow` false. Edit a template on
a copy in Studio with the Forge plugin, then save it back over the `.rbxmx` (right-click >
Save to File); Rojo overwrites edits made to the synced copy. Name templates after their
role (`LavaEruption`, `LavaEruptionCrack`). Don't `cacheAttributes` a template.

**Playing.** Look the template up without yielding and sequence layers with `ctx.Wait`
(this replaces Forge's folder `Stagger` and custom sequence scripts):

```luau
local forgeAssets = script.Parent.Parent:FindFirstChild("ForgeAssets")
local crackTemplate = forgeAssets and forgeAssets:FindFirstChild("LavaEruptionCrack")

function Effect.Play(ctx)
	local p = ctx.Params
	if crackTemplate then
		ctx.Forge(crackTemplate, ctx.CFrame, { Scale = p.Scale })
	else
		warn("LavaEruption: ForgeAssets.LavaEruptionCrack is missing")
	end
	ctx.Wait(p.EruptDelay)
	-- ...
end
```

`ctx.Forge` (via `ForgeBridge`) clones the template, scales it (`Model:ScaleTo` plus the
mesh scales, light ranges and Forge size attributes it misses), recolors it with Forge's
`recolor` if `Color` is given, retimes it to `ctx.TimeScale` with Forge's `retime` (plus
looping flipbook framerates), parents it to `ctx.Folder` and emits its children. Forge
timings live in the template's attributes, so expose only the knobs the effect needs in
`Defaults` (delays between layers, `Scale`, optional `Color`). To tune a Forge value per
play, clone the template yourself, set the attribute or property on the clone (never on
the template) and pass the clone to `ctx.Forge`.

**License (VFX-DL 1.1).** ForgeVFX may run only in game runtime (including Studio
playtests), not in plugins, edit-time tools or test tooling. `ForgeBridge` loads it lazily
on a running client only; the server loads it for `init()`. `VFXScrub` in Edit mode skips
Forge layers with a warning, so preview Forge effects in Play mode with the VFXHarness.
Never require ForgeVFX from `MeshFactory`, `VFXScrub` or MCP/command-bar snippets.

## Effect module contract

Base new effects on this template. Order: header, requires, `ASSETS`, constants,
local helpers, `Effect`, `Defaults`, `Linger`, `Play`, `return`.

```luau
-- ModuleScript: ReplicatedStorage/Shared/VFX/Effects/<EffectName>
-- <What it looks like, one line.> Layers: <core>, <shape>, <secondary>, <residue>.

local VFX = script.Parent.Parent
local Layers = require(VFX:WaitForChild("Layers"))
local Textures = require(VFX:WaitForChild("Textures")) -- only if it uses drawn textures
local MeshParticles = require(VFX:WaitForChild("MeshParticles")) -- only if used

-- Library ids from ReplicatedStorage.Assets.VFX. Comment = <Folder>/<CardName>.
local ASSETS = {
	CoreGlow = "rbxassetid://0", -- StaticVFXTextures/<CardName>
	WindSheet = { Id = "rbxassetid://0", Grid = 4 }, -- FlipbookTextures/<CardName> (cell 256 -> Grid4x4)
	StreakBeam = "rbxassetid://0", -- MigratedBeams/<CardName>
	ImpactStar = Textures.ImpactStar, -- drawn: assets/textures/impact.py (Grid4x4)
	SwirlMesh = { -- MigratedMeshes/<CardName>
		MeshId = "rbxassetid://0",
		TextureId = "rbxassetid://0",
		Scale = Vector3.new(1, 1, 1),
	},
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
		Texture = ASSETS.ImpactStar,
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

`Layers` (`src/shared/VFX/Layers.luau`, header for the full list): `Emitter`/`Twin`/`Black`/
`Dim`/`White` build emitters from spec tables (sequences, ranges, enums and textures given
compactly; `Flat = true` lies a sprite in the attachment's plane); `Light` and `Pop` (flash
and fade a light while its range grows, capped at 60); `Part`, `Quiet`, `Attachment`;
`Timeline` (`{ time, fn }` steps in effect time); `Track` (keyframe value at t); `Ground`
(raycast below, skipping characters) and `Frame` (layout frame, +X = viewer's right);
`Emit(ctx, e, n, slow)` for lingering layers. `Textures` holds the drawn sheets as
`{ Id, Grid }`, with a library fallback until each is uploaded.

The module's top level must not yield on or error over anything Studio-only: the harness
requires every effect at startup, and one bad module stops it.

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
| `ctx.Wait(t)` | -> number | Yield in effect time. Returns the effect time that actually passed (often more than `t`: a 1/60 wait usually takes 1-2 frames). Per-frame loops should add the return value, not `t`, to their clock. |
| `ctx.Shake(magnitude, duration, options?)` | | Shake the local camera: rotation only, `magnitude` in degrees, `duration` in effect seconds, distance-gated (`options.Range`, default 250 studs from `options.Position` or the effect). `options`: `Roughness`, `FadeIn`. Implemented by `VFXShake` (undo before the camera scripts, apply after, so it never drifts); `VFXPlayer.Clear` stops it, `VFXScrub` skips it. Pass a `Shake = false` override for effects replicated from other players. |
| `ctx.Forge(template, cf?, options?)` | -> env | Play a VFX Forge template as a layer at `cf` (default `ctx.CFrame`), retimed to `ctx.TimeScale`. Non-blocking; `env.Finished:await()` waits for it. `options`: `{ Scale = n, Color = Color3, ColorMode = "multiply" or "replace" }`. See "VFX Forge layers". |

`MeshParticles.Burst(ctx, template, count, config)`: non-blocking mesh debris; config in
`references/properties.md`.

## Naming

- **Effects:** PascalCase, describing what it looks like or does: `WindSpinSlash`,
  `GroundSlam`, `SlashImpact`. Not the owner (`RangerUlt`) and no versions (`SlashV2`).
  File name = module name = the name passed to `VFXPlayer.Play`.
- **Locals and helpers:** camelCase verbs for functions (`makeBurstEmitter`, `spawnRing`),
  camelCase nouns for values (`ringTemplate`). Module constants: UPPER_SNAKE (`ASSETS`,
  `RING_SEGMENTS`); keys inside `ASSETS` are PascalCase.
- **Defaults keys:** PascalCase, noun first: `RingSize`, `RingTime`, `SparkCount`,
  `SparkSpeed`, `RockColor`. Suffixes: `Count` (integer), `Time` (effect seconds), `Speed`
  (studs/s; `SpinSpeed`/`RotSpeed` are degrees/s, matching the engine and MeshParticles),
  `Size` (studs), `Color` (Color3). Always include `Color` and `Scale`.
- **Defaults types:** number, boolean, string, Color3, Vector3 only. The harness turns
  Defaults into attributes and `P` prints only these back as Luau. Build NumberRange /
  NumberSequence / ColorSequence / Enum values inside `Play` from scalars
  (`NumberRange.new(p.SparkSpeed * 0.6, p.SparkSpeed)`).
- **Mesh templates:** PascalCase shape names (`CrescentThin170`), per `references/meshes.md`.
- **Instances in ctx.Folder:** optional PascalCase names (`Flash`, `Ring`) for debugging.

## Assets

The art library `ReplicatedStorage.Assets.VFX` is Studio-only (four folders of ImageButton
cards; table and lookup snippet in `references/textures.md`, "Asset library").

**Convention: copy ids into the effect.** Put every library id in the `ASSETS` table at the
top of the effect, with `-- <Folder>/<CardName>` so it can be found again. The library is
not on disk or Rojo-managed, and its cards are UI objects that can be renamed or moved; an
asset id never changes, and the effect file stays self-contained and reviewable.

Never `WaitForChild` into `Assets` from an effect. For quick prototyping only, a card can be
read at runtime with an id fallback:

```luau
local function cardImage(folderName, cardName) -- returns nil if anything is missing
	local node = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
	for _, name in { "VFX", folderName, cardName, "Texture" } do
		node = node and node:FindFirstChild(name)
	end
	return node and node.Image
end

local glow = cardImage("StaticVFXTextures", "<CardName>") or ASSETS.CoreGlow
```

Replace it with the plain `ASSETS` id before the effect is done.

**Flipbooks:** grid = sheet / `OriginalRectSize` (1024 sheet: 512 -> `Grid2x2`,
256 -> `Grid4x4`, 128 -> `Grid8x8`). Note the grid in the `ASSETS` comment.

**Library meshes** (`MigratedMeshes`): rebuild as Part + `SpecialMesh` (FileMesh) from the
ids. A FileMesh is sized by `SpecialMesh.Scale`, not `Part.Size`: tween `mesh.Scale`, and
note that `MeshParticles.Burst` size curves do nothing on these parts (it sets `Part.Size`;
Transparency still works). For shrinking debris, use MeshFactory MeshPart templates.

**MeshFactory templates** live in `ReplicatedStorage.Assets.Meshes` (Studio-only). Look them up
without yielding and keep a plain-Part fallback (pattern in `examples/GroundSlam.luau`):

```luau
local meshRoot = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
local meshFolder = meshRoot and meshRoot:FindFirstChild("Meshes")
```

## Layering and timing (summary; details in the skill docs)

- Many single-sprite layers (40-60 in a studied hit), stacked and timed in place; the
  impact skeleton and category breakdowns are in `references/recipes.md`, the numbers in
  `references/design.md`.
- The flash at 0 (0.03-0.15 s), every other layer at +0.03 s or later in 0.025-0.05 s steps;
  intensity only falls after that. Expansion easing: `Quad` or `Exponential` Out
  (`Enum.EasingStyle.Expo` does not exist).
- Typical durations: slash 0.2-0.4s, impact 0.3-0.6s, movement 0.3-0.5s, ground slam
  0.6-1.2s, buff 0.6-1.2s, explosion 0.8-1.5s.
- Sequence layers with `ctx.Wait`. For a parallel timeline use
  `task.spawn(function() ctx.Wait(t) ... end)`, never `task.delay` (real time). `Play`
  should return around the last layer's peak; `Linger` covers whatever is still fading.
- Colour on solid layers (`LightEmission` 0.3 or less, Brightness 5-55); additive only for
  thin highlights and small glows; `LightInfluence = 0` on energy and most smoke.
- Budget, colors, and look: `SKILL.md` "Budget" and `references/style-guide.md` (still unfilled).

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
  Brightness and keep additive for thin highlights (`references/design.md` section 4).
- Camera-facing particles near the ground get cut by it (hard straight edge). Raise them
  or shrink them; for flames, spawn ~0.5x their half-size above the ground. Used on purpose, a camera-facing disc centred on the ground reads as a
  dome (see `MagnetPull`).
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
- `MigratedBeams` textures tile vertically, so as particles they show flat cut-off ends.
- A dark-coloured `Neon` part renders flat and unlit: good for translucent dark debris
  that shouldn't turn grey on its sunlit faces.
- A new texture can be blank for the first frames it is used (still loading). For
  screenshots, `ContentProvider:PreloadAsync` it or re-run the scrub.
- Beams and Trails draw their texture with the image's **top at Attachment0** and bottom at
  Attachment1 (TextureMode Stretch). Pick the attachment order to put the right end of a
  shape (e.g. the fanned-out end of grass strands) where you want it.
- `ParticleEmitter.Rotation`: positive values turn the texture counter-clockwise on screen.
- Moving a library effect's emitter through an orbit: set the attachment's CFrame, emit,
  then `ctx.Wait(1/60)` before moving again (see the shed streaks in `WindSpinSlash`).
- Library meshes are `SpecialMesh` FileMeshes: size with `SpecialMesh.Scale` (in native
  mesh units; get native size once via `AssetService:CreateMeshPartAsync(id).MeshSize`).
- `MeshPart.TextureID` ignores `Part.Color` (the texture's RGB shows as-is). Don't fade or
  cut a mesh with its texture's alpha (Roqer: the colour covers the whole surface): animate
  the part's `Transparency`, or put a Decal on a part with `Transparency = 1`
  (`references/meshes.md`, "Mesh effects"). The old `FireballExplosion` swapped `TextureID`
  through dissolve frames with `Transparency` just above 0 and showed holes; don't rely on it.
- Neon renders colours lighter and yellower: `(255, 145, 35)` reads lemon. Push orange to
  roughly `(255, 110, 25)`. Dark Neon colours read much brighter than their RGB.
- `ForceField` material with a texture gives a shimmering, edge-lit shell whose animation
  speed can't be controlled: a shield or an aura, not a timed wipe (Roqer). It hides what's
  inside at `Transparency` 0. For a timed fresnel rim on a ball, use a camera-facing
  `thick ring 2` particle sized ~1.3x the radius with `ZOffset` = radius.
- Changing an emitter's `Color` / `Size` / `Transparency` applies to particles already
  alive, so one long-lived particle can be animated per frame. `LockedToPart` particles
  follow their attachment when it moves.
- `Trail.Lifetime` is real time. Use textured Trails for ribbons (`references/motion.md`)
  and set `trail.Lifetime = authored / ctx.TimeScale` so they keep their length in slow-mo
  (Roqer's emit module does the same). A held trail loses its segments during a VFXScrub
  freeze, so capture trail layers while the effect still plays at a very low speed (scrub at
  ~0.04x and capture just before the freeze time) instead of frozen. Even then, Edit-mode
  scrubs render trails inconsistently from run to run (2026-11: a 0.005x scrub kept only
  the first segment of CrescentSlash's ribbons, while a 0.02x run had shown all of them):
  take the screenshot straight after `Scrub.Play` returns, and judge trail layers finally
  in the VFXHarness. A Beam bent into the
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
  (verified on `LavaEruption`). Rotating the attachments so Y pointed at the viewer
  showed the sheet edge-on. For an upright sheet along a direction D, set the
  attachments to `CFrame.fromMatrix(pos, up, D)`. `Attachment.Position` is in the
  **parent part's** space, not the attachment's own rotated axes, so sway or offset
  rotated attachments in part axes.
- Before you change an emitter or beam property, grep the module for every place that
  writes it. Per-frame loops often reset `Lifetime`, `Speed`, `Size` or `Rotation` each
  frame, which silently undoes a change made only where the emitter is created
  (`LavaEruption` reset tongue `Lifetime` this way, so a "faster but same height"
  change made the wall taller).
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
  (`BandArc` on the gas dome).

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

1. Parent only under `ctx.Folder` (directly or via `ctx.Anchor()`). Forge layers are the one
   exception: ForgeVFX parks some of its parts in `workspace.Terrain` and removes them itself.
2. All timing through ctx: no `task.wait`, `wait`, `task.delay`, raw `TweenService`, or `emitter:Emit`.
   Forge layers go through `ctx.Forge`, never `ForgeVFX.emit` directly (it would ignore slow-mo).
3. `Rate = 0` on burst emitters.
4. Visible parts: `Anchored`; `CanCollide`, `CanQuery`, `CanTouch`, `CastShadow` false.
5. `Linger` covers the longest particle or mesh-particle lifetime after `Play` returns.
6. Effects may require `MeshParticles`, `Layers` and `Textures`; never `MeshFactory`,
   `VFXScrub` (edit-time tools), `ForgeBridge` or the ForgeVFX package (use `ctx.Forge`).
7. No hard runtime dependency on Studio-only folders: library assets as `ASSETS` ids,
   mesh templates with a plain-Part fallback, no `WaitForChild` into them.
8. Defaults: PascalCase keys, attribute-safe types, everything tunable exposed.
9. Stay inside the budget in `SKILL.md`.
10. Edit code on disk, never in Studio. Don't put Studio-made instances in Rojo folders.
11. Effects run on the client only.

## Testing (VFXHarness)

**Before Studio**, run `node tools/luau-test/run.mjs [<Effect>]` (needs the `luau` CLI,
https://github.com/luau-lang/luau/releases, on PATH or as `LUAU=<path>`). It runs every
effect on a virtual clock with Roblox stubs that type-check every property, at 1x and 0.25x,
and reports errors (mapped to file:line), bad property names, types, enums and sequences,
Linger that cuts particles off, PointLight ranges over 60, instances left outside
`ctx.Folder`, and particle/instance counts. It doesn't render, so look in Studio too. Add an
override case to `CASES` in `run.mjs` for an effect with runtime-only keys. Add `--examples` to
also run the skill's `examples/` as if they were in `Effects/` (a real effect of the same name
wins). Without the `luau` CLI, `luau-lsp analyze --definitions=<globalTypes.d.luau>
--sourcemap=sourcemap.json <files>` still catches syntax and type errors (not property names
inside `Layers` spec tables).

1. With `rojo serve` connected, press Play in Studio. The harness adds a button for every
   ModuleScript in `Effects` and a target part 12 studs in front of you.
2. Keys: `R` replay, `L` loop (every 1.5s, scaled), `[` / `]` speed 0.1 / 0.25 / 0.5 / 1x,
   `T` move target in front of you, `P` print current params as a `Effect.Defaults` table.
   Each key also has an on-screen button (Replay, Loop, Target, Slower, Faster, Print), so
   the harness works on touch: use Studio's device emulator, or join the published place on
   a phone (the harness runs outside Studio too; `P` output goes to the Developer Console).
   `Hide` collapses the panel so it doesn't cover the effect.
3. Tune live: select `Workspace.VFXHarnessConfig.<Effect>` and edit its attributes. Press `P`
   and paste into the file on disk before stopping; edits are lost on stop.
4. Effects are required once per session. After editing a file (or adding a new effect),
   stop and press Play again.
5. Check at 1x for feel, at 0.1x for layer order and pops, and from ~40 studs for
   readability. Output must show no `VFXPlayer: effect ... errored` or `VFXHarness` warnings.
6. Judge the captures with the questions in `references/review.md` (two views: close, and
   from the player's camera), and run the colour check on them:
   `node tools/vfx/clip.mjs tone --dir <captures> --empty <capture past the end>`.

### Frame-by-frame screenshots (VFXScrub, Edit mode)

To match a reference video, compare the same effect times side by side:

```luau
local Scrub = require(game.ReplicatedStorage.Shared.VFX.VFXScrub)
local t, count = Scrub.Play("WindSpinSlash", dummy.HumanoidRootPart.CFrame, nil, 0.1)
-- screenshot now (Studio MCP screen_capture with a fixed camera), then Scrub.Clear()
```

`Play` requires a fresh copy of the effect (picks up edits), seeds `math.random`, advances
at 0.1x and freezes particles, tweens and MeshParticles within one frame of `stopAt`. Use a fixed
camera position/FOV for every capture and an R15 dummy for scale. Extract reference frames
with ffmpeg at the same times (t = 0 at the slash's first frame).

### Matching a reference video (workflow)

`tools/vfx/clip.mjs` does the frame work (needs Node and ffmpeg on PATH; `node
tools/vfx/clip.mjs help`). Every time it prints or labels is effect seconds (real game time).

1. Read the clip: `node tools/vfx/clip.mjs read <video> --from <s> --to <s> [--speed 0.25]`
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
   `node tools/vfx/clip.mjs span <clip dir> --from 0 --to 0.2 --count 16` (`--crop full` to see
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
   dashes). Keep the inventory in the effect's section of this file (see "Chromatic strike")
   and re-check it against the reference and our capture after every change.
   **Track how the particles move from frame to frame.** Compare each frame with the ones
   before it, following the same particle or group: where it spawns, the path it takes
   (straight, arcing, spiralling, drifting), how far it goes per frame (speed, and whether it
   slows: drag; or falls: acceleration), how it spins (`RotSpeed`), how it grows or shrinks
   (the `Size` sequence) and when it fades (`Transparency`, `Lifetime`). For a moving source
   (a projectile, a dash head) record its position along the path at several times and fit
   the easing (ChromaticStrike's dash: ~48% of the path 0.18 s after the launch, ~70% at
   0.28 s, ~86% at 0.38 s, `1 - (1 - t)^1.5`). For trails, note which end appears first and
   which end disappears first (ChromaticStrike's trails erase from the caster end).
   **Analyse our own capture the same way**: record it at the reference's speed (0.25x),
   read it with `clip.mjs read`, and step both at the same effect times, layer by layer:
   shape, type, size, motion and timing.
2. Build the effect, then capture the same moments with VFXScrub and a fixed camera at
   the reference's elevation, save them named by effect time (`0.10.png`) and put them side
   by side with `node tools/vfx/clip.mjs compare <clip dir> --captures <folder>` (clip R left,
   ours S right, labelled with effect times; at most 8 moments a sheet). Compare when each layer
   starts, peaks and fades, its size against the frame, its colours and its shape: proportions,
   not position.
   Use 4-6 moments at the clip's own key times (start, peak, half, gone, from the
   measurements), aimed the way the clip frames the effect (side, front or above). Scrub at
   0.05x for t < 0.3 s, since Studio Edit mode can stall ~0.3 s mid-effect and overshoot the
   freeze time at 0.1x. When the reference comes from more than one camera angle, match a
   camera to each: a layer that looks right from the front can be flat, thin or misplaced
   from the side.
3. Grade each round with **agy** (Antigravity CLI, Gemini), not a Claude subagent. Run
   `.claude/skills/roblox-vfx/scripts/agy_grade.sh <sheet dir> [NNNN ...]` as a background
   Bash command: it calls `agy.exe` directly on one sheet JPEG at a time (retry once) and
   writes `agy_NNNN.txt` next to it. Don't grade through the `agy-bridge` MCP: an image grade
   takes ~1-2 min (agy logs in again on every call, ~40 s even for a trivial prompt) and the
   app's MCP hop gives up at ~60 s, so about half the calls fail with "Request timed out".
   It grades with Gemini 4 Argon (High) (`gemini-4-argon-high`); set `AGY_MODEL` to another
   id or name from `agy models` to change it. A wrong name prints the model list instead of a
   grade, which the script reports as a missing score.
   Set `AGY_QUESTION` to replace the default (lava) question. It should say: the
   reference is ground truth, grade **only against it**, what the sheet layout is
   (timestamps, which column is REF, which row is which angle, grid spacing), what is out of
   scope, and ask for a 0-10 score per timestamp and angle, concrete differences (shape,
   size in studs, colour, missing or extra layers, detail), and the top fixes in order.
   Treat its stud sizes as estimates and its hex colours as guesses, and check each fix
   against the sheet yourself before applying it.
   **Compare at most twice** (Roqer): each round is a rebuild plus a capture, and the
   reference can't be copied exactly. After the second round, fix what the pairs show most
   clearly, then report what still differs.
4. Finish with a read-only file-integrity subagent: contract, rules grep, Linger maths,
   budget counts, docs accuracy.
5. Before every capture, check the Studio module's Source hash matches the disk file (Rojo
   can be disconnected or two-way sync can revert edits). A new texture can render blank on
   first use: preload it or re-run the scrub.
6. Say what you approximated. Roblox has no custom shaders, so distortion, heat haze,
   refraction, an engine's bloom strength and textures you cannot see in the frames can only
   be approximated, and particle counts can't be read from frames. Say which parts are
   approximations; don't claim it matches. If the result looks clearly faster or slower than
   the clip and the clip's speed wasn't given, ask.
7. Write down what you learned: new textures in `references/textures.md`, verified engine
   behaviour in "Engine gotchas", a recipe for a new effect category in
   `references/recipes.md`.

## New effect checklist

- [ ] Classified, matching recipe and `references/design.md` (plus topic files) read; the
      contract's shape taken from the template / `examples/`.
- [ ] `src/shared/VFX/Effects/<Name>.luau` created on disk; PascalCase name describes the look.
- [ ] Header comment: Studio path, one-line look, layer list.
- [ ] Every library id in `ASSETS` with a `-- <Folder>/<CardName>` comment (and flipbook grid).
- [ ] All tunables in `Defaults` (incl. `Color`, `Scale`), attribute-safe types only.
- [ ] `Linger` covers the longest lifetime.
- [ ] Mesh templates looked up without yielding, with a fallback; no `MeshFactory` require.
- [ ] `node tools/luau-test/run.mjs <Name>` passes with no warnings.
- [ ] Rules grep is clean:
      `grep -nE "task\.(wait|delay)|[^.]wait\(|TweenService|:Emit\(|MeshFactory|ForgeVFX|ForgeBridge|\.emit\(" src/shared/VFX/Effects/<Name>.luau`
- [ ] Forge layers only if the effect needs them (see "VFX Forge layers"); template looked up
      without yielding, with a warning if missing; `Linger` covers the Forge layers' end.
- [ ] Within budget.
- [ ] Tested in the harness at 1x and 0.1x; tuned Defaults pasted back.
- [ ] Captures judged with `references/review.md` from the close and the player's view; colour
      check run (`clip.mjs tone`).
- [ ] Drawn flipbooks pass `tools/vfx/flipbook.mjs` (no problems; notes weighed).
- [ ] Reusable new textures added to `references/textures.md`.

## Open issues (2026-10-12; delete each line when fixed)

- `ctx` has no FOV, blur or impact-frame helper yet (camera shake exists: `ctx.Shake`). Add
  one to `VFXPlayer` (and mirror it in `VFXScrub`) when the first effect needs it.
- The drawn textures in `src/shared/VFX/Textures.luau` (`Textures.Pending`) still use library
  fallbacks: upload `assets/textures/*.flipbook.png`, `Glint.png` and `ShockRing.png` and put
  the ids in `UPLOADED`. The redesigned effects (2026-10-21) were checked with
  `tools/luau-test` only, not yet looked at in Studio.
- `tools/vfx` (2026-10-21) was tested on synthetic clips and sheets in a Linux container, not
  yet on Oscar's Windows PC; `vfxtex.render_flipbook` and MeshFactory `Surface`/`Swirl`/`Dome`
  have not run in Blender/Studio yet.

- `references/style-guide.md` is an unfilled template.
- `core.autocrlf=true` rewrites files to CRLF on checkout; consider a `.gitattributes`
  with `* text=auto eol=lf` so Luau files stay LF.
