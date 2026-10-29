---
name: world-resources-and-drops
description: >
  World resources and loose items: mineable rocks and ores, trees, bushes and other nodes
  that respawn, the tools that harvest them, wandering animals, and physical item drops that
  players and belts pick up. Use when adding a resource node, quarry, tree or animal,
  changing tools, yields or respawn timers, adding item drops, pickup or despawn, or fixing
  harvests that lose items or drops that block placement.
---

# World resources and drops

## Nodes

- **Content is data.** One module lists each node type: the tool it needs, its drops, its
  `respawn` time and its art. A separate layout module places the nodes. Node art has a
  whole-cell hitbox, the same as blocks (`grid-building`).
- **Nodes sit on whole cells and are indexed by every cell they cover.** "What is under, near
  or in front of this machine?" is then a cell lookup. Every change to a node goes through
  one service.
- **Only nodes the world spawned respawn.** A world node comes back `respawn` seconds after it
  breaks, once its cells are clear. Anything a player grew (a planted tree, a crop) does not
  come back.
- **The right tool for each node:** a pickaxe for rock, an axe for trees, an empty hand for
  bushes. The client highlights what a press would do; the server re-checks the tool, reach
  and ownership.
- **Check the whole yield first.** Test all of a node's drops against a copy of the inventory
  before removing the node. Otherwise a node with several drops can lose part of its yield.
- **Shared or owned.** Decide for each area whether its nodes are shared (a public quarry) or
  belong to the player who owns the area.

## Animals and simple movers

The server moves the animal straight toward each destination and publishes the walk (from,
to, start time, duration); clients animate it. For game logic, the animal is wherever it is
heading. Turn off its art's hit-testing (`CanQuery` on Roblox), so it never blocks a placement
or catches an aim ray. For NPCs that pathfind, see `roblox-skills:roblox-npc-ai`.

## Loose drops

- Drops are real physics objects, simulated by the server, in one folder. Players drop items
  with a key, and belt or machine ends with nothing in front throw items off.
- A player picks a drop up by walking into it, after a short grace period (about 1 s). A drop
  nobody takes despawns after a few minutes.
- Give the dropper a slightly longer grace before they can pick their own drop back up, so
  dropping onto a belt doesn't snap straight back. Anyone else can take it at once.
- A drop that lands on a belt joins the belt if there's room. One that lands on a machine's
  input goes in if the machine accepts it. The factory registers these rules with the drop
  service (`setBelts(...)`), so neither service requires the other.
- **Drops collide, so a query filter can't hide them.** Every placement query, aim ray and
  open-end check must skip the drops folder by hand.
- Drops keep their owner. Other players' areas can't absorb them, they are cleared when the
  owner leaves, and they are never saved.

## Adding a node type

1. Make the art (`blender-studio-assets`).
2. Add a content entry and place it in the layout, inside the playable bounds.
3. Give each drop an item with art.
4. If a machine harvests it, add it to that machine's sources.
5. Playtest: mine it with a full inventory and with the wrong tool, wait for it to respawn
   while a player stands in its cells, and let a machine work it while a player mines it by
   hand.
