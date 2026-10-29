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

## Selling and XP

`Sell("Held" | "All")` rechecks DataReady, the living character, stall reach and cooldown.
Held removes only the selected stack. All removes every sellable stack, preserving tools,
seeds, machines, decorative blocks, ores and bars. InventoryService applies the removal as
one transaction and sends one final snapshot. GardenService prices removed items and awards
coins and XP without yielding. Rejected sales resync inventory and show a refusal toast.

`Inventory/Items` generates crop values from `World.CROPS`; mutation values already include
the multiplier. Selling sums `item.value * count` and never multiplies twice. Processed product
values live in `Shared/Factory/Products`: Flour 40 (from 24 of wheat), juices 3.5x one fruit
(from three), pies 250 / 400 / 600, and crates 12x the crop (from ten). Every product is worth
more than its plain inputs, which rewards building the line; processing a valuable mutation
intentionally loses its premium, so a Filter Conveyor that sends mutations to the bin pays. Seeds are not sellable, so buying/selling a seed cannot create currency.
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

HubService builds soft, non-colliding SeedShop and SellStand models at runtime under
Workspace.Hub. Positions and transaction reach live in Shared/Hub: stalls are at world
(-24, 0, -15) and (24, 0, -15), clear of spawn and the quarry. Each counter contains Prompt
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
also costs Workbench parts: its row lists them in `Stock` ("+ 4 Gear, 2 Steel Frame") and the
button reads "Need parts" until you carry them all. The server rechecks level, ownership,
room, every part, coins and reach before changing anything, then takes coins and parts and
gives the machine in one step. Rows sort by rarity or category and level,
then price. No price is
sent back as authority. Sell previews the held-stack and whole-inventory totals.

## Authored HUD contract (place file only)

The repo never creates or edits these UI instances. Author HUD with `ResetOnSpawn = false`,
safe-area insets, responsive sizing and useful selection/scroll layout in Studio. A missing
or mistyped node warns once through `libraries/Hud`; that screen returns without throwing.
Each screen under `controllers/UIController` receives `init(hud)`.

```text
StarterGui.HUD [ScreenGui]
  Wallet [Frame]
    Coins [TextLabel]                   formatted 1,234
    Level [TextLabel]                   Lv 3
    XpBar [Frame]
      Fill [Frame]                     tweened X.Scale 0..1
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
7. Process mixtures of plain/mutated inputs, collect plain products, then save/break a machine
   mid-recipe and verify exact input variants return. Filter a specific mutation separately
   from its plain crop. Back up a picker with fewer free slots than a fruit yield.
8. Open all four windows in turn; Close/B, walking away, death, respawn, controller focus,
   mouse/gamepad switching, disabled buttons, row scrolling, toast limit and expiration.
   Inspect desktop, narrow portrait, mobile landscape, tablet and console sizes in Studio.

Repository formatting, lint, type analysis and content/remote consistency checks do not
replace these tests. Studio execution was unavailable in this implementation session because
the tool required approval under an approval policy of `never`; the place was not modified.
