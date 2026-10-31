# Garden overhaul

The plan for turning the Islands-style factory sandbox into an industrialized farming game in the
spirit of Grow a Garden: each player has their own plot, buys seeds from a shop that restocks,
grows crops that can come out mutated and worth more, sells them, and saves up for machines that
farm, process and sell for them. A second progression mines ore and crafts it into parts for
higher machine tiers. Work happens on the `garden-overhaul` branch, phase by phase; each phase
ends playable.

The feel is calm and satisfying (see the game-vision note): soft, light art, things you enjoy
watching grow and flow, no harsh fail states. Islands is a reference for how machines and
conveyors play, never for their models.

## Decisions

| Question | Choice |
|---|---|
| Core loop | Grow a Garden's buy seeds, grow, sell loop, plus mining and crafting as a second progression |
| World | One plot per player on a shared map, with shops and a quarry in the middle; plots are saved |
| Getting machines | Bought with coins from a machine shop, unlocked by level; tier 2 also costs crafted parts |
| Machine art | Gameplay first with the current or simple placeholder models; new soft models in phase 5 |
| Crop weight | Cut. Every crop item is a stackable id so conveyors, stacks and machines keep working; value comes from rarity and mutations instead |
| Fuel | Cut for farm machines (calm: they run on their own). Only the smelter burns coal |

## The map

Cells are `Build` cells (3 studs). The baseplate is ±256 studs, so everything stays inside ±80 cells.

```text
          z = -74 ... -27      [Plot 1] [Plot 2] [Plot 3]  (maximum footprints)
          z = -12 ...  12      Seed Shop · Gear Shop · Machine Shop · Sell Stand · Quarry  (hub)
          z =  24 ...  71      [Plot 4] [Plot 5] [Plot 6]  (maximum footprints)
```

- **Plots.** Six gardens, each a grid of 7 x 6 sections of 10 x 10 cells (70 x 60 cells), in two
  rows of three with the hub and quarry between them, each row's front facing the hub. A player
  who joins takes the first free garden and is sent to its gate; it is released when they leave. The 3 x 3 start block at the front centre
  is free and holds the sign, the gate and a farm of Farmland. Any other section is bought once it
  touches owned land, its price lying on its ground like a factory tycoon's plot: 2,500 coins next
  to the start block, then 20,000, then 100,000 for the back rows. The fence follows the owned
  land. A player can place, plant and pick up only on owned sections of their own garden
  (`Shared/Plot`), and machines work only inside the plot they stand on.
  [plots.md](plots.md#buying-space) owns the flow; [economy.md](economy.md#garden-sections) the prices.
- **Hub.** NPC stalls opened with a ProximityPrompt: Seed Shop, Gear Shop, Machine Shop and
  Sell Stand. The quarry's rocks (stone, coal, iron, copper) respawn and are shared.
- Everything else from the old world goes: the ore field, the grove, the meadow, the pens and the
  `Workspace.IslandsMachines` showcase.

## Economy

- **Coins** are the currency, shown on the HUD and in `leaderstats`.
- **XP and level.** XP comes from harvesting (the crop's rarity) and from selling (1 per 10 coins).
  The level unlocks machines in the Machine Shop. Advancing from level n costs `20 * n^2.75` XP, rounded.
- **Selling.** At the Sell Stand: sell what's in your hand, or sell every crop and product you
  carry. A Shipping Bin on your plot sells what a belt brings it. Price is the item's `value`
  times its mutation's multiplier.

## Crops

Each crop has a rarity, a seed price, a sell value, a total grow time and a harvest kind.
A **single** crop is uprooted when harvested and must be replanted (a machine replants it from
the seed it keeps). A **multi** crop is a plant that stays: when ripe it shows its fruit, a harvest
takes the fruit, and the fruit grows back after `regrow` seconds, for ever.

| Crop | Rarity | Seed | Value | Grow (s) | Kind | Per harvest |
|---|---|---|---|---|---|---|
| Carrot | Common | 10 | 18 | 60 | single | 1 |
| Wheat | Common | 15 | 12 | 75 | single | 2 |
| Strawberry | Uncommon | 45 | 15 | 90 | multi, regrow 45 | 3 |
| Potato | Uncommon | 60 | 70 | 120 | single | 1 |
| Tomato | Rare | 150 | 35 | 150 | multi, regrow 60 | 2 |
| Corn | Rare | 250 | 160 | 240 | single | 1 |
| Blueberry | Rare | 400 | 30 | 180 | multi, regrow 50 | 4 |
| Pumpkin | Epic | 1,200 | 1,100 | 480 | single | 1 |
| Apple | Epic | 3,000 | 90 | 360 | multi, regrow 90 | 3 |
| Watermelon | Legendary | 6,000 | 3,500 | 600 | single | 1 |
| Grape | Legendary | 10,000 | 260 | 480 | multi, regrow 120 | 4 |
| Starfruit | Mythic | 30,000 | 1,800 | 720 | multi, regrow 150 | 2 |

Stages stay `Sprout`, `Young`, `Mature`, `Ripe`, each a quarter of the grow time. Growth is
timestamp based, so crops keep growing while the player is away and the plot is saved.

### Mutations

A crop rolls a mutation when it ripens (a multi crop rolls again each time its fruit grows back).
A mutated harvest is its own item id, `<Crop>+<Mutation>` (`Carrot+Golden`), so it stacks with its
own kind, rides belts and can be sorted by a Filter Conveyor (by item, each pick narrowed by
its own mutation checklist). Processing machines never mix variants: a batch of one mutation makes
that mutation's product (`Carrot Crate+Golden`, x20).

| Mutation | Multiplier | Comes from |
|---|---|---|
| Wet | x2 | 25% while it rains, 10% under a sprinkler |
| Shocked | x10 | 5% during a thunderstorm |
| Golden | x20 | 1% always |
| Rainbow | x50 | 0.1% always |

### Weather

The server rolls an event every 8 to 12 minutes, shown as a banner for everyone:

| Event | Lasts | Effect |
|---|---|---|
| Rain | 2 min | Crops grow 1.5x faster; Wet chance |
| Thunderstorm | 90 s | Rain's effects plus the Shocked chance |
| Golden Hour | 60 s | Golden chance x5 |

## Shops

- **Seed Shop.** It restocks every 5 minutes for the whole server, and each player has their own
  stock of each seed: Common 5 to 15, Uncommon 3 to 8, Rare 1 to 4 (60%), Epic 1 to 2 (25%),
  Legendary 1 (8%), Mythic 1 (2%); otherwise none. The screen shows the countdown.
- **Gear Shop.** Watering Can (a tool: one splash takes 20% off what's left of a crop's stage),
  Pickaxe, Hammer, and decorative blocks (Grass, Dirt, Stone, Wood Planks, Bricks, Glass).
- **Machine Shop.** Every machine, with its level, coin price and, for tier 2, the parts it needs.

## Machines

Machines still run on the factory engine (`Shared/Factory`, `FactoryService`): lanes, routers,
ports, belts out of output faces and the machine panel. The old Islands roster is replaced:

| Machine | Level | Coins | Does |
|---|---|---|---|
| Conveyor, turns, ramps | 1 | 25 | Carry items (tier 2 runs twice as fast) |
| Split, Merger, Filter, Sensor | 3 | 150 | Route items; the filter sorts mutations |
| Shipping Bin | 2 | 300 | Sells what a belt brings it for the owner |
| Storage Chest | 2 | 200 | Holds 12 slots from a belt (the Industrial Chest) |
| Seed Planter | 4 | 800 | Plants seeds from its hopper into empty soil in a 3 x 5 patch in front |
| Sprinkler | 5 | 1,000 | Crops within 3 cells grow 1.25x faster and can turn out Wet |
| Harvester | 6 | 2,000 | Harvests ripe crops within 4 cells onto its output belt; a single crop it harvests restarts from a sprout, so it replants itself |
| Mill | 7 | 2,500 | 2 Wheat -> Flour (value 40) |
| Juicer | 8 | 4,000 | 3 Strawberry, Blueberry, Grape, Apple or Tomato -> that Juice (3.5x the fruit) |
| Oven | 10 | 8,000 | Flour + 2 Strawberry, Blueberry or Apple -> that Pie (value 250, 400, 600) |
| Crate Packer | 9 | 6,000 | 10 of any crop -> its Crate (12x the crop) |
| Smelter | 3 | 500 | Ore + Coal -> Bar |
| Workbench | 3 | 400 | Bars -> parts (below) |

Tier 2 Harvester, Sprinkler, Planter and Mill (faster, wider) cost coins plus parts:

| Machine | Level | Coins | Parts | Does |
|---|---|---|---|---|
| Seed Planter II | 8 | 4,000 | 6 Gear, 3 Steel Frame | 5 x 7 patch, a seed a second |
| Sprinkler II | 9 | 5,000 | 6 Circuit, 6 Copper Wire | Radius 5, 1.5x growth, +20% Wet |
| Mill II | 10 | 6,000 | 8 Gear, 2 Steel Frame | The Mill's recipes in half the time |
| Harvester II | 12 | 10,000 | 6 Circuit, 3 Steel Frame | Radius 6, a crop every 1.5 s |

## Crafting

The quarry in the hub gives Stone, Coal, Iron Ore and Copper Ore to the Pickaxe. A Smelter makes
Iron and Copper Bars, and a Workbench makes parts:

| Part | From |
|---|---|
| Gear | 2 Iron Bar |
| Copper Wire | 1 Copper Bar |
| Circuit | 2 Copper Wire + 1 Gear |
| Steel Frame | 4 Iron Bar + 1 Stone |

## Persistence

ProfileStore (`ServerPackages.ProfileStore`) keeps, per player: coins, XP, inventory slots, seed
stock and the time of the restock it belongs to, discovered crops, and the plot including its
bought sections. Saves from before sections move once into the start block (+20 relative X,
`plotLayout`, plots.md), in the same GardenFoundation_v1 store; starter Farmland sits at
x 26..37, z 2..9. The plot is saved
relative to its own origin, so it loads into whichever plot is free: each placed block's item id,
cell, rotation and `Against`, and each crop's type, plant time, mutation and harvest count. Machine
contents are saved as their item counts. A profile autosaves every 2 minutes and on leave.

## What is cut

Oil, petroleum and fuel barrels, the pumpjack and drill and deposits, maple sap and every wood tube,
trees and the lumber chain, animals and their machines (milker, trough, wool vacuum, truffle
barrel), the stone polishing and cutting chain, the steel, bronze and press chain, and the Axe.
Git history keeps all of it.

## Phases

1. [x] **Foundation.** Cut the content above; plots and ownership; coins, XP and levels; ProfileStore
   saving inventory, coins and plots; offline growth.
2. [x] **Garden loop.** The crop table, multi-harvest plants, mutations, the Seed Shop with restocks,
   the Sell Stand, weather, and the HUD for coins, level and weather.
3. [x] **Automation.** The machine roster and Machine Shop, with Planter, Sprinkler, Harvester, the
   processors and the Shipping Bin.
4. [x] **Crafting.** The quarry, Smelter, Workbench, parts and tier 2 machines.
5. **Art.** New soft Blender models for crops, machines, stalls, plots and props, through the
   `IslandsMachines/build` pipeline. *In progress:* every crop, machine, processor, conveyor,
   router, stall and plot prop has art of its own (below). What is left is the quarry's copper
   rock (still a placeholder cube) and any polish.

### Art progress

- **Crops (done).** Strawberry, Tomato, Corn, Blueberry, Pumpkin, Apple, Watermelon, Grape and
  Starfruit: four stages and a produce item each, 45 models, about 52k triangles in all (the
  heaviest, ripe grapes, is 5.6k). Built in `IslandsMachines/build/garden.py` with new soft
  helpers (`blob`, `lathe`, `striped`, `leaf`, `on_dome`) on top of assets.py's. Each crop has
  its own silhouette: a low strawberry rosette, a staked tomato vine, tall corn, a cloud-like
  blueberry bush, a sprawling pumpkin, a little apple tree, a striped melon, an arched grape
  trellis and a slender teal starfruit with pale gold stars. Every stage fits one cell.
  Imported as the GardenWorld and GardenItems sets, so the Islands sets never re-import. Their
  Apple and Blueberry items replace the Islands ones.
- **Farm machines (done).** Seed Planter, Sprinkler, Harvester, Shipping Bin and Storage Chest
  have models of their own in `IslandsMachines/build/garden_machines.py`, imported as the
  GardenMachines set under their item ids, so they no longer borrow Islands art (tier 2 uses
  tier 1's model). Cream rounded bodies, sage, warm wood, terracotta and brass. Each is one cell
  wide and two deep (two tall; the sprinkler is one cell), smaller than the old 3 x 2 x 3
  Islands bodies. Belts are the kit's conveyor, so they meet every other conveyor, and each
  ends at a soft arch the finish script measures as a 1.1-stud port. The planter's patch is
  now centred on its own axis (Blocks `plantPatch`). Playtested: harvester -> shipping bin
  through the new ports, and the planter sowing onto the bed.
- **Processors (done).** Mill (a windmill on a mill house), Juicer (a glass jug of juice), Oven
  (a terracotta dome with a glowing mouth), Crate Packer (a gantry press over a crate), Smelter
  (a stone kiln with a glowing window and a coal basket) and Workbench (a wooden bench with a
  vise, gear, hammer and copper bars), in `garden_machines.py` as the GardenProcessors set.
  Each takes items in at -Z and puts products out at +Z, so each is one cell wide and three
  deep, with a belt and arch at both ends (1.1-stud ports). Mill II draws the Mill.
  Playtested: wheat -> Mill -> Flour riding straight into a Shipping Bin.
- - **Conveyors (done).** Plain belts, turns, ramps (tier 1 and 2) and the sensor are our own in
  `IslandsMachines/build/garden_conveyors.py`, imported as the GardenConveyors set under their
  item ids, so they replace the Islands templates. Only the geometry the game needs is kept:
  belt top 1.59, belt 2.3 wide, ends on cell faces, the ramps' 6-long 3-high climb, every
  footprint unchanged. The look is new: a smooth sage body (sky blue for tier 2) with a cream
  band (terracotta for tier 2), round cream rails (brass for tier 2) instead of lips, cream
  end rollers, soft pill arrows on a warm taupe belt, round ramp legs, no bolts or glass walls,
  and a sensor of cream posts with a mint curtain. The farm machines and processors use the
  same belt. Playtested: a carrot riding belt -> tier 2 belt -> sensor (lit) -> Shipping Bin.
- **Routers (done).** Split, Merger, Filter and Randomizer keep islandskit.junction's geometry (a
  3.8-stud hub with a belt arm to each connected cell face) and so their 3 x 2 x 3 footprints, but
  are drawn in the garden style: a soft cream hub with a sage band and a rounded cap, the new belt
  and an arch on each arm, and a pastel icon on the cap (a sage fork, a blue V, a terracotta
  funnel, a die). In `garden_machines.py` as the GardenRouters set. Playtested: a carrot through
  a Split, straight on into a Shipping Bin.
- - **Hub and plots (done).** The four stalls are market stalls with striped awnings in their own
  colours (sage, butter, sky, lilac), an emblem on a sign (sprout, coin, watering can, gear) and
  goods on the counter; the plots get a white picket fence with wooden posts and sage caps, a
  two-cell gate, and a sign beside it with the owner's name on its board; the hub gets a paved
  plaza, four lamp posts and four flower boxes. Built in `garden_props.py` as the GardenProps set
  into `ReplicatedStorage.Assets.Props` (no hitbox, pivot at the bottom centre). HubService and
  PlotService place them through `server/libraries/Props`, which makes every prop scenery only
  (no collisions, queries or touches), and fall back to plain parts when a prop is missing.
  The stall prompts sit on each stall's Counter part. The original 24-cell fence/sign props
  and Seed Shop opening were playtested. The section garden was playtested: an old save moved
  into the start block intact, a ring 1 section bought, fenced and built on, and labels read from
  the hub. The fence follows the owned sections and keeps the gate at the start block's front.
- - The importer counts the finish script's Hitbox as a part, so a full re-import of an already
  finished set rebuilds every model in it. New art therefore goes in its own set.
6. **Polish.** Onboarding, sounds, VFX, balance.

### Polish implementation decisions

- **Balance**
  - `tools/balance/model.py` reads the content owners and compares them with its historical
    `before.json`. Assumptions, before/after level and machine timings, income, the plain-crop
    sensitivity and remaining Studio checks are in [economy.md](economy.md#balance).
  - Only Strawberry's seed price, the two XP curve parameters and tier-two part counts change.
    Common/Uncommon seeds repay in one plain harvest; every valued product already beats its
    inputs, including same-mutation batches, so product values and machine speeds stay put.
  - Tier-two parts were first sized to 20-28 minutes of *supplied* crafting, which needed
    80-120 hand-mined bars from the shared quarry, a grind wall. Claude resized them to 24-36
    bars each (Planter II 6 Gear + 3 Steel Frame, Sprinkler II 6 Circuit + 6 Copper Wire, Mill
    II 8 Gear + 2 Steel Frame, Harvester II 6 Circuit + 3 Steel Frame): about 5 minutes of
    mining and 5-8 of crafting. Coin prices and unlock
    levels are unchanged. Existing lifetime XP is kept; levels recalculate with the new curve.
- **Onboarding**
  - `Shared/Onboarding` owns the seven ordered objectives, rewards and saved-step sanitization.
    `OnboardingService` observes `GardenEvents`; it never blocks an action or accepts client
    completion claims. Actions done ahead of the prompt count during the current session.
  - DataService restores onboarding after the plot, inventory, economy and garden, snapshots
    it with balances, and releases it on cleanup. Reconcile gives older saves step one.
    Existing crops/discoveries, level and Shipping Bin ownership satisfy the corresponding
    steps; seed purchases and stand sales need live evidence.
  - `Objective` binds the authored HUD panel through `Hud.find`, uses a short cancellable
    check/fade, and hides on completion. Reduced motion changes state immediately. The
    server's `OnboardingStep` attribute recovers a remote sent before the HUD binds.

- **Effects and sound**
  - `server/libraries/GardenEvents` is the one place live garden actions are announced
    (Planted, Placed, Harvested, Sold, Bought, LevelUp, Watered), fired by the service that did
    the action and never by save restoration. Onboarding and effects listen to it; gameplay
    services know neither.
  - `FxService` turns those into `Remotes.Fx`: planting, harvesting and watering go to everyone
    (clients draw only within 140 studs), sales, purchases and level-ups to the player. A
    level-up also toasts what it unlocked ("Level 6! New in the shops: Harvester.").
  - `FxController` draws a soil puff when planting; a burst in the crop's (or mutation's) colour
    and the produce bobbing up when harvesting; coins sparkling round the player at the Sell
    Stand (a small, silent sparkle at a Shipping Bin, so a busy factory stays quiet); and a warm ring
    on level-up. Reduced motion keeps colour and sound and drops the movement.
  - Sound roles live in `Shared/Sounds` (Plant, Harvest, Coin, Buy, Water, Step, LevelUp),
    played through `client/libraries/Sound`: spatial for world moments, flat for the player's
    own. The palette was generated with ElevenLabs sound effects in one family of material words
    (warm wood, soil, soft chimes, no voice or melody); every take is in `assets/sounds/takes`
    and the chosen ones in `assets/sounds` (README there). They are uploaded as audio assets
    through the Open Cloud Assets API (`ROBLOX_API_KEY`) and their ids set in `Sounds.luau`; a
    role with no id is silent, so the game is whole without sound.
  - Background music: two calm instrumentals (ElevenLabs Music, 150 s each, in `assets/music`)
    listed in `Shared/Music`. `MusicController` plays them flat at 0.22 volume in a shuffled
    order, fading in and out over 4 s, with 25-60 s of quiet between tracks.
  - Playtested in "farming game": the objective panel, a seed purchase completing step 1 (and
    steps 2-3 from the save), level-ups sending their effect and toast, and the live harvest,
    sale and purchase effects from a running plot.

### Foundation implementation decisions

- Both rows face the hub; the south row is turned half a turn and saves are turned with it
  (Plot), so a layout moves between rows with soil still under its crops. Runtime fences are
  soft (non-colliding); players join at the hub and are sent to their gate. Builds occupy y 0..79. A seventh player is rejected
  when no plot is available. Exact runtime layout and rules are mapped in [plots.md](plots.md).
- XP is cumulative: level one starts at zero and advancing from level n costs the rounded
  formula above. Foundation supplies the API, sync and leaderstats; harvest/sales awards, item
  prices, the HUD and Teleseller currency payout remain with Garden loop / Automation.
- Existing Wheat, Carrot and Potato yields and three transitions to Ripe are retained until
  Garden loop; only the clock changes now. Machine reaping still restarts a Sprout. Saves retain
  harvestCount and optional mutation, without adding multi-harvest behavior or mutation rolls.
- Milk suppliers are cut, so the retained Food Processor temporarily uses 2 Wheat + 1 Carrot
  for BerryDough; Oven still makes BerryBread. Crate Packer uses 20 Carrot or Wheat, and its
  retained tier 2 uses 50. Product ids/art and timings remain. Apple/Blueberry item ids remain
  for the later crops, but their old world suppliers are gone. These are transitional recipes.
- Wood Planks now break with Pickaxe. The retained decorative blocks are the six in the Gear
  Shop target; Smooth Stone and Stone Bricks leave with their processing chains. Gold and its
  smelting recipe leave with deposits/alloys; CopperRock uses a copper-coloured placeholder.
  Sawmill and Copper Press gameplay are cut now; their unused art remains for future placeholders.
- The profile store is GardenFoundation_v1. Selected hotbar slot resets to one. Saves preserve
  input/output counts separately, lane counts, fuel time, Sold and router settings. Active recipe
  inputs are refunded for restart; job progress, sensor pulses and loose drops are not saved.
  Lane order/positions are reconstructed. Only crops advance offline. A saved stack, block, crop
  or machine's contents that no longer checks out (an item renamed or cut since) is skipped with
  a warning, so content changes never lock a player out; only bad balances or a full server kick. Studio without API access
  uses ProfileStore's built-in mock, which lasts only for the current server.
- Source assets are untouched. PlotService removes only the live Workspace showcases (IslandsMachines, IslandsWorld, IslandsItems). Local
  formatter/linter configuration was added because the referenced repo gate/config files were
  absent. Runtime verification remains the Studio checklist in [plots.md](plots.md).

### Garden loop implementation decisions

- `World.CROPS` owns all twelve crop numbers and fallback art/colours. Items generates seeds,
  produce and four mutation variants per produce; `item.value` is the final sale price,
  already multiplied once. Existing seed/produce ids and GardenFoundation_v1 stay compatible.
  The absence of `regrow` denotes a single crop. Existing art wins; expected tinted fallbacks
  are silent. Exact placeholder choices and rarity/mutation palettes live in shared content.
- Four equal growth quarters reach Ripe at the full listed grow duration. With only three
  transitions before harvestable Ripe, the fourth quarter is final ripening with Mature art;
  BlockInfo calls it Ripening. Multi regrowth stays Mature for its `regrow` duration. A machine
  restarts single crops from Sprout. Neither ripe hand harvest nor ripe soil removal returns a seed;
  unripe digging/removal still does. Each successful hand/machine harvest awards rarity XP once.
- `plantedAt` is the current cycle start in fractional Unix seconds (old integers still load), reset after each reap; `harvestCount` distinguishes
  initial growth from multi regrowth. Saved `growthBonus` banks online rain speed, and offline
  time runs at normal speed. Rejoining starts a new live weather baseline, never retroactively
  claiming this server's past rain. Optional new crop fields default safely on Phase 1 saves.
- Mutations are exclusive: one draw partitions the stated probabilities into Rainbow,
  Golden, Shocked, Wet and plain outcomes, so the percentages remain exact. `mutationRolled` saves plain outcomes as well
  as variants so ripe fruit cannot reroll on rejoin. Offline ripening uses only always-on
  chances. The cell chance-provider hook is zero until Phase 3 adds sprinklers.
- Weather starts clear; events are equally likely and their starts are 8-12 minutes apart.
  Runtime `ReplicatedStorage.Weather` attributes Event/EndsAt publish the event and its
  server-time deadline. Client rain uses one bounded camera emitter; named lighting requests
  compose through a private colour-correction effect. Reduced motion suppresses flashes and
  Rainbow hue cycling. Crop sparkles are limited to 48 nearby emitters.
- Restock rolls are independent per seed using its rarity band. `restockAt` stores the next
  five-minute Unix boundary; current-window missing/invalid stock becomes zero rather than
  rerolling. The screen buys one seed per press; the server also accepts validated bulk counts.
  Inventory capacity is checked before spending; buying and selling share a 0.2-second cooldown.
- Sell Stand uses final item values, and sale XP is floored per transaction with no remainder
  carry. Provisional product values are BerryDough 60, BerryBread 90, FruitCrate 420 and
  LargeFruitCrate 1,100; [economy.md](economy.md) explains the processing margins. Processing
  consumes plain inputs first, accepts mixtures of mutations, outputs plain products and
  preserves consumed variant ids for unfinished-job refunds. Teleseller payout waits for
  Phase 3. Exact-id Filter Conveyor routing required no behavior change.
- Hub stalls sit at world (-24, 0, -15) and (24, 0, -15), with prompts in each Counter.
  Prompts activate at ten studs; server/client transaction reach is twelve studs. Stalls are
  soft non-colliding placeholders. Missing authored HUD/templates warn once and disable only
  that screen. Shop has generic catalogue rendering; Screens arbitrates all four windows.
  Wallet attributes recover a late initial economy sync, and prompt activation refreshes stock.
- All HUD shells/templates remain in the place file and are not edited here. The exact
  contract, code owners and Studio checklist are in [economy.md](economy.md). Static checks
  and content/remote consistency checks pass; Studio runtime, persistence, device layout and
  multiplayer verification remain unverified because Studio execution requires approval and
  this session's approval policy is never.

### Automation implementation decisions

Built by Claude, not Codex: Codex hit its usage limit, and the user chose not to wait.

- **The harvester replants on its own.** A single crop it harvests restarts from a sprout,
  as the picker did, rather than keeping seeds for a planter. The Seed Planter is for filling
  new soil. The harvester works one crop every 3 s, within 4 cells (12 studs) of its centre.
- **The planter's patch** is 3 wide and 5 deep past its forks, filled nearest row first,
  one seed every 2 s. Because the farm is a raised bed one cell high, each patch cell is tried
  at the planter's level and one up, so a planter on the grass beside the bed plants onto it.
- **Sprinklers** reach 3 cells across and one up or down, on their own plot. The best one
  counts; several don't stack. Growth speed banks into the saved `growthBonus` and multiplies
  with rain, so offline time still runs at normal speed.
- **Watering Can**: 150 coins, a fifth off what's left of the current stage, 1.5 s cooldown.
- **Shipping Bin** pays per item as it sells, carrying XP remainders per player, and batches
  its toasts every 2 s. It takes any item with a value, not only resources.
- **Products** live in `Shared/Factory/Products`. A juice is worth 3.5x one fruit, made from
  three; Flour is 40 from 2 wheat; crates are 12x the crop from ten. The old dough, bread and
  fruit crates are gone.
- **Tier 2 conveyors** cost 75 at level 4; routers are 150 at level 3, including the
  Randomizer and Sensor, which the table didn't price. Decorative blocks cost 5 to 20 and the
  Pickaxe and Hammer 50 each, all at level 1. Tools can't be bought while you carry one.
- **Old saves** keep their machines: DataService renames the old ids (Industrial Flower
  Picker -> Harvester, Sapling Automatic Planter -> Seed Planter, Teleseller -> Shipping Bin,
  Industrial Chest -> Storage Chest, Food Processor -> Juicer, Industrial Oven -> Oven, Crate
  Packer Tier 2 -> Crate Packer) before validating. Old products are dropped with a warning.
- **New place assets**: `Assets.Blocks.Sprinkler` (a one-cell sprinkler on a stone base) and
  `Assets.Tools.WateringCan`, both soft placeholders authored in Studio.
- **Playtested** in "farming game": shop locks, refusals and purchases; a planter filling its
  patch on the bed; sprinkler timings exactly 1.25x; harvester -> shipping bin paying coins;
  Mill making Flour; watering taking 20% off a stage, with the cooldown holding.

### Crafting implementation decisions

Built by Claude: Codex was still at its usage limit.

- **Parts live in `Shared/Factory/Products`** beside the processed products, as Workbench
  recipes with no value, so Items and Blocks read one table. They borrow Assets.Items art:
  Gear and Steel Frame the steel plate, Copper Wire the copper bar, Circuit the copper plate
  tinted green. Parts can't be sold.
- **Smelter** is the Industrial Smelter renamed (old saves are renamed too). It still burns
  coal: 30 s of running per coal, 10 s per bar. Gold and its bars stay cut.
- **Tier 2 machines are separate items**, built from the same constructors as tier 1
  (`planter`, `harvester`, `sprinkler`, `productRecipes(machine, pace)` in Blocks) and drawn
  with tier 1's art until the art phase. A tier 2 sprinkler beats a tier 1 over the same crop
  because the best speed counts.
- **Buying with parts** checks level, the tool rule, room, every part and coins before taking
  anything, then spends the coins, takes the parts and gives the machine without yielding. A
  refusal names every part needed ("You need 2 Circuit and 2 Copper Wire."). The shop row shows
  the parts in its `Stock` label and the button reads "Need parts" until you carry them all.
- **The planter's patch** is now data (`plantSize`), so the panel shows each tier's real size.
- **Playtested** in "farming game": the Smelter smelting with coal; the Workbench making Gears,
  Copper Wire and a Circuit; the "Need parts" row and refusal; and buying Sprinkler II, which
  took the coins and every part. A smelter whose outlet faces a machine it doesn't line up
  with keeps its bars waiting on its belt; nothing is lost.

Placeholder art until phase 5: the current machine models stand in for the new machines (Seed
Planter = Sapling Automatic Planter, Harvester = Industrial Flower Picker, Shipping Bin =
Industrial Merchant Teleseller, Mill = Industrial Sawmill, Juicer = Food Processor, Oven =
Industrial Oven, Crate Packer = Crate Packer, Smelter = Industrial Smelter, Workbench = Copper
Press), and new crops borrow an existing crop's stage art tinted their colour.
