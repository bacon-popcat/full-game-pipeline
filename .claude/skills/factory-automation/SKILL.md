---
name: factory-automation
description: >
  Automation systems: conveyors, routers (split, merge, filter, randomizer, sensor), machines
  with recipes, input and output belts, storage chests, sellers and fluid networks, all run
  from data. Use when adding a machine, recipe, belt type or router, changing how items flow,
  or fixing belts that stop, items that vanish or duplicate, machines that starve, ramps that
  don't connect, or laggy belt items.
---

# Factory automation

Islands-style automation: placed blocks carry items and machines turn them into other items.
Read [docs/factory.md](../../../docs/factory.md) and the headers of `Shared/Factory`,
`Shared/Factory/Lane`, `Shared/Factory/Blocks`, `server/libraries/Machine` and
`FactoryService` before changing anything. On `garden-overhaul` the roster is being replaced
(docs/overhaul.md, Machines), but the engine stays the same.

## The design rules

1. **Blocks are data.** [Shared/Factory/Blocks](../../../src/shared/Factory/Blocks.luau)
   gives each block its lanes, route, ports, recipes (`recipe(inputs, outputs, time)`), fuel
   and world needs. FactoryService runs any entry, so a new machine is a data entry plus art.
2. **Connect by geometry, with no wiring.** Two blocks connect when one's exit and the other's
   entry share a point and face each other. Ports sit on hitbox faces at belt height on the
   conveyor axis, so any conveyor placed against a port connects. Ends face **level**: when
   lane ends faced along their sloped belt, ramps never met flat conveyors.
3. **Items move only on the server, and clients run the same rule.** `Lane.advance` moves items
   front first at the lane speed, keeping `SPACING` between them, and a blocked front item backs
   up the whole lane. The server sends a lane only when an item joins or leaves it; the client
   slides items in between and keeps one model per item `id` across lanes.
4. **Machines never lose items.** A job starts only when its output fits, and capacities are
   small and per item, so a full machine stops and its belt backs up. Nothing disappears into
   a machine.
5. **Look past a blocker.** If the item at a machine's port won't go in (spare fuel full, or not
   accepted), the machine takes the first item queued nose to tail behind it that does, up to
   12 back, over conveyors and through mergers. Without this, surplus coal starved the ore
   behind it.
6. **Items enter and leave at ports.** A face with belt art gets its own lane up to the port
   (`PortDepthBack/Front` on the hitbox). Output rides out on the output belt. An open end
   throws the item off as a physics drop if the cell in front is clear, or waits if it isn't.
7. **Players work machines through the panel only** (`Load`, `Collect`, `TakeBack`). A click
   in the world never feeds or empties a machine. The hand takes items off belts, switches
   splits and toggles filters.
8. **Publish status as attributes** (`Status`, `Fuel`, `Contents`, `Output`, `Progress`,
   `Sold`, `Slots`, `Powered`, `Filter`). `client/libraries/BlockText` turns them into words,
   for both the hover panel and the machine panel.
9. **Producers check the world when a job starts and again when it ends**, so a node removed
   mid-job, such as a tree chopped or a crop already harvested, stops production cleanly.
10. **Fluids are networks, not items.** Tubes join into networks that start empty and fill once
    fluid has moved, and they stay full while a source still feeds them. Tick each source once
    per frame, even when several networks touch it (sap was doubled when it wasn't). Forget
    timers for sources no network reaches.

## Adding things

- **A recipe:** a `recipe(...)` line in the machine's `Blocks` entry. New ingredients and
  products are `Resource` items with art in `Assets.Items`.
- **A machine:** art with conveyor ends on hitbox faces (output belt on every machine that
  makes items), a hitbox from `studio_blocks.luau`, an item, and a `Blocks` entry. Use the
  existing constructors (`processor(...)` and so on) rather than writing a new shape.
- **A storage or seller block:** see the Industrial Chest (`stores = 12`, slots sized by item
  stack, panel with TakeOut / Take all) and the Teleseller (`Sold`). On `garden-overhaul` the
  seller pays the owner through EconomyService.
- **A router:** decide per item at a hub. Mergers pass the look-past queue through; other
  routers stop it.

## Leaks and bugs to check for

- Removing a block clears its pending lane updates, sensor pulses and fluid state.
- Picking up a machine returns inputs, outputs and lane items (`FactoryService.drain`).
- Saved machines (`garden-overhaul`) refund active recipe inputs and restart the job. Lane
  order is rebuilt at legal spacing, and partial progress is not saved.
- Machines, lanes and sensor pulses stay inside their own plot.

## Test in a playtest

Run belts in a straight line, round corners, up and down ramps, and through split, merge, filter
and randomizer. Back a machine up until it is full, overfeed fuel, drop items onto belts, leave
open ends throwing items off, and walk over a belt to pick up items. To get real items onto a
belt from MCP, use the client remotes (mine a rock, move it to slot 1, `DropItem` onto a
belt); see `studio-playtest`.
