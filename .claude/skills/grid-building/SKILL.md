---
name: grid-building
description: >
  Grid-based building: block templates with whole-cell hitboxes, the placement ghost,
  rotation, reach and overlap tests, picking blocks back up, ownership, and pieces that
  reshape themselves to fit their neighbours (pipes, tubes, rails, fences). Use when adding
  placeable blocks or machines, changing placement rules, fixing blocks that sit off-grid or
  overlap, making connecting pieces join up, or building tycoon, sandbox or survival-style
  building.
---

# Grid building

The world is cut into cells of a fixed size (for example 3 studs). A placeable block fills
whole cells, sits on the floor of its origin cell and turns in quarter turns about the
vertical axis. One shared module holds the grid, footprints, reach and overlap test, and the
client's ghost and the server's check both run it.

## The template contract

Most placement bugs come from a template breaking this contract.

- Each placeable has a template named by its item id.
- **The template's root part is its hitbox**: a box of whole cells. Its size is the
  footprint and its centre is the template's only pivot. A plain cube is its own hitbox; a
  machine has an invisible, queryable, non-colliding `Hitbox` part around its art.
- Art may poke past the hitbox by a small tolerance (for example 0.15). The overlap test
  shrinks boxes by slightly more than that, so neighbours that only touch don't count as
  overlapping.
- **Read the footprint and pivot from the hitbox, never from the bounding box.** Rounding a
  bounding box up shifts off-centre art by half a cell, and connections break.
- A template whose hitbox isn't whole cells should warn and refuse to place. Don't guess.
- Generate hitboxes with a script that also records any metadata the game needs (the
  authored origin, port depths), and rerun it after every art import.

## Placement rules

- **Test the world itself; keep no occupancy map.** A placement is legal when it's within
  reach, nothing queryable overlaps its shrunken box, and its own colliding parts don't clip
  a character. With no map, nothing can fall out of sync when blocks are placed, broken or
  loaded.
- **Test characters against the art, not the box,** so a player standing in an empty corner
  of a machine's cells can still place it. Ask the user whether characters should block
  placement at all.
- **Skip loose physics items by hand.** They collide, so a query filter can't hide them.
  Exclude their folder from every placement query, aim ray and open-end check.
- **The client proposes and the server re-checks.** The client sends a cell, a rotation and
  the axis of the surface it aimed at (`against`). The item always comes from the held slot.
  The server stores the item id, owner, origin, rotation and `against` on the placed object.
- **The ghost uses the shared rules:** green means the server will accept it, red means it
  won't. Keep everything bound to the held item in one cleanup bag (Trove, Maid), and clean
  it the moment the hand changes, so no ghost or key binding is left behind.
- **Aim at hitboxes for placing, at art for describing.** Placing snaps to hitbox faces;
  hover text and the interact key should pass through invisible hitboxes to the art.
- **Ownership:** check that the whole footprint, including its height, is inside the
  player's area. Refuse edits until the player's data has loaded.
- **Picking up:** only the owner can pick a block up. A hammer-type tool takes any block, and
  a cube can also break with the tool its item names. Whatever the block held comes back
  with it.

## Pieces that shape themselves

For pipes, tubes, rails, fences and wires:

1. Make **one item**. Its shapes (straight, corner, vertical, elbow up, elbow down, T) are art
   variants, not items.
2. When it's placed, link first to the block on its `against` side, if that block can take
   another link. Then link to any neighbour whose spare end points at the new piece, up to the
   link limit.
3. The links decide the ends, and the ends pick the art. With one link, the other end is
   straight across from it; with none, both ends run along the way it was placed facing.
4. Swap the art in under the hitbox, rotated to fit. When a piece is removed, reshape the
   neighbours it was linked to.
5. Give every shape the same cross-section, centred in the cell at the same height, so any
   two line up without steps.

## Adding a placeable

1. Build the art inside whole cells, with every connecting end on a cell face (see
   `blender-studio-assets`).
2. Import it, generate its hitbox, and confirm the template's root part is the hitbox.
3. Add the item (`inventory-hotbar`), and its behaviour if it has any (`factory-automation`).
4. Test it in all four rotations, against each face, next to another of itself, while
   standing in its cells, at the edge of reach and at the edge of the player's area.
