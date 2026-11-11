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
button and claimable badge (progress.md); notices carry
a kind icon or item picture, merge repeats, wrap, open their window when clicked and stack above the
hotbar, with level-ups, achievements and rare seed stock in a top banner (`Shared/Notices`); the backpack button sits after hotbar slot 9; and the
Crafting window is an Islands-style catalogue (categories, search, cards, a details panel). The
Rock Drill digs quarry materials on your own plot from coal (factory.md). Machines are now
crafted only, in the Crafting window opened from its side button (or C) anywhere, with four
tiers upgraded with materials in that window; the Crafting Bench block is gone (factory.md §
Crafting); blocks have logical display names (the Workbench is the Assembler); and the Machine
Shop is gone, its stall and tab now the Robux Shop's coin packs (economy.md), opened from a Menu
row. Stacks have no limit (inventory.md), and a Shipping Bin's sales float up from it as "+coins". A hand-filled Chest,
the Auto Collector (the old Storage Chest, belt-fed, pulling in loose drops near it) and the
Auto Crafter (repeats a picked crafting recipe) are in factory.md.

## Domain docs

- [docs/animations.md](docs/animations.md) — client-only placed-block motion, art keys and quality culling.
- [docs/social.md](docs/social.md) — rare-harvest notices to the server, likes at a garden's sign, capped gifting by walking up to a player (both need the Gifting setting on), the hub leaderboards and the saved social fields.
- [docs/welcome.md](docs/welcome.md) — the daily gift, the welcome-back card and offline coins: what is owed on load, collecting, the bin-rate buckets and the saved fields.
- [docs/progress.md](docs/progress.md) — lifetime stats, achievements, daily quests, orders, rewards and per-garden saving.
- [docs/overhaul.md](docs/overhaul.md) — the target design: plots, coins, crops and mutations, shops, the machine roster, crafting, saving, phases and the decisions taken in each. Where it disagrees with the docs below, it is the target and they describe what is built so far.
- [docs/retention.md](docs/retention.md) — the plan for what comes next, in phases R1-R7: the goal chain (R1, built: 25 goals to the first Mk II machine, then the next level unlock; economy.md § Onboarding), crop and juice retuning with a rare seed stock notice (R2, built), daily quests, orders and raised achievement rewards (R3, built; progress.md), the daily gift, welcome-back card and offline coins (R4, built; welcome.md), the Roaster, Preserving Kettle and Chiller with sixteen chained products and two Recipe Books at levels 13-35 (R5, built; factory.md § Processors), rare-harvest notices, likes, gifting and leaderboards (R6, built; social.md; two-player paths still to test), then the art for all of it (R7: the three machines, the Orders Board and Leaderboards props and the product item models are built from `IslandsMachines/build/garden_kitchen.py`; the timed fresh run to level 20 is still to be played, with a `Pace:` line per level in Studio's output to record it).
- [docs/plots.md](docs/plots.md) — plot layout, sections and ownership, economy APIs, profile loading/saving and offline growth, plus the Studio playtest checklist.
- [docs/farming.md](docs/farming.md) — crops: seeds, soil, growth stages, mutations, weather, hand harvesting, sprinklers and the watering can.
- [docs/research.md](docs/research.md) — projects, saved timers, remotes, bonuses and their gameplay hooks.
- [docs/factory.md](docs/factory.md) — conveyors, routers, machines (Seed Planter, Harvester, processors, Shipping Bin), loose drops, the shared quarry and forest, crafting and owner-only interactions.
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
| `tools/hud` | The builders that author the Menu, progress windows, the Quests window's tabs and order row (`quests_hud`, run after `progress_hud`), the welcome-back card (`welcome_hud`, after those), the Visit card (`visit_hud`, after that), the Settings window's Gifting row (`settings_hud`), Crafting window (and its upgrade panel), Shop and Robux windows, the notice card, banner and kind icons (`notice_hud`, any time), prompt card, and the Crafting side button and Menu's Robux row (`sidebar_hud`, run last) in the place file |
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
product, shop, crafting recipe, quarry or XP numbers, rerun `python tools/balance/model.py` and update economy.md.
