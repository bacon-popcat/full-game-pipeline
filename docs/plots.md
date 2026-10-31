# Plots, economy and saving

Foundation gives each loaded profile a private garden on the shared map. Each module's
header owns its rules; this page maps initialization, permissions and persistence.

## Flow

```text
DataService -> ProfileStore.StartSessionAsync -> reconcile/validate
                 | failure / session lost -> kick, release runtime state
                 v
PlotService.assign -> first free plot, saved Expansion + Owner attributes, display-name sign
                 v
BuildService.restore -> FactoryService.register/restore -> lanes and machines
WorldService.restore -> crops, elapsed wall-clock growth
InventoryService.load + EconomyService.load + GardenService.load -> sync + leaderstats
                 v
OnboardingService.load -> restored conditions + Objective sync
                 v
             DataReady = true

ProfileStore OnSave / two-minute snapshot / leave
    <- inventory slots + economy + garden stock/discoveries + onboarding + expansion + relative blocks, factory contents, crops
leave -> clear crops -> unregister/remove blocks -> clear drops/inventory/economy
      -> release plot -> ProfileStore.EndSession
```

State is established at require time. Assignment builds plots idempotently even if
PlotService.init has not run. Placement registers factories synchronously; a later
ChildAdded notification or init scan is harmless. No load assumes a sibling init ran.

## Layout and ownership

- `Shared/Plot` owns expansion tiers/prices, bounds, origins and cell conversions. All plots face -Z so saved
  crops still have Farmland beneath them when moved between map rows. PlotService owns
  the runtime grass, soft non-colliding fences, signs and farm dimensions.
- Models are `Workspace.Plots["1"]` through `["6"]`; `Owner` is a user id or zero when
  free. `Expansion` is the saved tier, 0..3, replicated to every client. A full server
  rejects a seventh loaded profile without changing its save.
- Every garden starts at 30 x 30 cells (90 x 90 studs), up from 24 x 24. The maximum is
  48 x 48 cells (144 x 144 studs). Origins are x = -78, -24, 30 and z = -74, 24 cells,
  indexed left-to-right across the north row, then the south row. At maximum the plots
  span x [-78,-30), [-24,24), [30,78), z [-74,-26), [24,72): six-cell column gaps,
  a fifty-cell hub corridor, and all edges inside the existing +/-256-stud baseplate.
- Farms contain twelve by eight Farmland nodes at relative x 6..17, z 2..9, y 0.
  Crops plant above them; the rest is open grass. Players spawn at the hub. The hub
  quarry contains shared Stone, Coal, Iron and Copper rocks.
- `Build.owns` checks the complete footprint and height; `Build.canEdit` additionally
  requires `DataReady`. Block cells must remain at y 0..79. Placement, harvest, machine
  controls and belt pickup are owner-only, on the server and client.
- Machines, lane connections and sensor pulses stay inside their own plot. Drops keep
  their owner's id and cannot be picked up or absorbed by another player's plot.
- `Plot.at` returns only occupied, purchased bounds; `contains` and `same` use that same
  check. Missing plot/owner replication fails closed. `Build.owns`/`canEdit`, crop restoration
  and machine area/connection checks therefore reject locked cells on both server and client.
- Plot indices and owners never come from client requests. Placement uses the held slot;
  interactions validate target ancestry, reach, ownership and supplied item ids.
- PlotService removes the live showcase. Place-file source assets remain untouched.

## Buying space

`Plot.EXPANSIONS` owns the three sequential coin purchases; the price/area table and balance
rationale are in [economy.md](economy.md#plot-expansions). No level gate or inventory item is
required. Extra space is grass for building or player-placed soil; the starter farm stays
twelve by eight. The muted grey-green ground beyond the fence is locked; the bright grass
and fence grow toward +X/+Z with each purchase. Maximum plots have no locked ground left.

The plot sign's `ExpansionSign.ExpandPlot` ProximityPrompt opens `HUD.Expansion`, a runtime
clone of the existing Sell shell. UIController prepares the clone before any screens start,
preserving authored styling. It displays current/next dimensions, added cells and coin price,
with Buy expansion and Cancel. HubWindow supplies close/B, modal exclusivity, reduced motion,
gamepad focus and close-on-death/walking-away. No new Studio UI or prop authoring is required
when the existing Sell HUD contract is present; missing nodes warn and skip the window.

`PlotExpand(nextTier)` sends only the expected next tier. PlotService derives ownership from
its assignment, requires DataReady and a living owner within 12 studs of the sign, enforces
a 0.5-second cooldown, rejects stale/skipped/non-number tiers and checks coins through
EconomyService.trySpend. Spending and publishing the tier do not yield. Repeated requests for
the same tier cannot spend twice. Success sends Notify and GardenEvents.Expanded (the normal
purchase sound); restored tiers never fire purchase effects or onboarding rewards. A response
or two-second timeout releases the UI's pending state. Scenery refresh leaves soil, crops,
machine contents and existing builds intact. Release resets the free plot to tier zero.

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
| plot.expansion | Purchased tier 0..3; applied before restoring any blocks/crops |
| plot.blocks | Item id, relative cell, rotation, Against, factory contents |
| factory contents | Separate input/output counts, counts per lane, remaining coal burn time, Sold, filter (items sent left), optional filterRight (items sent right) and filterMutations ("Left:Golden"), manual Split switch |
| plot.crops | Crop id, relative cell, current cycle wall-clock plantedAt, harvestCount, optional mutation, mutationRolled and growthBonus |
| seedStock | Remaining seed counts for this player in the current shop window |
| restockAt | Next five-minute Unix boundary; stock is reused only while it matches |
| discovered | Crop id to boolean, marked by a successful hand or machine harvest |
| onboarding | Next objective, integer 1..#Onboarding.STEPS+1; the last value means finished |

Vectors serialize as three-number arrays. Rotation and Against keep world axes because
all plots have the same orientation. Blocks restore before crops so placed soil exists
first. A saved stack, block, crop or machine's contents that no longer checks out (an item
renamed or cut since it was saved, a missing template) is skipped with a warning, so a content
change never locks a player out. Only bad balances, a broken save shape or a full server fail
loading, and those keep the original profile.

The larger layout keeps `GardenFoundation_v1`. Reconcile defaults old `plot.expansion` to
zero; `Plot.sanitize` floors/clamps finite values to 0..3 and resets missing/non-numeric,
NaN and infinite values to zero. Snapshots store the live tier together with spent coins.
No coordinate migration is needed: relative (0,0,0) is still the minimum corner, expansion
never moves that corner, and Farmland remains at relative x 6..17, z 2..9, y 0. Every old
24 x 24 saved cell fits the new 30 x 30 starter area. Moving a whole garden to a new map
origin translates its saved blocks, crops and starter soil together, with no rotation.

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
8. At each tier, test the last owned cell, the first locked cell, a rotated footprint crossing
   the fence, planting on placed soil and planter/harvester/sprinkler reach across the edge.
   The next tier must become usable immediately by both ghost and server. Max plots must
   remain separated and clear of stalls, quarry and spawn.
9. Buy all three tiers from the sign: insufficient funds, exact funds, stale/double requests,
   skipped/negative/fractional/NaN/infinite/string tiers, remote spam, another owner's sign,
   out-of-range, dead and pre-DataReady requests. Only one correct price is charged per tier.
   Inspect the panel on desktop/mobile/gamepad, Cancel/B, walking away, max tier and late HUD.
10. Load an old save with crops on every starter-soil edge, then buy, build/plant at relative
    (47,47), and rejoin on the opposite row. Check unchanged farm alignment, expanded contents,
    saved coins/tier, release/reassignment and malformed/missing tier defaults.

Local formatter, lint and type checks do not substitute for these runtime checks.

## Plot and hub props

PlotService fences each plot with one `PlotFence` prop per edge cell, a `PlotFencePost` at each
corner and either side of the fixed two-cell gate at the starter front, and stands the
`PlotSign` outside the fence beside the gate; the owner's name is a SurfaceGui on the sign's
`Board` part. HubService stands each stall prop (named for its stall) turned to face the
spawn, parents its ProximityPrompt to the stall's `Counter` part, and lays a paved plaza with
`HubLamp` and `HubFlowerBox` props. `server/libraries/Props` places them all as scenery (no
collisions, queries or touches). The props come from `IslandsMachines/build/garden_props.py`
into `ReplicatedStorage.Assets.Props`; without them both services build plain parts.
