# Economy and garden HUD

`EconomyService` owns coins and lifetime XP; `Shared/Economy` derives levels. GardenService
owns seed stock, discoveries and stall transactions. DataService loads and snapshots both
services. [farming.md](farming.md) owns crop timing/mutations; [plots.md](plots.md) owns saves.

## Stock and purchases

The server uses five-minute Unix boundaries. Each player's `restockAt` is the **next**
boundary; `seedStock` is the remaining stock for that window. On load, keep it if that
boundary still matches, otherwise reroll. Rejoining cannot refresh a current window.
Unknown stock ids are discarded; invalid or missing amounts in a current window become
zero. An expired window rolls each seed independently, using its rarity's chance and
inclusive quantity band in `Shared/Economy/Content`. The server checks boundaries once per
second and also before a purchase, so a timer tick cannot sell yesterday's stock.

A purchase accepts a known seed id and positive finite integer count no greater than the
player's stock. The player must have DataReady, a living character and be within the
server's stall reach. Purchases and sales share a 0.2-second action cooldown. The server
checks the whole inventory addition before `EconomyService.trySpend`, then gives the seeds
and reduces stock without yielding. No coins or stock are lost to a full inventory.
The UI buys one seed per press; the server supports larger validated counts.

`ShopSync` sends `{restockAt, stock}` on load, restock, purchase response and Seed Shop
prompt activation. Prompt refresh recovers from a load sync that preceded HUD binding.
`ShopBuy(shopId, itemId, count)` is intent only; `shopId` names the stall. `Notify(message)` explains purchases, refusals and
rare harvests. All remote instances/payloads are owned by `default.project.json` and
`Shared/Remotes`.

## Garden sections

`Shared/Plot` owns the section grid and its prices. Every garden is 7 x 6 sections of 10 x 10
cells; the 3 x 3 start block at the front centre (30 x 30 cells) is free. Any other section
is bought once it shares an edge with owned land, priced by its ring, its distance in
sections from the start block:

| Ring | Sections | Coins each |
|---|---|---|
| 1 (touching the start block) | 11 | 2,500 |
| 2 | 15 | 20,000 |
| 3 (the back rows) | 7 | 100,000 |

Ring 1 is the first goal after the starter farm, about the price of an early machine. Ring 2
fits mid-game automation income, and ring 3 is the long tail for a full factory. The whole
garden costs 1,027,500 coins. No level gate or parts. The balance model below does not buy
sections, so its milestone estimates are unchanged. Purchases go through `PlotBuySection`
([plots.md](plots.md#buying-space)) and play the purchase sound through
GardenEvents.SectionBought, without counting as buying seeds or a Shipping Bin.

## Selling and XP

`Sell("Held" | "All")` rechecks DataReady, the living character, stall reach and cooldown.
Held removes only the selected stack. All removes every sellable stack, preserving tools,
seeds, machines, decorative blocks, ores and bars. InventoryService applies the removal as
one transaction and sends one final snapshot. GardenService prices removed items and awards
coins and XP without yielding. Rejected sales resync inventory and show a refusal toast.

`Inventory/Items` generates crop values from `World.CROPS`; mutation values already include
the multiplier. Selling sums `item.value * count` and never multiplies twice. Processed product
values live in `Shared/Factory/Products`: Flour 40 (from 2 Wheat, worth 24), juices 3.5x one fruit
(from three), pies 250 / 400 / 600, and crates 12x the crop (from ten). Every product is worth
more than its plain inputs, which rewards building the line. A batch of mutated inputs makes a
mutated product worth the same multiplier (ten Golden Carrots make a Golden Carrot Crate at
x20), so processing keeps a mutation's premium; a batch never mixes variants. Seeds are not
sellable, so buying/selling a seed cannot create currency.
A Shipping Bin on a plot pays its owner per item (factory.md).

Harvest XP is Common 1, Uncommon 2, Rare 4, Epic 8, Legendary 15 and Mythic 30, once per
successful hand or machine harvest, independent of yield and mutation. The source is
`Economy/Content.RARITIES`. Selling gives `floor(transactionCoins / 10)` XP per transaction;
fractional remainders do not carry. Digging up unripe crops does not award XP.

EconomySync sends `{coins, xp, level}`. Read-only player attributes `Coins`, `Xp`, `Level`
mirror it so a late-binding wallet can recover its initial state. Leaderstats still show
Coins and Level. Level is never separately saved. EconomyClient exposes the latest snapshot
and one changed signal. First harvest also marks the crop id in saved `discovered`.

## Hub and screens

HubService stands four soft, non-colliding stalls at runtime under Workspace.Hub: SeedShop,
SellStand, GearShop and MachineShop, each its `Assets.Props` model or a plain placeholder.
Positions and transaction reach live in Shared/Hub: the stalls are at world (-24, 0, -15),
(24, 0, -15), (-24, 0, 15) and (24, 0, 15), clear of spawn and the quarry. Each counter contains Prompt
with ActionText Shop/Sell, ten-stud activation and no line-of-sight requirement. The server
allows twelve studs from the stall's interaction point to tolerate movement during transit.
The client checks the same reach, closes out of range/on death, and treats the server reply
as authoritative.

`libraries/Screens` arbitrates Backpack, MachinePanel, Shop and Sell. `HubWindow` owns
stall prompt binding, UIScale pop, Close, gamepad B, selection trapping/restoration and reach
closing. Buttons use `libraries/UI`; icons use `ItemIcon`. Disabled or pending buttons show
text feedback as well as a muted appearance. Reduced motion skips spatial pops/XP animation.

One `HUD.Shop` window serves three stalls: whichever stall's prompt opened it decides the
catalogue (`HubWindow.bind` takes a list of stalls and tells the screen which one). The Seed
Shop shows stock and the restock countdown; the Gear Shop and Machine Shop
(`Shared/Economy/Shops`: price, unlock level and category per item) never run out. A row's
`Rarity` label shows the rarity or category, `Stock` shows stock or "Lv N" while locked, and
the button reads Buy, Need coins, Locked, Owned (a tool you carry) or Sold out. A tier 2 machine
also costs Workbench parts: its row lists them in `Stock` ("+ 6 Gear, 3 Steel Frame") and the
button reads "Need parts" until you carry them all. The server rechecks level, ownership,
room, every part, coins and reach before changing anything, then takes coins and parts and
gives the machine in one step. Rows sort by rarity or category and level,
then price. No price is
sent back as authority. Sell previews the held-stack and whole-inventory totals.

## Authored HUD contract (place file only)

Author these source HUD instances with `ResetOnSpawn = false`,
safe-area insets, responsive sizing and useful selection/scroll layout in Studio. A missing
or mistyped node warns once through `libraries/Hud`; that screen returns without throwing.
Each screen under `controllers/UIController` receives `init(hud)`.

```text
StarterGui.HUD [ScreenGui]
  Wallet [Frame]                         moved to the bottom-left corner by Wallet.luau
    Coins [TextLabel]                   formatted 1,234
    Level [TextLabel]                   Lv 3
    XpBar [Frame]
      Fill [Frame]                     tweened X.Scale 0..1
      Text [TextLabel]                 optional; "120 / 450 XP" (made plain if missing)
  Weather [Frame]                       initially hidden
    Title [TextLabel]                   Rain / Thunderstorm / Golden Hour
    Time [TextLabel]                    1:42
  Toasts [Frame]                        UIListLayout; at most four clones
  Shop [Frame]                         initially hidden
    UIScale [UIScale]
    Header [Frame]
      Title [TextLabel]
      Close [TextButton]
    Body [Frame]
      Restock [TextLabel]               Restocks in 3:12
      List [ScrollingFrame]            UIListLayout; AutomaticCanvasSize Y
  Sell [Frame]                         initially hidden
    UIScale [UIScale]
    Header [Frame]
      Title [TextLabel]
      Close [TextButton]
    Body [Frame]
      Held [TextLabel]                  Golden Carrot x4 — 1,440
      SellHeld [TextButton]
        Label [TextLabel]
      Total [TextLabel]                 Everything: 3,210
      SellAll [TextButton]
        Label [TextLabel]

ReplicatedStorage.Assets.UI
  Shop [Folder]
    Row [Frame]
      Icon [ViewportFrame]
      Name [TextLabel]
      Rarity [TextLabel]                colour from Economy/Content.RARITIES
      Price [TextLabel]
      Stock [TextLabel]                 x3 / Sold out
      Buy [TextButton]
        Label [TextLabel]
  Toast [Folder]
    Toast [TextLabel]                   expires after 2.5s; fades for 0.25s
```

Wallet, Weather, Toasts, Shop and Sell each have their own client module. Existing
BlockInfo and its row template show crop stage, mutation, countdown and ripe harvest value.
No row sizes, fonts, responsive breakpoints or UI geometry are generated by these modules;
those belong to the authored assets. Existing Backpack/MachinePanel contracts still apply.

## Studio verification still required

1. Fresh join: wallet agrees with leaderstats, XP fills correctly across a level, stock
   arrives even if the HUD binds late. All twelve seeds have icons and rarity labels.
2. Shop: buy one and several via remote, exhaust stock, lack coins, full inventory, fractions,
   NaN/infinity, unknown ids, spam, remote actions from outside reach and before DataReady.
   Verify no lost coins/stock and no stuck pending button after rejection.
3. Sell a mutated held stack (four Golden Carrots = 1,440 coins), then Sell All with mixed
   sellable/non-sellable inventory. Check one-time payout, floor XP and preserved non-sellables.
4. Grow all twelve crops, including borrowed art. Singles give no ripe seed; unripe digging
   returns one. Multi hand/machine harvests remain planted, reroll once per regrow and respect
   full inventory/output. Two players cannot harvest each other's crops.
5. Save/rejoin in another plot during initial growth, during regrowth, during rain, and with
   both plain and mutated ripe fruit. Check preserved stock in-window, rerolled stock after
   boundary, discoveries, harvest count, offline growth and no repeated weather credit.
6. Exercise Rain, Thunderstorm and Golden Hour: calm transitions, banner deadline, accelerated
   growth across start/end/save, mutation chances, reduced motion, covered-camera rain and
   Rainbow tint. Check crop effects clean up when harvested or streamed out.
7. Feed a mix of plain and mutated inputs: each batch uses one variant and makes that
   variant's product (Golden in, Golden out), rare ones waiting without blocking plain ones.
   Save/break a machine mid-recipe and verify exact input variants return. Open a filter
   pick's mutation arrow, tick one and check only that variant goes to its side. Back up a
   Harvester with fewer free slots than a fruit yield.
8. Open all four windows in turn; Close/B, walking away, death, respawn, controller focus,
   mouse/gamepad switching, disabled buttons, row scrolling, toast limit and expiration.
   Inspect desktop, narrow portrait, mobile landscape, tablet and console sizes in Studio.

Repository formatting, lint, type analysis and content/remote consistency checks do not
replace these tests. Studio execution was unavailable in this implementation session because
the tool required approval under an approval policy of `never`; the place was not modified.

## Balance

Run `python tools/balance/model.py` from the repo root; add `--plain` to remove all
mutations, or `--runs N` to sample more reproducible stock rolls. No dependencies are needed.
The script reads the Luau content owners and compares against `tools/balance/before.json`,
the pre-polish numeric fixture. That fixture has no onboarding rewards; current runs read
the rewards from `Shared/Onboarding`. The fixture is historical evidence, never game content.

The model starts with DataService's 50 coins, ten Carrot Seeds and five Wheat Seeds, one
96-cell farm, two seconds per hand action, twenty seconds per round trip to the hub, and
Sell All about once a minute. It rolls every seed's actual stock band every five minutes.
It buys one initial seed for onboarding and one Strawberry plant, saves for the Shipping
Bin, then expands toward twelve Wheat and twenty-four Strawberry plants. Only Common and
Uncommon seeds are used; rare stock and jackpots are unnecessary. Machines are bought as
their unlock and wallet allow, with two ordinary belts budgeted per farm/processing machine.
Optional storage/crafting purchases also debit the same wallet.

After the Harvester, this deliberately modest policy stops hand harvesting and tends a
compact twenty-cell patch (twelve Wheat, eight Strawberry), leaving time for building and
mining. One Harvester and Sprinkler cover that patch; the other soil is expansion headroom.
The Planter fills new soil using purchased seeds, with hand time for loading/repositioning;
the Harvester restarts singles for free. The simulation uses recipe batch times, distinct
mutation queues, and one Shipping Bin capped at sixty items a minute. Wheat goes through the
Mill, fruit through the Juicer, excess fruit through the Crate Packer, and matching flour/fruit
through the Oven once owned. Overflow remains buffered; belt geometry, finite machine
buffers, inventory sorting and repeated manual routing are not simulated. Real layouts
need adequate belt/chest buffering and routes or will be slower.

Mutations contribute expected fractional yields, never a sampled lucky payout. Batches still
need a whole recipe of one variant, so scarce mutations accumulate before they can process.
Clear-weather chances apply for ten minutes, then time-weighted weather chances; sprinkler
Wet chance also applies. Rain growth acceleration is omitted. The estimates below are the
median of nine stock rolls, not a promise or a measured player-session percentile. Continuing
hand farming, covering more of the 96 cells, or planting rare crops can progress faster.

| Milestone (minutes from join) | Before, mutation EV | After, mutation EV | After, plain only |
|---|---:|---:|---:|
| Level 2 | 9.6 | 2.6 | 2.6 |
| Level 3 | 18.8 | 9.0 | 10.0 |
| Level 4 | 27.4 | 17.8 | 19.8 |
| Level 5 | 34.4 | 27.4 | 30.9 |
| Level 6 | 42.7 | 39.0 | 46.1 |
| Level 7 | 53.2 | 58.4 | 70.8 |
| Level 8 | 65.8 | 85.9 | 106.0 |
| Level 9 | 82.1 | 130.7 | 155.3 |
| Level 10 | 96.8 | 177.1 | 217.1 |
| Level 11 | 106.9 | 208.3 | 262.6 |
| Level 12 | 117.9 | 249.4 | 321.8 |

| Stage, net coins/minute | Before, mutation EV | After, mutation EV | After, plain only |
|---|---:|---:|---:|
| Hand farming | 459.2 | 563.3 | 427.8 |
| Shipping Bin + Harvester + Planter + Sprinkler | 1,079.5 | 1,079.2 | 770.0 |
| With processors, across levels 7-12 | 1,774.3 | 2,002.6 | 1,443.4 |

Income is realized sales less purchased seeds, averaged over time in that stage. It excludes
onboarding grants and capital purchases; it is not the wallet's rate of change. Processor
income includes the faster Oven stage, not just a Mill. Different stage durations explain
different averages even though crop values and machine speeds remain unchanged.

Machine affordability is the first time both the unlock level and coin price are met, after
earlier purchases. It is not a claim that all machines sharing a level can be bought at once.
Tier-two rows observe the wallet without buying an upgrade: add the supplied crafting time
if its parts have not already been made. A player can start making them after level three.

| Machine | Level | Before coin-affordable (min) | After coin-affordable (min) | After purchased (min) |
|---|---:|---:|---:|---:|
| Shipping Bin | 2 | 9.6 | 2.6 | 3.0 |
| Storage Chest | 2 | 9.6 | 2.6 | 6.8 |
| Smelter | 3 | 18.8 | 9.9 | 10.3 |
| Workbench | 3 | 18.8 | 9.3 | 12.2 |
| Seed Planter | 4 | 27.4 | 17.8 | 18.2 |
| Sprinkler | 5 | 34.4 | 27.4 | 27.7 |
| Harvester | 6 | 42.7 | 39.0 | 39.3 |
| Mill | 7 | 53.2 | 58.4 | 58.4 |
| Juicer | 8 | 65.8 | 85.9 | 85.9 |
| Seed Planter II | 8 | 65.8 | 85.9 | Parts separate |
| Crate Packer | 9 | 82.1 | 130.7 | 130.7 |
| Sprinkler II | 9 | 82.1 | 130.7 | Parts separate |
| Oven | 10 | 96.8 | 177.1 | 177.1 |
| Mill II | 10 | 96.8 | 177.1 | Parts separate |
| Harvester II | 12 | 117.9 | 249.4 | Parts separate |

The Shipping Bin costs 300; the modeled wallet when level two is reached is 479 with
mutation EV and 403 with plain crops, before the stand-sale and level objectives pay.
The hand-to-machine trip
explains purchase at 3.0 minutes rather than 2.6. Harvester purchase is 39.3 minutes with
EV, 46.2 plain: the no-mutation sensitivity is just beyond the approximate 30-45 minute
target, without a stock or coin wall. The Oven is about three hours with EV and 3.6 hours
plain. No rare seeds are needed for either path.
With Common/Uncommon stock held at every band's minimum, level six is 42.4 minutes
with EV (47.6 plain) and level ten is 180.3 (218.6 plain): lower stock slows expansion
without making progression depend on a lucky restock.

The complete balance edits are:

| Owner / number | Before -> after | Reason |
|---|---|---|
| World.CROPS, Strawberry seed | 50 -> 45 | Its first plain harvest yields 3 x 15 = 45; every Common/Uncommon seed now repays in one harvest |
| Economy.required coefficient | 100 -> 20 | The starter harvest/sale can reach level two |
| Economy.required exponent | 1.5 -> 2.75 | Spread later unlocks across a calm three-hour progression rather than compressing the Oven into about 97 minutes |
| Seed Planter II parts | Gear 4 -> 6; Steel Frame 2 -> 3 | Supplied crafting 3.1 -> 4.7 min; 24 iron ore |
| Sprinkler II parts | Circuit 2 -> 6; Copper Wire 2 -> 6 | Supplied crafting 2.3 -> 6.9 min; 18 copper, 12 iron ore |
| Mill II parts | Gear 4 -> 8; Steel Frame 1 -> 2 | Supplied crafting 2.4 -> 4.7 min; 24 iron ore |
| Harvester II parts | Circuit 4 -> 6; Steel Frame 2 -> 3 | Supplied crafting 5.3 -> 7.9 min; 12 copper, 24 iron ore |

The model's parts time assumes bars are supplied; it leaves out mining. The first pass sized parts
to 20-30 minutes of supplied crafting, which needed 80-120 iron bars per machine: 120 hand-mined
ore from three shared iron rocks (2 ore every 45 s each), a grind wall the calm target rules
out. The parts were sized down so a tier 2 machine is 24-36 bars of ore, about 5 minutes of
mining plus 5-8 minutes of smelting and crafting: roughly 15 minutes of real effort.

Each tier-two bundle now needs 24-36 bars (4-6 minutes of Smelter operation, 8-12 Coal) and
recursive Workbench operations. The table adds all Workbench time serially as a conservative
upper bound; feeding the Workbench while smelting approaches the smelting time plus the last
part. Ore/coal collection, loading and quarry contention add real time. Farm income during
crafting covers the unchanged coin prices. Keeping the ten-second bars and quick part
recipes preserves visible flow rather than making a single machine operation feel slow.

All valued products already beat their immediate inputs, both plain and in each of the
four mutations; the script asserts this for every recipe. Product prices, growth times,
yields, rarity stock bands, harvest XP, unlock levels, machine prices and speeds are unchanged.
The resulting curve is `round(20 * n^2.75)` additional XP from level n. Existing lifetime
XP is preserved, so returning players' displayed levels can move when recalculated.

Studio verification remains: timed fresh sessions, low-stock windows, actual belt/chest
backpressure, hand loading and routing overhead, quarry supply, and how much players keep
hand farming after automation. The model is a reproducible balance hypothesis, not runtime QA.

## Onboarding

`Shared/Onboarding.STEPS` is the content owner. `OnboardingService` observes server
`GardenEvents` and pays through EconomyService. There is no inbound objective remote and
no tutorial gate; ordinary play can satisfy later steps before their prompts appear.

| Step | Objective | Server evidence | Coins |
|---|---|---|---:|
| 1 | Buy seeds at the Seed Shop | Bought a World.PLANTS seed | 10 |
| 2 | Plant a seed on your farm | Planted, or restored crops/discoveries | 10 |
| 3 | Harvest a ripe crop | Harvested, or restored discoveries | 20 |
| 4 | Sell your harvest at the Sell Stand | Sold with positive coins and no position | 20 |
| 5 | Reach level 2 | LevelUp >= 2, or current level already >= 2 | 30 |
| 6 | Buy a Shipping Bin at the Machine Shop | Bought ShippingBin, or restored owned Bin | 20 |
| 7 | Place your Shipping Bin on your plot | Placed ShippingBin, or restored placed Bin | 50 |

Each completion advances the saved next step before paying once and sending
`Done! +N coins`; completion sends `Your garden is yours to grow. Happy gardening!`.
Total rewards are 160 coins. There is no extra finishing grant. Earlier live actions are
remembered for the session; restored crops, discoveries, level and inventory/placed Bin
provide evidence on rejoin. A starter seed is not evidence of buying, and a Shipping Bin
sale is not evidence of selling at the stand. Those two events must be observed live.
Only the next step persists, with the profile integration in [plots.md](plots.md#profile-contents).

The server sends `Objective {step, total, text, done}` on load and every step change.
Its read-only `OnboardingStep` player attribute lets a late HUD recover without a client
request. `UIController/Objective` receives `init(hud)`, binds with `Hud.find`, warns once
for missing/mistyped nodes, and leaves gameplay usable if the authored screen is absent.

```text
StarterGui.HUD.Objective [Frame]       top-left below side buttons; initially hidden
  Title [TextLabel]                    Next step
  Text [TextLabel]                     current objective
  Progress [TextLabel]                 Step 2 of 7
  Check [ImageLabel or Frame]          initially hidden
```

A completion shows the check and softly fades the old text for 0.3 seconds, then displays
the latest objective. Later updates cancel old tweens; finishing hides the panel. Reduced
motion applies the new state immediately, including if enabled mid-transition. Baseline
transparencies come from the authored objects, and HUD destruction disconnects listeners
and invalidates delayed transitions. Place-file layout and assets remain Studio work.

Verify in Studio: fresh profile through all seven steps; plant/harvest/buy/place ahead of
the prompt; already-level-two and already-owned/placed Bin; machine sales not counting as
stand sales; duplicate events not repaying; rejoin at each step and after completion;
corrupt/missing step sanitization; late/missing HUD; rapid multi-step advancement; reduced
motion and respawn. Static checks do not verify these interactions.
