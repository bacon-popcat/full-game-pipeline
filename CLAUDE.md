# Full game pipeline

A calm Roblox farming game in the spirit of Grow a Garden, with factory automation: each
player grows crops on their own garden plot, sells them, and buys machines that plant,
harvest, process and sell for them, with mining and crafting as a second progression.

## Current state

Work is on the `garden-overhaul` branch, following [docs/overhaul.md](docs/overhaul.md).
Phases 1-4 (foundation, garden loop, automation, crafting) and 6 (polish: onboarding,
effects, sounds, music, balance) are built and playtested. Phase 5 (art) is nearly done;
the quarry's copper rock is still a placeholder.

## Domain docs

- [docs/overhaul.md](docs/overhaul.md) — the target design: plots, coins, crops and mutations, shops, the machine roster, crafting, saving, phases and the decisions taken in each. Where it disagrees with the docs below, it is the target and they describe what is built so far.
- [docs/plots.md](docs/plots.md) — plot layout, sections and ownership, economy APIs, profile loading/saving and offline growth, plus the Studio playtest checklist.
- [docs/farming.md](docs/farming.md) — crops: seeds, soil, growth stages, mutations, weather, hand harvesting, sprinklers and the watering can.
- [docs/factory.md](docs/factory.md) — conveyors, routers, machines (Seed Planter, Harvester, processors, Shipping Bin), loose drops, the shared quarry and owner-only interactions.
- [docs/economy.md](docs/economy.md) — seed stock, shops, selling, XP, section prices, hub stalls, the authored garden HUD contract, balance and onboarding.
- [docs/inventory.md](docs/inventory.md) — inventory, hotbar/backpack UI and block placement: the server/client flow and which pieces live only in the place file.
- [conventions.md](conventions.md) — naming, module shape, startup, types, UI and comment rules.

## Repo map

| Path | Holds |
|---|---|
| `src/shared` | Code both sides run: content tables (`World`, `Inventory/Items`, `Factory/Blocks`, `Factory/Products`, `Economy/Shops`), shared rules (`Build`, `Plot`, `Inventory`), `Remotes` |
| `src/server/services`, `src/client/controllers` | Feature modules, started by `ModuleLoader` from each side's `initialize` script |
| `src/server/libraries`, `src/client/libraries` | Helpers, not auto-started |
| `default.project.json` | The Rojo tree, including every RemoteEvent |
| `assets/sounds`, `assets/music` | Generated audio and its uploaded asset ids (README in each) |
| `tools/balance/model.py` | The balance model (economy.md § Balance) |

The place file, `StarterGui.HUD`, `ReplicatedStorage.Assets` (block, item, world, prop and UI
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
