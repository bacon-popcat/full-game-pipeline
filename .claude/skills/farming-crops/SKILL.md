---
name: farming-crops
description: >
  Growing systems: seeds, soil, growth stages, single and regrowing (multi-harvest) crops,
  offline growth, mutations, weather, watering, sprinklers, and machines that plant and
  harvest. Use when adding a crop or plant, changing grow times or yields, adding mutations
  or weather events, building planters, harvesters or sprinklers, or fixing crops that don't
  grow, grow while offline wrongly, or duplicate on harvest.
---

# Farming and crops

This is a Grow a Garden-style garden loop inside a calm farming game. Read `docs/farming.md`
on the `farming` and `garden-overhaul` branches, and the Crops, Mutations and Weather
sections of `docs/overhaul.md`. Crops do not exist on master.

## Model

- **A crop is a world node, not a placed block.** Planting a seed calls
  `WorldService.plant` directly from BuildService. A seed never becomes a block for a moment,
  so a save can't catch a half-planted seed.
- **One catalogue drives everything.** `Shared/World.CROPS` gives each crop its seed,
  harvest, machine yield and stage times, and builds the stage definitions and the plant
  mapping from them. The picker machine reads its sources from the same catalogue.
- **Soil is queried, not tracked.** `Shared/World/Soil` asks the world whether a placed soil
  block (`World.SOIL_BLOCKS`) or a node marked `soil` (Farmland) is under the cell, the same
  way `Build` tests overlap. The ghost, the placement check and planting all ask it.
- **Growth runs on the wall clock.** Save `plantedAt = os.time()` and work the stage out from
  elapsed time, so crops keep growing offline and a loaded crop jumps straight to the stage it
  has reached. For countdowns in the UI, publish a `GrowsAt` deadline in `GetServerTimeNow`
  time.
- **Stages** are `Sprout`, `Young`, `Mature`, `Ripe`, with separate art for each in
  `Assets.World`. Crop art doesn't collide but can be queried.
- **Single and multi crops.** A single crop is uprooted when harvested and must be replanted.
  A multi crop stays in the ground: a harvest takes the fruit, and the fruit grows back after
  `regrow`. Machine reaping restarts the crop as a Sprout and advances `harvestCount`.
- **A mutation is its own item id** (`<Crop>+<Mutation>`), rolled when the crop ripens (and
  again on each regrow for multi crops). It stacks, rides belts and can be filtered.
  Processing machines take any mutation of their input and output the plain product. Its
  value is the crop's value times the mutation's multiplier.
- **Weather is a server-wide event** rolled on a timer and shown as a banner for everyone. It
  changes growth speed and mutation chances while it lasts. Keep it pleasant (rain, golden
  hour), never a punishment; this is a calm game.

## Rules that prevent bugs

- Ownership: planting and harvesting are owner-only, checked by the shared rule (red ghost)
  and again on the server. Shared areas (the quarry) stay open to everyone.
- Removing soil uproots its crop into owned drops. When a plot is cleaned up, remove crops
  **before** blocks, or the cleanup harvests twice. A deferred removal checks the soil again.
- Only crops grow offline. Machine jobs don't simulate the time away.
- A machine target (a soil cell, a ripe crop) must be inside the machine's own plot both when
  the job is chosen and when it finishes.
- Unripe crops dug up by hand return their seed. Ripe ones give the harvest and seeds.

## Adding a crop

1. Add the seed and produce items to `Inventory/Items`.
2. Add a `World.CROPS` entry with the rarity, seed price, value, grow time, kind (single or
   multi) and yield.
3. Add art: a seed ghost in `Assets.Blocks`, the four stages in `Assets.World` and the produce
   in `Assets.Items`. Until the art phase, borrow another crop's stages tinted the new colour.
   Follow the art direction: soft, rounded, light warm colours, and a shape of its own, not an
   Islands copy.
4. Add the seed to the planter's plant list in `Factory/Blocks`.
5. Saves store crop ids, not stage art ids, so renaming art needs no migration.

## Balance check

For each crop at the level it unlocks: seed cost, value times yield, grow time, coins per
minute per cell, and payback. Rarer crops should be worth more per cell, but never make the
common crops pointless to plant. Use the overhaul's tables as the baseline.
