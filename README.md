# Full game pipeline

A calm Roblox farming game: grow crops on your own garden plot, sell them at the hub, and
build conveyors and machines that plant, harvest, process and sell for you. Mining the
shared quarry and crafting parts unlock tier 2 machines.

## Running it

1. Install the tools: [Aftman](https://github.com/LPGhatguy/aftman) pins Rojo
   (`aftman install`); install [Wally](https://github.com/UpliftGames/wally) too.
2. `wally install` fills `Packages/` and `ServerPackages/` (Trove, Signal, ProfileStore).
3. Open the place file in Roblox Studio, run `rojo serve` and connect the Rojo plugin.

The place file and the art pipeline (`IslandsMachines/`) are kept outside git: the HUD,
block, item and prop templates live only in the place. Without Studio API access,
ProfileStore uses its mock store, so saves last only for the current server.

## Where to read next

- [CLAUDE.md](CLAUDE.md): current state, repo map and invariants.
- [docs/](docs): one page per system, starting with [docs/overhaul.md](docs/overhaul.md).
- [conventions.md](conventions.md): code style and structure rules.
