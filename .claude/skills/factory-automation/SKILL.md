---
name: factory-automation
description: >
  Automation systems: conveyors, routers (split, merge, filter, randomizer, sensor), machines
  with recipes, input and output belts, storage, sellers and fluid networks, all driven by
  data. Use when adding a machine, recipe, belt or router, changing how items flow, or fixing
  belts that stop, items that vanish or duplicate, starving machines, ramps that won't
  connect, or laggy items on belts.
---

# Factory automation

Placed blocks carry items, and machines turn them into other items. This works with
`grid-building` (placement and hitboxes) and `server-authority` (sync).

## Design rules

1. **Blocks are data.** One content module gives each block its lanes, route, ports, recipes
   (`recipe(inputs, outputs, seconds)`), fuel and world needs, built with a few constructors
   (`conveyor`, `router`, `processor`, `producer`, `storage`). The simulation runs any
   entry, so a new machine is a data entry plus art.
2. **Connect blocks by geometry, with no wiring.** Two blocks connect when one's exit and the
   other's entry share a point and face each other. Put ports on hitbox faces, at belt
   height, on the conveyor's axis, so any conveyor placed against a port connects. Make every
   end face **level**: if a ramp's ends face along its slope, it will never meet a flat belt.
3. **Move items only on the server, and run the same rule on clients.** A lane keeps its
   items front first. Each moves at the lane's speed until it reaches the end or closes to
   `SPACING` behind the item ahead, so a blocked front item backs up the whole lane. Send a
   lane's item list only when an item joins or leaves it, stamped with server time. Clients
   slide the items in between and keep one model per item id across lanes, so items never
   jump.
4. **Machines never lose items.** Start a job only when its output fits, and keep capacities
   small and per item. A full machine stops and its belt backs up; nothing vanishes into it.
5. **Look past a blocker.** When the item at a port won't go in (its fuel is full, or the
   machine never takes that item), take the first item queued nose to tail behind it that
   does, up to a limit. Without this, spare fuel on a belt starves the machine of ore.
6. **Items enter and leave at ports.** A face with belt art gets a short lane of its own up to
   the port. Output rides out on an output belt. At an open end, throw the item off as a
   loose drop if the space in front is clear; otherwise it waits, like at any blocked end.
7. **Pick one way to work machines.** For example, the panel only (load, collect, take back),
   with world clicks doing nothing to machines. Mixing panel and world clicks leads to items
   being loaded by accident.
8. **Publish status on the block** (status, fuel, contents, output, progress), and word it
   through one formatter, so the hover text and the panel always agree. Say *why* a machine
   is idle ("Waiting for coal", "Output full").
9. **Producers check the world when a job starts and again when it ends,** so a node that
   disappears mid-job (a tree chopped, a crop harvested by hand) stops production cleanly.
10. **Fluids are networks, not items.** Pipes join into networks. A network starts empty,
    fills once fluid has moved, and stays full while a source still feeds it. Tick each
    source once per frame even when several networks touch it, and drop any timers for
    sources no network reaches.

## Adding things

- **A recipe:** one line in the machine's entry. New ingredients and products are items with
  art.
- **A machine:** art whose conveyor ends sit on hitbox faces (with an output belt on every
  machine that makes items), a hitbox, an item, and a data entry using an existing
  constructor.
- **Storage:** N slots, each holding up to that item's stack size. It backs up its belt when
  full, and its panel has take-one and take-all.
- **A seller:** pays the block's **owner**, never whoever fed it.
- **A router:** it decides per item at a hub. Mergers pass the look-past queue through;
  routers that decide stop it.

## Leaks and bugs to check for

- Removing a block clears its pending lane updates, its timers and its fluid state.
- Picking up a machine returns its inputs, outputs and lane items to the owner.
- Saving a machine: refund the inputs of any job in progress and restart the job. Save lanes
  as item counts and rebuild their spacing on load.
- Machines and lanes never reach into another player's area.

## Playtest

Test straight runs, corners, ramps up and down, and every router. Back a machine up, overfeed
it fuel, drop items onto belts, leave open ends throwing items off, walk over a belt to pick
items up, and run a long line for a while to watch the server's frame time.
