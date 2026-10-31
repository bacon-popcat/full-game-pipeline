# Plots, economy and saving

Foundation gives each loaded profile a private garden on the shared map. Each module's
header owns its rules; this page maps initialization, permissions and persistence.

## Flow

```text
DataService -> ProfileStore.StartSessionAsync -> reconcile/validate
                 | failure / session lost -> kick, release runtime state
                 v
PlotService.assign -> first free plot, saved Sections + Owner attributes, display-name sign
                 v
BuildService.restore -> FactoryService.register/restore -> lanes and machines
WorldService.restore -> crops, elapsed wall-clock growth
InventoryService.load + EconomyService.load + GardenService.load -> sync + leaderstats
                 v
OnboardingService.load -> restored conditions + Objective sync
                 v
             DataReady = true

ProfileStore OnSave / two-minute snapshot / leave
    <- inventory slots + economy + garden stock/discoveries + onboarding + sections + relative blocks, factory contents, crops
leave -> clear crops -> unregister/remove blocks -> clear drops/inventory/economy
      -> release plot -> ProfileStore.EndSession
```

State is established at require time. Assignment builds plots idempotently even if
PlotService.init has not run. Placement registers factories synchronously; a later
ChildAdded notification or init scan is harmless. No load assumes a sibling init ran.

## Layout and ownership

- `Shared/Plot` owns the section grid and prices, origins and cell conversions. All plots face
  -Z so saved crops still have Farmland beneath them when moved between map rows. PlotService
  owns the runtime ground tiles, price labels, soft non-colliding fences, signs and farm.
- Models are `Workspace.Plots["1"]` through `["6"]`; `Owner` is a user id or zero when
  free, and `Sections` lists the bought sections ("x,z;x,z"), replicated to every client. A
  full server rejects a seventh loaded profile without changing its save.
- Each garden is 7 x 6 sections of 10 x 10 cells: 70 x 60 cells (210 x 180 studs). Section
  column x, row z covers relative cells from x*10, z*10; row 0 is the front (-Z). The start
  block, columns 2..4 and rows 0..2 (30 x 30 cells, relative x 20..49, z 0..29), is everyone's
  from the start. Origins are x = -115, -35, 45 and z = -76, 16 cells (10-cell gaps), indexed
  across the south row, then the north row; the hub and quarry sit between the rows.
  PlotService widens the place's Baseplate (its top unchanged) to cover them all plus 36 studs.
- Farms contain twelve by eight Farmland nodes at relative x 26..37, z 2..9, y 0 (in the start block).
  Crops plant above them; the rest is open grass. Players spawn at the hub. The hub
  quarry contains shared Stone, Coal, Iron and Copper rocks.
- `Build.owns` checks the complete footprint and height; `Build.canEdit` additionally
  requires `DataReady`. Block cells must remain at y 0..79. Placement, harvest, machine
  controls and belt pickup are owner-only, on the server and client.
- Machines, lane connections and sensor pulses stay inside their own plot. Drops keep
  their owner's id and cannot be picked up or absorbed by another player's plot.
- `Plot.at` returns a plot only for a cell in a section that an owned plot owns; `contains`
  checks every cell of a footprint (sections can leave notches) and `same` uses `at`. It reads
  Owner and Sections every call and re-parses Sections only when it changes, so a purchase or
  an assignment counts in the same frame. Missing plot/owner replication fails closed. `Build.owns`/`canEdit`, crop restoration
  and machine area/connection checks therefore reject locked cells on both server and client.
- Plot indices and owners never come from client requests. Placement uses the held slot;
  interactions validate target ancestry, reach, ownership and supplied item ids.
- PlotService removes the live showcase. Place-file source assets remain untouched.

## Buying space

A locked section can be bought once it shares an edge with owned land, for the price of its
ring, its distance in sections from the start block: 2,500, 20,000 or 100,000 coins
([economy.md](economy.md#garden-sections)). No level gate or item is required. Every locked
section shows its price lying on its ground, turned to read upright from the hub; the ones
that can be bought now are bright, the rest dimmed. Locked ground is a muted grey-green, owned
ground bright grass, and the fence follows the owned land's outline, whatever its shape, with
the two-cell gate at the start block's front.

Each buyable section has a `BuySection` ProximityPrompt at its centre (hold 0.6 s) carrying
its SectionX and SectionZ. PlotService builds them disabled and `PlotController` enables the
ones on the local player's own garden, so nobody else sees them; holding one sends
`PlotBuySection(x, z)`. PlotService derives the plot from its assignment and requires
DataReady, a 0.5-second cooldown, whole in-grid coordinates, a locked section touching owned
land, the character within 30 studs of its centre and coins through EconomyService.trySpend.
Spending and publishing the section do not yield, so a repeated request cannot buy twice.
Success sends Notify and GardenEvents.SectionBought (the purchase sound), then rebuilds only
the scenery, never soil, crops or machines. Release clears the sections of the freed plot.

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
| plot.sections | Bought sections as "x,z" (the start block is implicit); applied before restoring blocks/crops |
| plot.blocks | Item id, relative cell, rotation, Against, factory contents |
| factory contents | Separate input/output counts, counts per lane, remaining coal burn time, Sold, filter (items sent left), optional filterRight (items sent right) and filterMutations ("Left:Golden"), manual Split switch |
| plot.crops | Crop id, relative cell, current cycle wall-clock plantedAt, harvestCount, optional mutation, mutationRolled and growthBonus |
| seedStock | Remaining seed counts for this player in the current shop window |
| restockAt | Next five-minute Unix boundary; stock is reused only while it matches |
| discovered | Crop id to boolean, marked by a successful hand or machine harvest |
| onboarding | Next objective, integer 1..#Onboarding.STEPS+1; the last value means finished |
| plotLayout | 2 once the save's cells are laid out in sections (below); not in the template |

Vectors serialize as three-number arrays. Rotation and Against keep world axes because
all plots have the same orientation. Blocks restore before crops so placed soil exists
first. A saved stack, block, crop or machine's contents that no longer checks out (an item
renamed or cut since it was saved, a missing template) is skipped with a warning, so a content
change never locks a player out. Only bad balances, a broken save shape or a full server fail
loading, and those keep the original profile.

The section layout keeps `GardenFoundation_v1`. A save without `plotLayout = 2` was laid out
from the corner of the old square garden, which is now the start block's corner, so
DataService moves every saved block and crop cell by `Plot.START_OFFSET` (+20 relative X)
once, turns an old sign tier (36/42/48 cells) into the sections that covered it, drops
`plot.expansion` and sets `plotLayout`. The key is kept out of the template on purpose:
Reconcile would otherwise fill it in on old saves and skip the move. Sections load through
`Plot.decode`, which drops anything that is not a whole, in-grid, non-start section. Moving a
whole garden to a new map origin translates its blocks, crops and starter soil together.

Active recipe ingredients are refunded into saved input counts and processing restarts
after loading. Partial job progress and sensor pulses do not persist. Stored fuel time,
outputs, router settings and lane counts persist; lane ordering/positions are reconstructed
at legal spacing. Loose drops are not saved and are cleared on departure. Only crops grow
offline. Current timing, multi regrowth and weather credit are in [farming.md](farming.md).
Old crops default missing growthBonus to zero and mutationRolled to false (or true when
a mutation is already stored); the profile store stays unchanged.

Onboarding defaults to 1 through Reconcile for existing saves. `Shared/Onboarding.sanitize`
floors and clamps finite numbers to the valid step range, and resets non-numbers, NaN and
infinities to 1. It loads after all restored state is available, snapshots alongside reward
coins, and releases before economy cleanup. The service remembers actions ahead of the
current prompt for this session; only the next step is persisted. Restored crops, discoveries,
level and Shipping Bin ownership provide durable evidence for already-satisfied steps.
See [economy.md](economy.md#onboarding) for objectives and the HUD contract.

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
8. Buy sections in several directions: the last owned cell, the first locked cell, a rotated
   footprint across a notch, planting on placed soil, and planter/harvester/sprinkler areas
   across a section edge. A bought section must be usable at once by ghost and server, its
   fence and prompts must move, and another player must see no prompts. Try a non-adjacent,
   owned, out-of-range and fractional section, too few coins and remote spam.
9. Load an old (pre-section) save: blocks and crops must land in the start block on the same
   farmland, once; rejoin and check they do not move again.

Local formatter, lint and type checks do not substitute for these runtime checks.

## Plot and hub props

PlotService fences the owned land with one `PlotFence` prop per edge cell and a `PlotFencePost`
at every corner of the fence, leaving the two-cell gate at the start block's front, and stands the
`PlotSign` outside the fence beside the gate; the owner's name is a SurfaceGui on the sign's
`Board` part. HubService stands each stall prop (named for its stall) turned to face the
spawn, parents its ProximityPrompt to the stall's `Counter` part, and lays a paved plaza with
`HubLamp` and `HubFlowerBox` props. `server/libraries/Props` places them all as scenery (no
collisions, queries or touches). The props come from `IslandsMachines/build/garden_props.py`
into `ReplicatedStorage.Assets.Props`; without them both services build plain parts.
