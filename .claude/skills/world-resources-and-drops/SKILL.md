---
name: world-resources-and-drops
description: >
  World resources and loose items: mineable rocks and ores, trees, bushes and other nodes that
  respawn, tools that harvest them, wandering animals, and physical item drops that players
  and belts pick up. Use when adding a resource node, quarry, tree or animal, changing tools,
  yields or respawn timers, adding item drops, pickup or despawn, or fixing harvests that lose
  items or drops that block placement.
---

# World resources and drops

Read [docs/factory.md](../../../docs/factory.md) (Loose items, What the hand does) and the
headers of `WorldService`, `DropService`, `Shared/World` and `Shared/World/Layout`. On
`garden-overhaul` most nodes are cut and only the hub quarry (Stone, Coal, Iron and Copper
rocks) and Farmland remain.

## Nodes

- **Content is data.** `Shared/World` lists each node type: the tool it needs, its drops,
  `respawn` and art. `Shared/World/Layout` places them (spots, pens, quarry). Art lives in
  `Assets.World` with a whole-cell hitbox, the same as blocks.
- **Nodes sit on whole cells and are indexed by every cell they cover.** "What's below, near
  or in front of this machine" is a cell lookup, and all of it goes through WorldService, so
  every change to a node happens in one place.
- **Respawn only what the world spawned.** A world node comes back `respawn` seconds after it
  breaks, once its cells are clear. A grown node (a planted sapling's tree, a crop) does not.
- **The right tool for the node**: a Pickaxe for rock, an Axe for trees (cut on
  `garden-overhaul`), an empty hand for bushes and flowers. The client outlines what a press
  would do; the server re-checks the tool, reach and ownership.
- **Check the whole yield first.** Test the whole drop list against a copy of the inventory
  before removing the node. Otherwise mining a multi-item node could drop part of the yield.
- **Shared versus owned**: quarry rocks are shared by everyone, but crops and placed blocks
  belong to their owner.

## Animals

The server moves an animal straight to each destination and publishes the walk as attributes
(`WalkFrom`, `WalkTo`, `WalkStart`, `WalkTime`). Clients animate it (`WorldController`). For
machines, an animal is "near" by where it is heading. Animal art has `CanQuery` off, so it
never blocks a placement or catches an aim ray. For pathfinding NPCs, see
`roblox-skills:roblox-npc-ai`.

## Drops (DropService)

- Loose items are real server physics in `Workspace.Drops`. Players drop one with Q,
  Backspace or D-pad down, and belt or machine ends with nothing in front throw items off.
- Walking into a drop picks it up after a 1 s grace; a drop nobody takes despawns after 5 min.
  A player's own drop on a belt can't be walked back up by them for 1.5 s, while anyone else
  can take it at once.
- A drop over a belt joins that lane if there is room. One over a machine's input end goes in
  if the machine takes it. FactoryService registers those rules with `DropService.setBelts`,
  so the two services never require each other.
- **Drops collide, so `CanQuery` can't hide them.** Placement, the aim and open-end checks skip
  `Workspace.Drops` by hand (`Build.isLoose`, `Aim.cast`). Any new spatial query must do the
  same, or drops will block it.
- On `garden-overhaul`, drops keep their owner's id, other plots can't take them, and they are
  cleared when the owner leaves. They are never saved.

## Adding a node type

1. Model the art with the pipeline (`blender-studio-assets`), with soft shapes and light
   colours.
2. Add an entry in `Shared/World` and placements in `World/Layout`, inside the baseplate's
   ±256 studs.
3. Give its drops items in `Inventory/Items` with art in `Assets.Items`.
4. If a machine harvests it, add it to the producer's `Blocks` entry (`sources`, `radius`).
5. Playtest: mine it with a full inventory, mine it with the wrong tool, watch it respawn
   while a player stands in its cells, and run a machine on it while it is mined by hand.
