# Plots, economy and saving

Foundation gives each loaded profile a private garden on the shared map. Each module's
header owns its rules; this page maps initialization, permissions and persistence.

## Flow

```text
join -> SaveSlots (what each of the three save files holds) -> save menu
                 | the slot played last opens by itself, or the player picks one (Remotes.SaveMenu "Load")
                 v
DataService -> ProfileStore.StartSessionAsync -> reconcile/validate
                 | failure / session lost -> release runtime state, back to the menu with why
                 v
PlotService.assign -> first free plot, saved Sections + Owner attributes, display-name sign
                 v
ResearchService.load -> finished bonuses + BeltSpeed + ResearchSync (no completion events)
                 v
GroundService.restore -> dug and tilled cells, exposed ground in owned sections
                 v
BuildService.restore -> FactoryService.register/restore -> lanes and machines
WorldService.restore -> crops, elapsed wall-clock growth
InventoryService.load + EconomyService.load + GardenService.load -> sync + leaderstats
                 v
OnboardingService.load -> restored conditions + Objective sync
                 v
             DataReady = true

ProfileStore OnSave / two-minute snapshot / leave
    <- inventory slots + economy + research + garden stock/discoveries + onboarding + sections + dug/tilled ground + relative blocks, factory contents, crops
leave or "Save & quit to menu" -> clear crops -> unregister/remove blocks -> clear drops/inventory/economy
      -> release research (clear bonuses/BeltSpeed) -> release plot (ground back to untouched) -> ProfileStore.EndSession
      (quitting then sends SaveSlots once the last save has landed)
```

## Save files

Each player has three save files, each its own profile key in `GardenFoundation_v1`: slot 1
is `<UserId>`, the key every save had before slots, so older gardens are Slot 1; slots 2 and 3
are `<UserId>_2` and `<UserId>_3`. On join the slot played last opens by itself: each save
keeps `loadedAt`, the Unix time it was last opened, and DataService picks the filled slot with
the latest one (a save from before `loadedAt` counts its last save time instead). While it
opens, and whenever DataReady isn't true, `SaveMenuController` shows the authored
`StarterGui.SaveMenu`, with one card per slot (level, coins and when it was last saved, read
with `GetAsync` without taking the session lock); SaveSlots' `loading` tells it a garden is
already opening, so the cards stay quiet. A player with no save yet picks a slot. An
empty slot starts a new garden; a filled one can be deleted (`RemoveAsync`) after a confirm.
`Settings.Body.SaveQuit` saves and releases the garden exactly as leaving does and reopens the
menu, so a player can switch saves without rejoining.

State is established at require time. Assignment builds plots idempotently even if
PlotService.init has not run. Placement registers factories synchronously; a later
ChildAdded notification or init scan is harmless. No load assumes a sibling init ran.

## Layout and ownership

- `Shared/Plot` owns the section grid and prices, origins and cell conversions. The two rows
  face each other across the hub: the north row's front is its -Z edge, and the south row is
  the same garden turned half a turn (`Plot.flipped`), its front on its +Z edge. Saves are
  always laid out as an unturned garden, so a layout loads the same into either row:
  `toWorld`/`toRelative` turn cells, and `blockToWorld`, `turn` and `axis` turn a block's
  origin (its minimum corner moves to the far corner), rotation (+2) and Against with it.
  PlotService owns the locked-section slabs, soft non-colliding fences and signs, and
  GroundService the owned land's ground (farming.md § Ground and Farmland), all laid out in
  relative cells and turned the same way.
- Models are `Workspace.Plots["1"]` through `["6"]`; `Owner` is a user id or zero when
  free, and `Sections` lists the bought sections ("x,z;x,z"), replicated to every client. A
  full server rejects a seventh loaded profile without changing its save.
- Each garden is 7 x 6 sections of 10 x 10 cells: 70 x 60 cells (210 x 180 studs). Section
  column x, row z covers relative cells from x*10, z*10; row 0 is the front (-Z). The start
  block, columns 2..4 and rows 0..2 (30 x 30 cells, relative x 20..49, z 0..29), is everyone's
  from the start. Origins are x = -115, -35, 45 and z = -86, 26 cells (10-cell gaps), indexed
  across the south row, then the north row; the hub and quarry sit between the rows.
  PlotService lays grass pieces round the gardens (and removes the place's Baseplate), reaching
  `Map.GROUND_MARGIN` (36 studs) past them all and as deep as the ground plus 4 studs of bedrock,
  so a hole dug at a garden's edge meets a wall; each garden has a bedrock slab under
  `Plot.FLOOR`. Past that ground the map is MapService's parts (§ The map round the gardens). Owned
  sections are diggable ground, grass on top; each locked section is one solid slab as deep.
- New gardens are all grass; the Hoe tills it into Farmland, flush with the ground, so crops
  grow at y = 0, the level of machines standing on the grass beside them. Gardens used to start
  with twelve by eight Farmland cells at relative x 26..37, z 2..9 (`Plot.FARM_LOW`/`FARM_HIGH`);
  DataService saves those as tilled ground in older saves (layout 5), so their farms stay. Players spawn at the hub, then PlotService
  sends them to stand in front of their own gate, facing in, as soon as their garden is
  assigned and again after every respawn. The hub
  quarry contains shared Stone, Coal, Iron and Copper rocks.
- `Build.owns` checks the complete footprint and height; `Build.canEdit` additionally
  requires `DataReady`. Block cells must remain at y -8..79 (`Plot.FLOOR`..`HEIGHT` - 1); below
  y = 0 they can only go where the ground has been dug. Placement, harvest, machine
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
section's tile carries its Price and whether it is Buyable now; `PlotController` writes the
price on the tiles of the local player's own garden only, lying on the ground and turned to
read upright from the hub, so nobody sees another garden's prices. The ones that can be bought
now are bright, the rest dimmed. Locked ground is a muted grey-green, owned
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
the scenery and stands the new section's ground (`GroundService.extend`), never touching crops or
machines. Release clears the sections of the freed plot and puts its ground back to untouched.

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

DataService owns the fresh profile's 50 coins, zero XP, Hammer, Pickaxe, Hoe, Crafting Bench, ten
Carrot Seeds and five Wheat Seeds. The old full test kit is gone. Seeds are bought at the hub
and machines crafted at the Crafting Bench; playtests can still grant items through the server's
InventoryService.give API. Selected hotbar slot resets to one on load.

## Profile contents

DataService owns the template in `GardenFoundation_v1`. ProfileStore comes from the
installed ServerStorage package; its normal session lock and EndSession API are used.

| Field | Stored data |
|---|---|
| coins, xp | Live balances; level is derived |
| inventory | Dense slots, including `false` for empty slots |
| plot.sections | Bought sections as "x,z" (the start block is implicit); applied before restoring blocks/crops |
| plot.ground | `dug` and `tilled`: relative cells as "x,y,z" where the ground differs from untouched (farming.md § Ground and Farmland); applied after sections, before blocks and crops |
| plot.blocks | Item id, relative cell, rotation, Against, factory contents |
| factory contents | Separate input/output counts, counts per lane, remaining coal burn time, Sold, filter (items sent left), optional filterRight (items sent right) and filterMutations ("Left:Golden"), manual Split switch |
| plot.crops | Crop id, relative cell, current cycle wall-clock plantedAt, harvestCount, optional mutation, mutationRolled and growthBonus |
| seedStock | Remaining seed counts for this player in the current shop window |
| restockAt | Next five-minute Unix boundary; stock is reused only while it matches |
| discovered | Crop id to boolean, marked by a successful hand or machine harvest |
| indexed | Item id to boolean for the Index, marked when an item is given or harvested; unknown ids are dropped on load |
| onboarding | Next objective, integer 1..#Onboarding.STEPS+1; the last value means finished |
| research | `done: {[id]: boolean}`, `active: {id, startedAt, seconds}?`; fractional Unix start and whole-second duration, loaded before blocks/crops (research.md) |
| loadedAt | Unix seconds this save was last opened (0 before then), so a join reopens the one played last |
| plotLayout | 2 once the save's cells are laid out in sections, 3 once its farm is sunk, 4 once placed soil under crops is tilled ground (below); not in the template |

Vectors serialize as three-number arrays. Cells, Rotation and Against are saved as in an
unturned garden and turned on load into the south row (`Plot.blockToWorld`/`turn`/`axis`). Ground restores first, so blocks
can stand in its holes, then blocks, then crops, so their Farmland exists first. A dug or tilled
cell off the garden's land, out of range, or tilled where it can't be (stone) is skipped. A saved stack, block, crop or machine's contents that no longer checks out (an item
renamed or cut since it was saved, a missing template) is skipped with a warning, so a content
change never locks a player out. An Auto Crafter's recipe since cut is dropped on its own,
keeping what the crafter holds. Only bad balances, a broken save shape or a full server fail
loading, and those keep the original profile. A garden with no Crafting Bench anywhere --
carried, placed, or held in a chest, machine or belt -- gets one in its inventory on load.

The section layout keeps `GardenFoundation_v1`. A save without `plotLayout = 2` was laid out
from the corner of the old square garden, which is now the start block's corner, so
DataService moves every saved block and crop cell by `Plot.START_OFFSET` (+20 relative X)
once, turns an old sign tier (36/42/48 cells) into the sections that covered it, drops
`plot.expansion` and sets `plotLayout`. The key is kept out of the template on purpose:
Reconcile would otherwise fill it in on old saves and skip the move. Sections load through
`Plot.decode`, which drops anything that is not a whole, in-grid, non-start section. Moving a
whole garden to a new map origin translates its blocks, crops and starter soil together.

A save below `plotLayout = 3` had its Farmland at y = 0 and the crops on it at y = 1. Once,
crops at y = 1 over the farm move down to y = 0, and every block whose footprint stands over
the farm at y >= 1 moves down one (so a stack keeps its shape), then `plotLayout` becomes 3.

Below `plotLayout = 4`, crops could grow on placed Grass and Dirt blocks. Once, each such block
under a saved crop is removed from the blocks and its cell saved as tilled ground, so the crop
keeps its soil; a save without a Hoe is given one if it has room; then `plotLayout` becomes 4.

Active recipe ingredients are refunded into saved input counts and processing restarts
after loading. Partial job progress and sensor pulses do not persist. Stored fuel time,
outputs, router settings and lane counts persist; lane ordering/positions are reconstructed
at legal spacing. Loose drops are not saved and are cleared on departure. Only crops grow
offline; research timers also elapse offline and then wait for the player to complete them.
Current timing, multi regrowth and weather credit are in [farming.md](farming.md).
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

1. Join fresh: check the starter kit (Hammer, Pickaxe and Hoe only), 50 Coins, Level 1, a hub
   spawn followed by arrival at your own gate, well clear of the travel loops, owner sign, an
   all-grass garden, an old save's farm kept as Farmland, and no gap or seam showing baseplate between the garden and the ground
   round it. With API access off, expect the mock-store warning.
2. Use two players: test full-footprint boundary ghosts, planting, Hammer/Pickaxe pickup,
   harvest, machine panels, belt pickup and aimed drops on another plot. All writes must
   fail there; both players can mine every quarry rock, including Copper.
3. Place rotated machines and cubes, load a chest, queue belts, configure a Filter/Split,
   start a recipe and plant on both Farmland and placed Dirt. Save and rejoin into another
   plot. Verify contents, rotations, Against, offline crop stages and Next stage countdown.
4. Break planted soil and collect owned drops. Leave with loaded machines and crops;
   verify cleanup produces no duplicate harvest and the plot can be reassigned.
5. Test Seed Planter/Harvester near boundaries, smelter coal, fuel-free processors, all conveyor
   and router variants, chest Take all and the Shipping Bin's Sold counter.
6. Exercise EconomyService on the server: overspend, add coins, add XP across a level
   boundary, then rejoin and verify balances and the wallet. Continue with the Garden loop
   checklist in [economy.md](economy.md#studio-verification-still-required).
7. With API access enabled in a test place, verify persistence across Stop/new server,
   shutdown during processing, and session locking from a second server. A deliberately
   invalid saved item should be skipped with a warning while the rest of the garden loads;
   only bad balances or a broken save shape should fail loading, keeping the original profile.
8. Buy sections in several directions: the last owned cell, the first locked cell, a rotated
   footprint across a notch, planting on placed soil, and planter/harvester/sprinkler areas
   across a section edge. A bought section must be usable at once by ghost and server, its
   fence and prompts must move, and another player must see no prompts. Try a non-adjacent,
   owned, out-of-range and fractional section, too few coins and remote spam.
9. Load an old (pre-section) save: blocks and crops must land in the start block on the same
   farmland, once; rejoin and check they do not move again. A save with crops on placed Grass or
   Dirt must keep them, now on Farmland, and gain a Hoe.
10. Ground: dig grass, dirt and stone down to the floor (bedrock stops it) and at a section and
    garden edge (a wall, never a view into the void); mine Farmland for Dirt with a crop
    on it (uprooted); till grass, dirt and a placed Dirt block; seeds must refuse plain grass.
    Stand a sprinkler by Farmland and wait out a rain: it darkens, and dries two minutes after.
    Build a block back into a hole, buy a section next to a dug hole, rejoin and check every
    hole, tilled cell and block, then leave and check the garden is untouched for the next
    player. Watch server memory and join time with all six gardens loaded.

Local formatter, lint and type checks do not substitute for these runtime checks.

## The map round the gardens

`Shared/World/Map` owns the layout, built outward from the gardens' extent: `GROUND` (the gardens
plus the margin), a flat forest ring `FOREST` (150) studs wide, then `HILLS` (240) studs of hills
to `EDGE`; its `PATHS` (a road out of each end of the hub road, joining a loop through the
middle of the forest) and `PONDS`; and the meadow colour both PlotService and the land past it use. `MapService` builds it at
startup out of anchored parts in `Workspace.Map` (no Terrain), never saved:

- **Forest floor.** Four 16-stud-deep strips from PlotService's ground out to the forest's edge,
  top at y = 0, wearing World/GroundLook's grass on top and dirt down the sides, tiled one per
  3 studs like a garden's cubes, so the meadow meets the gardens' ground with no seam. The ground
  round the gardens (PlotService) wears the same.
- **Paths and ponds.** Paths are dirt-textured strips with rounded disc ends, standing 0.12 studs
  proud of the floor (each 0.03 higher than the last so crossings never flicker): a texture is
  drawn with a depth bias that beats a surface a few hundredths of a stud above it. Each pond is a
  sand disc, a darker bed and a shallow, see-through water disc that can be waded through.
- **Hills.** Soft low-poly hills: a grid about 40 studs square over the whole map, skipping the
  forest, each square two flat triangles (two WedgeParts each, sunk under their surface, the
  diagonal alternating), about 2,900 wedges built 200 a frame. Heights rise from the forest's edge
  (corners rounded) to about 130 studs at the map's edge, in broad noise swells with small bumps;
  each triangle is the meadow green, lighter up high and a touch lighter or darker by a slow
  noise, or rock on the bumpiest high tops.
- **Edge and sky.** Invisible walls at `EDGE`; an Atmosphere (soft haze) when the place has none.
- **Trees.** `World/Layout` scatters about 90 ForestOak, ForestPine and ForestBirch nodes over the
  forest on a seeded, jittered grid, thicker in noise groves and clear of paths and ponds
  (factory.md § The forest).

Playtested: the meadow meets the gardens' ground with no seam, paths and ponds (with their sand
rims) show, the low-poly hills close the view, and the trees stand.

## Plot and hub props

`TravelService` builds two public, opposite-direction continuous loops along the central
road under `Workspace.TravelLanes`. Each runs beside both rows of plots and turns around
at both ends, with the hub inside the loops. It owns their speed and appearance and derives
their length from the plot bounds. Both are soft grey with low darker curbs; low surfaces allow
entry and exit anywhere, and pale chevrons
show travel direction. They sit clear of the hub stalls and quarry and use anchored surface
velocity, independent of factory lanes and saves. Playtest by standing on each belt without
input through the rounded end turns, then walking sideways off it and jumping; check that each carries in its marked
direction and that ordinary ground movement resumes off the belt.

PlotService fences the owned land with one `PlotFence` prop per edge cell and a `PlotFencePost`
at every corner of the fence, leaving the two-cell gate at the start block's front, and stands the
`PlotSign` outside the fence beside the gate; the owner's name is a SurfaceGui on the sign's
`Board` part. HubService stands each stall prop (named for its stall) turned to face the
spawn, parents its ProximityPrompt to the stall's `Counter` part, and lays a paved plaza with
`HubLamp` and `HubFlowerBox` props. `server/libraries/Props` places them all as scenery (no
collisions, queries or touches). The props come from `IslandsMachines/build/garden_props.py`
into `ReplicatedStorage.Assets.Props`; without them both services build plain parts.
