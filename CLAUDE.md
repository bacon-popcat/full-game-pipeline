# Full game pipeline

A calm Roblox farming game in the spirit of Grow a Garden, with factory automation: each
player grows crops on their own garden plot, sells them, and buys machines that plant,
harvest, process and sell for them, with mining and crafting as a second progression.

## Current state

Work is on the `garden-overhaul` branch, following [docs/overhaul.md](docs/overhaul.md).
Phases 1-4 (foundation, garden loop, automation, crafting) and 6 (polish: onboarding,
effects, sounds, music, balance) are built and playtested. Phase 5 (art) is nearly done;
the quarry's copper rock is still a placeholder. Phase 7 (research, wood and the world) is
built and playtested: research, crafting, the forest map and chopping, tree crops, the level
curve, the industrial machine and conveyor art, the new effects, sounds and music. Since then:
research is a full-screen upgrade tree per category, with info on hover and click, and a
finished timer waits for Complete (with a burst on the tile and the `ResearchComplete` VFX); grass and dirt wear the game's
own textures (`World/GroundLook`); the map is built from parts, not Terrain; and Harvest
sounds like a plant pulled from soil. Research is now one five-fold tree of diamond tiles
round a hub (each category a coloured fan), showing what is in reach plus undiscovered "?" tiles
one step past it, rippling open from the middle and closed from the edge, with requirement cards
in its info and a glow that runs out to each unlock; harvesting plays the `HarvestPop` effect.
Since then: a side Menu opens Achievements, Stats and Settings, and Quests has its own side
button and claimable badge (progress.md); notices are
coloured by kind and stack above the hotbar; the backpack button sits after hotbar slot 9; and the
Crafting window is an Islands-style catalogue (categories, search, cards, a details panel). The
Rock Drill digs quarry materials on your own plot from coal (factory.md). Machines are now
crafted only, at a Crafting Bench with four tiers upgraded with materials (factory.md § Crafting
Bench); blocks have logical display names (the Workbench is the Assembler); and the Machine
Shop is gone, its stall and tab now the Robux Shop's coin packs (economy.md). Chests take items
by hand too, and the Auto Collector (a chest at the Workshop tier) pulls in loose drops near it
(factory.md).

## Domain docs

- [docs/animations.md](docs/animations.md) — client-only placed-block motion, art keys and quality culling.
- [docs/progress.md](docs/progress.md) — lifetime stats, achievements, repeatable quests, rewards and per-garden saving.
- [docs/overhaul.md](docs/overhaul.md) — the target design: plots, coins, crops and mutations, shops, the machine roster, crafting, saving, phases and the decisions taken in each. Where it disagrees with the docs below, it is the target and they describe what is built so far.
- [docs/plots.md](docs/plots.md) — plot layout, sections and ownership, economy APIs, profile loading/saving and offline growth, plus the Studio playtest checklist.
- [docs/farming.md](docs/farming.md) — crops: seeds, soil, growth stages, mutations, weather, hand harvesting, sprinklers and the watering can.
- [docs/research.md](docs/research.md) — projects, saved timers, remotes, bonuses and their gameplay hooks.
- [docs/factory.md](docs/factory.md) — conveyors, routers, machines (Seed Planter, Harvester, processors, Shipping Bin), loose drops, the shared quarry and forest, the Crafting Bench and owner-only interactions.
- [docs/economy.md](docs/economy.md) — seed stock, shops, selling, XP, section prices, hub stalls, the authored garden HUD contract, balance and onboarding.
- [docs/lighting.md](docs/lighting.md) — the lighting look and day/night cycle, the Low/Medium/High quality presets, the saved setting and which pieces live only in the place file.
- [docs/inventory.md](docs/inventory.md) — inventory, hotbar/backpack UI and block placement: the server/client flow and which pieces live only in the place file.
- [conventions.md](conventions.md) — naming, module shape, startup, types, UI and comment rules.

## Repo map

| Path | Holds |
|---|---|
| `src/shared` | Code both sides run: content tables (`World`, `Inventory/Items`, `Factory/Blocks`, `Factory/Products`, `Economy/Shops`, `Research`, `Crafting`, `World/Map`), shared rules (`Build`, `Plot`, `Inventory`), `Remotes` |
| `src/server/services`, `src/client/controllers` | Feature modules, started by `ModuleLoader` from each side's `initialize` script |
| `src/server/libraries`, `src/client/libraries` | Helpers, not auto-started |
| `default.project.json` | The Rojo tree, including every RemoteEvent |
| `assets/sounds`, `assets/music` | Generated audio and its uploaded asset ids (README in each) |
| `tools/balance/model.py` | The balance model (economy.md § Balance) |
| `tools/textures` | The ground textures' generator and the Studio script that puts them on the Grass and Dirt cubes |
| `tools/hud` | The builders that author the Menu, progress windows, Crafting window (and its upgrade panel), Shop and Robux windows, notice look and prompt card in the place file |
| `src/shared/VFX` | `VFXPlayer`, `Layers` and the effects (the `roblox-vfx` skill), copied from the VFX project's runtime |

The place file, `StarterGui.HUD` and `StarterGui.SaveMenu`, `ReplicatedStorage.Assets` (block, item, world, prop and UI
templates) and the `IslandsMachines/` art pipeline live outside git.

## Invariants

- The server decides. Clients send intents through `Shared/Remotes` (each remote's payload
  is documented there) and predict with the same shared rules; the server revalidates
  ownership, reach, DataReady and every item id.
- A player can place, plant, harvest or work machines only on owned sections of their own
  plot (`Shared/Plot`, `Build.owns`/`canEdit`); machines act only inside their own plot.
- Saves are plot-relative, in ProfileStore's `GardenFoundation_v1`; a saved entry that no
  longer checks out is skipped with a warning, never a load failure (plots.md).
- `server/libraries/GardenEvents` is the only announcer of live garden actions; onboarding
  and effects listen to it, and save restoration never fires it.
- Each fact has one owner (a module header or one doc); everything else points to it.

## Checking a change

Sync into Studio with Rojo and playtest there (the `studio-playtest` skill). Formatting
(stylua), linting (selene) and type checks do not replace a playtest. After changing crop,
product, shop or XP numbers, rerun `python tools/balance/model.py` and update economy.md.
