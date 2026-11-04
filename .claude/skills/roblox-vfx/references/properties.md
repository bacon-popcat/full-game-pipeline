# Properties that matter

## ParticleEmitter
| Property | Notes / good start |
|---|---|
| Rate | 0 for bursts (use ctx.Emit). |
| Lifetime | NumberRange. Sparks 0.2-0.45, glow 0.3-0.6, smoke 0.8-1.5. |
| Speed | NumberRange. Sparks 20-40, smoke 1-4. |
| SpreadAngle | Vector2. (180,180) = all directions. (15,15) = cone. |
| Size / Transparency | NumberSequence. Pop then shrink; fade in last 30-50%. Give Size keys an envelope (`NumberSequenceKeypoint.new(t, v, envelope)`, about a third of the peak) so particles differ in size. Transparency keys above 1 end a particle early; negative values don't make a soft texture solid. |
| Color | ColorSequence. Use 2-3 keypoints for value contrast. |
| LightEmission | 1 = additive glow (thin highlights, small glows; washes out over a bright sky). 0 = solid colour (most saturated studied layers sit at 0.3 or less). Negative (-1 to -3) = saturated and solid with a dark rim. Black renders as ink at 0, a faint veil at 0.55, invisible at 1. |
| LightInfluence | 0 = ignores scene lighting: energy and most smoke (self-lit smoke keeps its grey in shade). 0.5-1 only when matter must sit in the scene's light. |
| Brightness | Multiplies Color. Read the place's Bloom first: studied hot layers run 15 (median) to 50+, sharp shapes ~4, soft glows 1-6 (often <1), smoke ~1.6 self-lit. A dark Color at high Brightness is not dark. |
| Drag | Half-life of speed in seconds. High (5-16) makes bursts snap out then hang: Speed 45-75 at Drag 16, 25-60 at Drag 6. |
| Acceleration | Gravity for debris (y -30 to -80), rise for smoke (y 2-6). |
| Squash | NumberSequence; stretches particles. Pair with VelocityParallel for streaks. |
| Orientation | FacingCamera (default), VelocityParallel (streaks; `Rotation` -90 puts the image's top first), VelocityPerpendicular (flat discs; needs a tiny Speed or it doesn't show), FacingCameraWorldUp (upright columns). |
| Rotation / RotSpeed | Random rotation hides texture repetition. |
| FlipbookLayout / Mode / Framerate | For animated sheets (Grid2x2/4x4/8x8). OneShot for bursts; Loop + FlipbookStartRandom for burning fire; Loop at Framerate 0 + StartRandom for one random variant per particle. See `drawing-textures.md`. |
| ZOffset | Push core layers forward so they draw over smoke. Scale with the effect: ~±1 for a 10-stud orb, 0-3 for an impact, tens of studs for a huge explosion. |
| Shape / ShapeStyle / ShapeInOut | Emit from a volume or surface, e.g. Disc + Outward for ground rings. The emitter must sit directly under a part sized for the shape; under an Attachment it emits from a point. |
| EmissionDirection | NormalId the emitter points along (e.g. Top for upward dust). |
| LockedToPart | true for projectile cores, auras, held forms. Off for anything thrown off. |
| TimeScale | Set by ctx.Emit. To slow a lingering layer (smoke, wind at 0.6-0.95), multiply it right after `ctx.Emit`. |

## Beam
Attachment0/1, Width0/1, CurveSize0/1 (arcs), Segments (smoothness), Texture,
TextureMode (Stretch/Wrap/Static), TextureSpeed (scrolling energy), LightEmission,
Brightness, FaceCamera, Transparency (NumberSequence), ZOffset.
Segments: 20+ for a visible curve (studied slash beams use 100-360). Give stacked beams
different TextureLength/TextureSpeed so their scrolls never line up (`motion.md`).

## Trail
Attachment0/1, Lifetime (0.1-0.3 for weapons), WidthScale (taper to 0), MinLength,
FaceCamera, Texture, LightEmission, Transparency, Color.
Always textured (an untextured trail is a flat tube); weapon trails in pairs: a thin hot core
(0.04-0.15 s, Brightness 10-30) and a soft wisp (0.15-0.4 s, LightEmission 0.55-0.75).
Lifetime is real time: set it to `authored / ctx.TimeScale` (`structure.md` gotchas).

## Highlight
FillColor, FillTransparency, OutlineColor, OutlineTransparency, DepthMode.
Good for hit flashes and buffs: tween FillTransparency from ~0.4 to 1.

## Neon parts (flashes, rings)
Material Neon, Anchored, CanCollide/CanQuery/CanTouch/CastShadow false.
Cylinder axis is local X: size (thickness, diameter, diameter).

## Mesh templates (cloned from ReplicatedStorage/Assets/Meshes)
- Templates are already Anchored with collisions/queries/shadows off.
- Energy look: Material Neon + Color. Matter look: Slate/Concrete/Ice + Color.
- Gradient look: set `TextureID` to a gradient texture; MeshFactory meshes run U
  along the shape, so a horizontal gradient fades along a slash.
- Animate with ctx.Tween on Size, Transparency, CFrame. Size scales the mesh.
- MeshFactory shapes lie flat with Y up; rotate the CFrame to the swing/impact plane.
  Crescent is centered on +X.

## MeshParticles.Burst(ctx, template, count, config)
Non-blocking. Simulated client-side; respects slow-mo.

| Config | Type | Default | Notes |
|---|---|---|---|
| Origin | Vector3 | ctx.CFrame.Position | |
| Direction | Vector3 | up | center of the emission cone |
| Spread | number (deg) | 45 | cone half-angle, 0-180 |
| Speed | NumberRange/number | 20 | studs/sec |
| Lifetime | NumberRange/number | 1 | seconds; Linger must cover the max |
| Drag | number | 0 | exponential slowdown |
| Acceleration | Vector3 | (0,-60,0) | gravity; debris uses -80 to -110 |
| SpinSpeed | NumberRange/number | 360 | degrees/sec, random axis |
| Scale | number | 1 | multiplies template size |
| Size | NumberSequence/number | 1 | multiplier over lifetime; shrink to 0 at the end |
| Transparency | NumberSequence/number | 0 | over lifetime |
| SpawnRadius | number | 0 | random offset from Origin |
