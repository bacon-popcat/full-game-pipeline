---
name: player-saves-and-plots
description: >
  Saving player progress and per-player plots: session-locked profiles (ProfileStore), the
  profile template, the load, restore and release order, plot-relative layouts, skipping
  stale entries, versioned stores, autosave, and assigning and freeing plots on a shared
  map. Use when adding saved fields, changing what persists, building tycoon or garden plots,
  fixing data loss, duplication or join kicks, or testing saves.
---

# Player saves and plots

On Roblox, use a session-locking library (ProfileStore) rather than raw DataStore calls. See
`roblox-skills:roblox-data-stores` for the API details.

## Load order

```text
start session -> reconcile with template -> validate
  failure / session lost -> kick, release runtime state
assign plot                 first free plot, owner marker, sign
restore placed blocks       (blocks that crops stand on first), then their contents
restore world state         crops, with growth for the time elapsed
load inventory + economy    -> sync to the client + leaderstats
DataReady = true            only now may the player edit anything
```

Leaving runs the reverse: snapshot the state, clear crops, remove blocks, clear drops,
inventory and economy, release the plot, end the session.

- **Gate every edit on `DataReady`.** Otherwise a player can place something before their
  save lands, and the restore collides with it.
- **Never depend on start order.** Set up a service's state when its module is required, and
  make plot building idempotent, so loading works whichever service started first.

## What to save

- **Plain data only.** Store vectors as number arrays, and keep empty slots as `false`.
- **Save positions relative to the plot's origin,** so a layout loads into whichever plot is
  free. If all plots face the same way, rotations need no transform.
- **Save causes, not results:** XP rather than level, `plantedAt` rather than stage, item
  counts rather than positions on a belt (rebuild those on load).
- **Refund work in progress instead of saving it.** Put a running job's inputs back and
  restart the job on load. Partial progress, timers and loose drops are not saved.
- **Skip what no longer fits; don't kick the player.** An entry whose item has been renamed or
  removed is skipped with a warning, so a content change never locks a player out. Only a
  broken save shape, invalid balances or a full server fail the load, and those release the
  profile **unchanged**.
- **Version the store** (`<Game>_v1`). A breaking schema change gets either a new store name
  or a migration, never a silent reinterpretation of old data.

## Saving

Autosave on a timer (for example every two minutes), from the library's save hook
(including the save on shutdown), and before ending the session. Each save snapshots the
live services; don't keep a second copy of the data that can drift.

## Plots

- One shared module owns plot bounds, origins and the conversion between world and plot
  cells. A plot service owns the runtime props (ground, fences, signs).
- A joining player gets the first free plot, and it is freed when they leave. If the server
  is full, reject the player without touching their save.
- The plot index and owner never come from the client. Every write (place, plant, harvest,
  machine controls, pickups) checks that the whole footprint is inside the player's own plot,
  on both client and server.
- Machines, lanes and drops stay within their own plot, and drops keep their owner.
- Spawn players in a shared hub, not on a plot that might not be assigned yet.

## Testing

Without API access, Roblox Studio needs a mock store (ProfileStore provides one): saves
reload within one server but are gone after Stop. Test:

- joining fresh;
- two players trying to edit each other's plots;
- saving and rejoining into a **different** plot;
- leaving in the middle of a job;
- session locking from a second server, with API access on.

A deliberately invalid save must fail to load without overwriting the original. Lint and
type checks are no substitute for these tests.
