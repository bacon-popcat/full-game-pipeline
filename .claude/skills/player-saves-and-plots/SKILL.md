---
name: player-saves-and-plots
description: >
  Saving player progress and per-player plots: ProfileStore sessions, the profile template,
  load, restore and release order, plot-relative layouts, cleaning bad entries, versioned
  stores, autosave, and assigning and freeing plots on a shared map. Use when adding saved
  fields, changing what persists, building tycoon or garden plots, fixing data loss,
  duplication or players kicked on join, or testing saves in Studio.
---

# Player saves and plots

On branch `garden-overhaul`: `server/services/DataService`, `PlotService`, `Shared/Plot`
and `docs/plots.md` (read it with `git show garden-overhaul:docs/plots.md`). ProfileStore is
`ServerStorage.ServerPackages.ProfileStore` (wally `sekuriyo-lotus/profilestore`). For
general DataStore detail, see `roblox-skills:roblox-data-stores`.

## Load order (the part that matters)

```text
StartSessionAsync -> reconcile + validate
  fail / session lost -> kick, release runtime state
PlotService.assign            first free plot, Owner attribute, sign
BuildService.restore          blocks (soil first) -> FactoryService register/restore
WorldService.restore          crops, with elapsed wall-clock growth
InventoryService.load + EconomyService.load -> sync + leaderstats
DataReady = true              only now can the player edit anything
```

Leaving runs the reverse: snapshot, clear crops, unregister and remove blocks, clear drops,
inventory and economy, release the plot, then `EndSession`.

- **Gate every edit on `DataReady`.** Otherwise a player can place before their save lands
  and the restore collides with it.
- **No sibling's `init` is a prerequisite.** Modules start in any order (`ModuleLoader`), so
  set up state when the module is required, and make plot building idempotent so assignment
  works even if `PlotService.init` hasn't run yet.

## What to save

- **Plain data only.** Vectors become 3-number arrays, and empty slots stay `false`.
- **Save relative to the plot origin**, so a layout loads into whichever plot is free. Keep all
  plots facing the same way, so rotations and `Against` axes need no transform.
- **Save causes, not results.** XP, not level; `plantedAt`, not the stage; item counts, not
  lane positions (rebuild them at legal spacing).
- **In-progress work is refunded, not saved.** Active recipe inputs go back into the
  machine's inputs and the job restarts. Partial progress, sensor pulses and loose drops are
  not saved.
- **Skip what no longer fits, don't kick.** A saved stack, block, crop or machine's contents
  whose item was renamed or cut is skipped with a warning, so a content change never locks a
  player out. Only a broken save shape, bad balances or a full server fail the load, and those
  release the profile **unchanged**.
- **Version the store name** (`GardenFoundation_v1`). A breaking schema change gets a new
  name or a migration, never a silent reinterpretation.

## Saving

Set ProfileStore's `AUTO_SAVE_PERIOD` (two minutes here). Also refresh the snapshot on that
timer, from `OnSave` (including the shutdown save) and before `EndSession`. Snapshot the live
services; don't keep a second copy that drifts.

## Plots

- `Shared/Plot` owns the bounds, origins and cell conversions (6 plots of 24 × 24 cells,
  height 80). PlotService owns the runtime grass, soft non-colliding fences, signs and
  farmland.
- A joining player takes the first free plot, and it is freed when they leave. When the server
  is full, the extra player is rejected without changing their save.
- Plot index and owner never come from the client. Every write (place, plant, harvest,
  machine controls, belt pickup) checks the whole footprint is inside the player's own plot,
  on both sides.
- Machines, lanes and sensors stay inside their own plot; drops keep their owner.
- Players spawn at the shared hub, not on a plot.

## Testing

Studio without API access uses ProfileStore's mock store: it reloads within one server but
not after Stop. Follow the playtest list in `docs/plots.md`, which includes: join fresh,
two-player permission tests, save and rejoin into a **different** plot, leaving mid-job,
and session locking from a second server with API access on. A deliberately invalid save
must fail without replacing the original. Lint and type checks are no substitute.
