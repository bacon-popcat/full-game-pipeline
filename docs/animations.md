# Block animations

Placed machines animate their own moving parts on each client, only while they work. Blocks never
bob, pop or move as a whole. `src/client/controllers/BlockAnimationController.luau` owns it all;
nothing here changes the game.

## What moves

| Machine | Part (art key) | Motion |
|---|---|---|
| Rock Drill | `Bit` | spins on its vertical axle |
| Fruit Press (`Juicer`) | `Juice`, `Piston` | the juice fills over five seconds, drains as the batch is bottled, and churns; the piston pumps |
| Grain Mill (`Mill`, Mk II too) | `Sails`, `Millstone` | the sails turn on their hub; the top stone grinds |
| Harvester (Mk II too) | `Reel` | rolls its tines toward the patch |
| Seed Planter (Mk II too) | `Wheels` | turn slowly |
| Crate Packer | `Press` | stamps down on the crate and eases back up |
| Assembler (`Workbench`) | `Gear` | turns |
| Sprinkler (Mk II too) | `Head` | sweeps all the time (a sprinkler has no working state) |
| Smelter, Baking Oven | `Glow`, `Stack` | the fire flickers; soft smoke rises from the stack |

"Working" is the machine model's `Status` attribute, which FactoryService replicates. A machine eases
up to speed and winds down over `EASE` seconds rather than snapping.

## How it works

- A part is found by its art key, the suffix of `Mesh_<Asset>_<Key>`. `ANIMATIONS` in the controller
  maps each key to a motion (Spin, Slide, Fill, Flicker or Smoke) and its numbers. A Mk II machine
  that borrows its tier 1 art animates the same; art without a key simply stays still.
- The moving part is hidden with `LocalTransparencyModifier` and a local copy, with no collision or
  queries, is moved instead (`BulkMoveTo` each frame). The real part keeps its CFrame, size and
  collision, so hitboxes, placement and the server never see the motion. Rest, culling or the block
  leaving shows the real part again and drops the copy.
- One RenderStepped loop drives every block. The quality preset (docs/lighting.md) sets how far away
  blocks still animate (Low 60, Medium 90, High 120 studs), how often copies move, and whether stacks
  smoke (not on Low). Reduced motion stops it all.

## The art contract

Each moving piece is its own mesh part, built under its own key in
`IslandsMachines/build/garden_machines.py`, and rotationally symmetric about its axle, so its
bounding-box centre (where Studio puts the part) lies on the axle. Axes are in the block's authored
frame: +Y up, +Z the way items travel, +X across.

## Adding an animation

1. In `garden_machines.py`, build the moving piece under a key of its own (`m.add('Fan', ...)`).
2. Rebuild and export (headless Blender: `runner.run(...)`, then `roblox_data.run(...)` for its set),
   clear the changed parts' ids from the set folder's `_MeshAssetIds`, delete the machine's showcase
   model, run `studio_import.luau` for its set, then `studio_blocks.luau` and `studio_cells.luau`
   (IslandsMachines/README.md).
3. Add the key to `ANIMATIONS`.
4. Playtest: place the machine and make it work (or set its `Status` to "Working" on the client),
   and check the part moves about its axle without drifting.
