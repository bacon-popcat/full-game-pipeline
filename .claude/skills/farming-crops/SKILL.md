---
name: farming-crops
description: >
  Growing systems: seeds, soil, growth stages, crops harvested once or regrowing, offline
  growth, mutations and rarities, weather events, watering, sprinklers, and machines that
  plant and harvest. Use when adding crops or plants, changing grow times or yields, adding
  mutations or weather, building planters, harvesters or sprinklers, or fixing crops that
  won't grow, grow wrongly while players are offline, or duplicate when harvested.
---

# Farming and crops

This is a Grow a Garden-style loop: plant, wait, harvest, sell, with automation layered on
top. It builds on `world-resources-and-drops` (nodes), `grid-building` (planting is placing)
and `economy-progression`.

## Model

- **A crop is a world node, not a placed block.** Planting should create the crop directly.
  Don't make the seed a block first and convert it later, or a save could catch a seed
  half planted.
- **One crop table drives everything:** each crop's seed, harvest, yield, rarity, grow time
  and kind. Build the stage definitions, the seed-to-crop mapping and the harvesters' source
  lists from that table, so a new crop is one entry.
- **Ask the world about soil; don't keep a soil map.** "Can I plant here?" asks whether a
  soil block or a soil node is under the cell. The ghost, the placement check and machines
  all ask the same function.
- **Grow on the wall clock.** Save `plantedAt` (Unix time) and work the stage out from the
  elapsed time, so crops grow while the player is offline and a loaded crop jumps straight to
  the stage it has reached. For countdowns in the UI, publish a deadline in the server's
  synced clock (`workspace:GetServerTimeNow()` on Roblox).
- **Stages:** for example Sprout, Young, Mature, Ripe, each with its own art. Crop art
  usually doesn't collide but can be queried, so it can be aimed at.
- **Two kinds of crop.** A *single* crop is uprooted when harvested and has to be replanted.
  A *multi* crop stays planted: a harvest takes its fruit, which grows back after `regrow`
  seconds. A harvesting machine can replant a single crop from a seed it keeps.
- **A mutation is its own item id** (`<Crop>+<Mutation>`). Roll it when the crop ripens (and
  again on each regrow), so it stacks, rides belts and can be filtered. Processing machines
  accept any mutation of their input and output the plain product. Its price is the base
  value times the mutation's multiplier.
- **Weather is a server-wide event.** Roll it on a timer and show it to everyone. It changes
  growth speed and mutation chances while it lasts. Decide on purpose whether weather can
  hurt crops; in a relaxed game it should only help.

## Rules that prevent bugs

- Planting and harvesting are owner-only. Check on the client (red ghost) and again on the
  server. Shared areas say clearly that they are shared.
- Removing soil uproots the crop on it into drops owned by the crop's owner. When cleaning
  up a player's area, remove crops **before** the blocks under them, or they get harvested
  twice.
- Only time-based growth runs offline. Machine jobs don't simulate the time away unless you
  design for it.
- A machine's target must be inside the machine's own area both when the job is chosen and
  when it finishes.
- Digging up an unripe crop returns its seed. A ripe crop gives its harvest (and seeds, if
  the design says so).

## Adding a crop

1. Add a seed item and a produce item.
2. Add a crop table entry with its rarity, seed price, value, grow time, kind and yield.
3. Add art: a seed ghost, each stage and the produce. A tinted copy of another crop's art is
   fine as a placeholder.
4. Add the seed to any planter machine's list, if that list isn't built from the table.
5. Save crop ids, not stage art ids, so renaming art needs no save migration.

## Balance check

For each crop, at its unlock level, work out: seed cost, value × yield, grow time, coins per
minute per cell, and payback time. Rarer crops should earn more per cell, without making the
common ones pointless.
