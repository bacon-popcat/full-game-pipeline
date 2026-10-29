# Plots, economy and saving

Foundation gives each loaded profile a private garden on the shared map. Each module's
header owns its rules; this page maps initialization, permissions and persistence.

## Flow

```text
DataService -> ProfileStore.StartSessionAsync -> reconcile/validate
                 | failure / session lost -> kick, release runtime state
                 v
PlotService.assign -> first free plot, Owner attribute, display-name sign
                 v
BuildService.restore -> FactoryService.register/restore -> lanes and machines
WorldService.restore -> crops, elapsed wall-clock growth
InventoryService.load + EconomyService.load + GardenService.load -> sync + leaderstats
                 v
             DataReady = true

ProfileStore OnSave / two-minute snapshot / leave
    <- inventory slots + economy + garden stock/discoveries + relative blocks, factory contents, crops
leave -> clear crops -> unregister/remove blocks -> clear drops/inventory/economy
      -> release plot -> ProfileStore.EndSession
```

State is established at require time. Assignment builds plots idempotently even if
PlotService.init has not run. Placement registers factories synchronously; a later
ChildAdded notification or init scan is harmless. No load assumes a sibling init ran.

## Layout and ownership

- `Shared/Plot` owns bounds, origins and cell conversions. All plots face -Z so saved
  crops still have Farmland beneath them when moved between map rows. PlotService owns
  the runtime grass, soft non-colliding fences, signs and farm dimensions.
- Models are `Workspace.Plots["1"]` through `["6"]`; `Owner` is a user id or zero when
  free. A full server rejects a seventh loaded profile without changing its save.
- Farms contain twelve by eight Farmland nodes at relative x 6..17, z 2..9, y 0.
  Crops plant above them; the rest is open grass. Players spawn at the hub. The hub
  quarry contains shared Stone, Coal, Iron and Copper rocks.
- `Build.owns` checks the complete footprint and height; `Build.canEdit` additionally
  requires `DataReady`. Block cells must remain at y 0..79. Placement, harvest, machine
  controls and belt pickup are owner-only, on the server and client.
- Machines, lane connections and sensor pulses stay inside their own plot. Drops keep
  their owner's id and cannot be picked up or absorbed by another player's plot.
- Plot indices and owners never come from client requests. Placement uses the held slot;
  interactions validate target ancestry, reach, ownership and supplied item ids.
- PlotService removes the live showcase. Place-file source assets remain untouched.

## Economy

`EconomyService` exposes `get`, `add`, `trySpend` and `addXp`. Mutators reject negative,
non-integer and non-finite amounts. Overspending fails without changing the balance;
`get` returns a copy. Coins and Level appear in `leaderstats`; `EconomySync` sends
`{coins, xp, level}` on load and changes. There is no inbound balance remote.

`Shared/Economy` owns level math: XP is lifetime XP, starting at level one. Advancing
from level n costs the design's rounded formula. `progress` returns level, progress
into that level and its cost. Level is derived, not independently saved. GardenService
awards harvest/sale XP and handles stock and selling; the HUD binds EconomyClient.
See [economy.md](economy.md).

DataService owns the fresh profile's 50 coins, zero XP, Hammer, Pickaxe, ten Carrot
Seeds and five Wheat Seeds. The old full test kit is gone. Seeds are bought at the hub;
until the Machine Shop arrives, automation playtests can grant machines through the
server's InventoryService.give API. Selected hotbar slot resets to one on load.

## Profile contents

DataService owns the template in `GardenFoundation_v1`. ProfileStore comes from the
installed ServerStorage package; its normal session lock and EndSession API are used.

| Field | Stored data |
|---|---|
| coins, xp | Live balances; level is derived |
| inventory | Dense slots, including `false` for empty slots |
| plot.blocks | Item id, relative cell, rotation, Against, factory contents |
| factory contents | Separate input/output counts, counts per lane, remaining coal burn time, Sold, filter, manual Split switch |
| plot.crops | Crop id, relative cell, current cycle wall-clock plantedAt, harvestCount, optional mutation, mutationRolled and growthBonus |
| seedStock | Remaining seed counts for this player in the current shop window |
| restockAt | Next five-minute Unix boundary; stock is reused only while it matches |
| discovered | Crop id to boolean, marked by a successful hand or machine harvest |

Vectors serialize as three-number arrays. Rotation and Against keep world axes because
all plots have the same orientation. Blocks restore before crops so placed soil exists
first. A saved stack, block, crop or machine's contents that no longer checks out (an item
renamed or cut since it was saved, a missing template) is skipped with a warning, so a content
change never locks a player out. Only bad balances, a broken save shape or a full server fail
loading, and those keep the original profile.

Active recipe ingredients are refunded into saved input counts and processing restarts
after loading. Partial job progress and sensor pulses do not persist. Stored fuel time,
outputs, router settings and lane counts persist; lane ordering/positions are reconstructed
at legal spacing. Loose drops are not saved and are cleared on departure. Only crops grow
offline. Current timing, multi regrowth and weather credit are in [farming.md](farming.md).
Old crops default missing growthBonus to zero and mutationRolled to false (or true when
a mutation is already stored); the profile store stays unchanged.

ProfileStore's autosave period is configured to two minutes. DataService also refreshes
the snapshot every two minutes, before leave, and from OnSave (including ProfileStore's
shutdown save). Session loss disables edits and clears the plot. The installed package
automatically uses its mock store without Studio API access: mock saves can reload in
the same server but do not survive Studio Stop.

## Studio playtest

1. Join fresh: check the starter kit, 50 Coins, Level 1, hub spawn, owner sign and 96
   Farmland cells per plot. With API access off, expect the mock-store warning.
2. Use two players: test full-footprint boundary ghosts, planting, Hammer/Pickaxe pickup,
   harvest, machine panels, belt pickup and aimed drops on another plot. All writes must
   fail there; both players can mine every quarry rock, including Copper.
3. Place rotated machines and cubes, load a chest, queue belts, configure a Filter/Split,
   start a recipe and plant on both Farmland and placed Dirt. Save and rejoin into another
   plot. Verify contents, rotations, Against, offline crop stages and Next stage countdown.
4. Break planted soil and collect owned drops. Leave with loaded machines and crops;
   verify cleanup produces no duplicate harvest and the plot can be reassigned.
5. Test planter/picker near boundaries, smelter coal, fuel-free processors, all conveyor
   and router variants, chest Take all and the Teleseller's Sold counter.
6. Exercise EconomyService on the server: overspend, add coins, add XP across a level
   boundary, then rejoin and verify balances and the wallet. Continue with the Garden loop
   checklist in [economy.md](economy.md#studio-verification-still-required).
7. With API access enabled in a test place, verify persistence across Stop/new server,
   shutdown during processing, and session locking from a second server. A deliberately
   invalid saved item should fail loading without replacing the original layout.

Local formatter, lint and type checks do not substitute for these runtime checks.

## Plot and hub props

PlotService fences each plot with one `PlotFence` prop per edge cell, a `PlotFencePost` at each
corner and either side of the two-cell gate in the middle of the front, and stands the
`PlotSign` outside the fence beside the gate; the owner's name is a SurfaceGui on the sign's
`Board` part. HubService stands each stall prop (named for its stall) turned to face the
spawn, parents its ProximityPrompt to the stall's `Counter` part, and lays a paved plaza with
`HubLamp` and `HubFlowerBox` props. `server/libraries/Props` places them all as scenery (no
collisions, queries or touches). The props come from `IslandsMachines/build/garden_props.py`
into `ReplicatedStorage.Assets.Props`; without them both services build plain parts.
