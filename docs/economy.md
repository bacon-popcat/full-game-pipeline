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

A fresh roll that holds an Epic or better seed sends a Stock notice (a top banner that opens the Shop when clicked) naming them, rarest first,
under the rarest's name ("Legendary seed in stock! Grape Seeds, Pumpkin Seeds"), so a rare roll
is seen without opening the Shop. A garden that loads with such seeds still in stock says so
four seconds after it opens, once the save menu has cleared.

A purchase accepts a known seed id and positive finite integer count no greater than the
player's stock. The player must have DataReady; shops and selling work from anywhere, so
there is no stall reach check. Purchases and sales share a 0.2-second action cooldown. The server
checks the whole inventory addition before `EconomyService.trySpend`, then gives the seeds
and reduces stock without yielding. No coins or stock are lost to a full inventory.
The UI buys one seed per press; the server supports larger validated counts.

`ShopSync` sends `{restockAt, stock}` on load, restock, purchase response and Seed Shop
prompt activation. Prompt refresh recovers from a load sync that preceded HUD binding.
`ShopBuy(shopId, itemId, count)` is intent only; `shopId` names the stall. `Notify(message, kind, detail)` explains purchases, refusals and
rare harvests; `Shared/Notices` owns the kinds (colour, sound, lifetime, stack or banner), the detail and which messages are worth one. All remote instances/payloads are owned by `default.project.json` and
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

`Sell("Held" | "All")` rechecks DataReady and the cooldown; it works from anywhere.
Held removes only the selected stack. All removes every sellable stack, preserving tools,
seeds, machines, decorative blocks, ores and bars. InventoryService applies the removal as
one transaction and sends one final snapshot. GardenService prices removed items and awards
coins and XP without yielding. Rejected sales resync inventory and show a refusal toast.

`Inventory/Items` generates crop values from `World.CROPS`; mutation values already include
the multiplier (stacked mutations add their bonuses, farming.md § Mutations). Selling sums `item.value * count` and never multiplies twice. Processed product
values live in `Shared/Factory/Products`: Flour 40 (from 2 Wheat, worth 24), juices 4.5x one fruit
(from three, so one machine adds half again), pies 250 / 400 / 600, and crates 12x the crop (from ten).
The mid-game products (crisps, popcorn, sauces, jams, tarts, sorbets; factory.md § Processors)
have no written value: each is worth the crops inside it times 1.5, 3 or 4.5 by how many
machines deep it is (§ Balance, Mid-game products). Every product is worth
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

HubService stands five soft, non-colliding stalls at runtime under Workspace.Hub: SeedShop,
SellStand, GearShop, RobuxShop and OrdersBoard, each its `Assets.Props` model or a plain
placeholder (the Robux Shop borrows the old `MachineShop` prop until it has its own). The Orders
Board, a notice board with a counter at (-48, 0, 16), faces east and opens the Quests window on
Orders (progress.md); it stands south of the hub's east-west line so it never hides the
leaderboards, which LeaderboardService stands at (-72, 0, 0) (social.md).
Positions live in Shared/Hub: the stalls are at world (-24, 0, -15),
(24, 0, -15), (-24, 0, 15) and (24, 0, 15), clear of spawn and the quarry. Each counter contains Prompt
with ActionText Shop/Sell, ten-stud activation and no line-of-sight requirement. A prompt opens
its window, and so do the authored `SideButtons.Shop` and `SideButtons.Sell` from anywhere:
buying and selling need no walk to the hub. The Shop window is a left rail of tab tiles
(`Body.Tabs.SeedShop` and `GearShop`, the restock timer under them) beside a grid of tall cards;
the selected tab is opaque and the side button reopens the last one. The Robux Shop is its own
`HUD.Robux` window, opened by the Robux stall or the Menu popup's `Robux Shop` row (there is no
Robux side button; `UIController/RobuxScreen`). Windows close on Close, gamepad B or losing DataReady, and
treat the server reply as authoritative.

`libraries/Screens` arbitrates Backpack, MachinePanel, Shop, Robux, Sell and Settings. `HubWindow` owns
stall prompt binding, opening from a side button, Close, gamepad B and selection
trapping/restoration. Buttons use `libraries/UI`; icons use `ItemIcon`. Disabled or pending buttons show
text feedback as well as a muted appearance. Reduced motion skips spatial pops/XP animation.

One `HUD.Shop` window serves two stalls: whichever stall's prompt opened it decides the
catalogue (`HubWindow.bind` takes a list of stalls and tells the screen which one). The Seed
Shop shows stock and the restock countdown; the Gear Shop (`Shared/Economy/Shops`: price, unlock
level and category per item) never runs out. No shop sells machines, conveyors or routers: they
are crafted in the Crafting window (factory.md § Crafting). A row's `Rarity` label shows the
rarity or category, `Stock` shows stock or "Lv N" while locked, and the button reads Buy, Need
coins, Locked, Owned (a tool you carry) or Sold out. The server rechecks level, ownership, room,
coins and reach before changing anything, then takes coins and gives the item in one step. Rows
sort by rarity or category and level, then price.

The Robux window lists `Shops.ROBUX_PACKS`: coin packs priced in Robux (`R$ 49` for 2,500 coins up to
`R$ 499` for 40,000) as `Assets.UI.Robux.Pack` cards (a coin, the name, its coins, a `Buy` button
reading its price). Buy sends
`ShopBuy("RobuxShop", packId)`; GardenService shows Roblox's purchase prompt for the pack's
developer product, and `MonetizationService` grants the coins from `ProcessReceipt`, keeping the
last 50 granted PurchaseIds in the save (`receipts`) so a resent receipt never pays twice. Every
pack's `productId` is 0 until its developer product exists on the Creator Dashboard; until then
Buy only says the pack isn't on sale yet. No price is
sent back as authority. Sell previews the held-stack and whole-inventory totals.

## Authored HUD contract (place file only)

Author these source HUD instances with `ResetOnSpawn = false`,
safe-area insets, responsive sizing and useful selection/scroll layout in Studio. A missing
or mistyped node warns once through `libraries/Hud`; that screen returns without throwing.
Each screen under `controllers/UIController` receives `init(hud)`.

The always-on pieces (SideButtons, Wallet, Objective, Weather, Toasts, ItemName, and the
Slot and Toast templates inside them) are authored in Scale so they scale with the device.
Each piece's Size is its share of a 1280x720 reference screen (`Hud.REFERENCE_WIDTH` and
`REFERENCE_HEIGHT`), and a UIAspectRatioConstraint keeps its shape, so it follows whichever
screen axis is tighter. A 4:3 tablet therefore scales by width, while 16:9 and wider screens
scale by height. Their contents are Scale shares of the piece, and single-line text is
TextScaled in a box trimmed to the authored text height, capped at twice that by a
UITextSizeConstraint. The objective's wrapped body text is capped at its authored size.
The objective sits 58 px (Roblox's topbar) plus a Scale gap from the top. Code that sizes
these pieces in pixels uses `Hud.zoom` and follows the same rule: the hotbar's slots, gaps
and margin in InventoryScreen, and ItemGained's code-built cards. There are no minimum
sizes, because on a phone a floor pushes the left column and the hotbar into each other.
So a 390 px tall phone draws the HUD at about half size (28 px side buttons). The wallet,
item cards and side column can also sit under Roblox's touch thumbstick and jump button
there, since the arrangement is the desktop one.

The side column is, top to bottom, Shop, Crafting, Sell, Research, Quests and Menu.
`SideButtons.Menu` opens the small `HUD.Menu` popup ([progress.md](progress.md#screens)), whose
rows are Index, Achievements, Stats, Robux Shop and Settings, and whose
Settings row opens the authored `HUD.Settings` frame (Settings registers its opener with
`libraries/Screens`; there is no Settings side button), with `Header.Close`,
`Header.Title`, `Body.MusicVolume` and `Body.SfxVolume` (each a `Track` TextButton holding
`Fill` and `Knob`, and a `Value` TextBox), `Body.Note`, `Body.ControlsHint` and the
`Body.LightingQuality` (Low, Medium and High buttons; lighting.md), `Body.Gifting` (On and Off; social.md), the
`Body.SaveQuit` button (back to the save menu, plots.md § Save files). Clicking or
dragging a track, or typing 0-100 in its box, sets that session volume (`libraries/AudioSettings`:
music and every `Sound.play` effect each play through their own SoundGroup).
Settings has music and sound volume sliders and input-specific quick controls. The five main windows
(Backpack, MachinePanel, Shop, Sell, Settings) are centred on the screen (anchor 0.5, 0.5,
size 0.94 x 0.72 scale (Settings 0.8), UISizeConstraint caps of 1040x580, 880x500, 700x520,
510x300 and 530x470), with BackgroundTransparency 0.2, and share authored header subtitles, dividers and a
garden-green top accent. The Backpack (and the MachinePanel, which copies it) stays centred but
is sized by InventoryScreen to end 12 px above the hotbar. While any of them is open,
`libraries/Backdrop` darkens the world through the authored `HUD.Backdrop` frame (ZIndex 0,
under every other HUD node, so the hotbar and wallet stay clear) and a private `PopupBlur`.
`libraries/PopupMotion` owns their scale-and-content entrance and shrink exit (and, for these
modal windows, the backdrop), plus the
scale transitions for Weather and BlockInfo. Each popup requires an authored UIScale.
Closing disables interaction immediately; rapid reopen cancels the old exit. Reduced motion
settles immediately, including when enabled during a transition. Notification templates also
carry a UIScale for an entrance pop and a shrinking fade on expiry.
Every modal window (ZIndex 30) also plays `libraries/WindowReveal` as it opens: its outline
flashes and settles, its corner brackets snap in from outside as their arms draw out, the Accent
springs out from its middle, a light with a spinning glint runs along `Header.Divider` (its
authored `Sweep.Light` and `Glint`), and Body's content fades and rises in a springy cascade, top
to bottom, finished within 0.4 s however long the list (rows outside their scroller are left
alone). It plays only on an open, never on a re-render, never waits on input, and is settled at
once by every close. A window's `Cascade` attribute (false on the Welcome card, which pops its own
parts) turns the cascade off; a Vector2 `CascadeOffset` moves where its pieces come from (the
Menu's rows slide in from the left).
Moments a screen calls go through `libraries/Flair`: `pulse` (a pop with a sweeping flash: a
purchase, a craft, a claimed quest), `refuse` (a damped side-to-side shake, the cost or status
flashing `TextColors.BAD`: a refused or impossible purchase or craft), `burst` (spark images flying
from a piece, drawn on the authored `HUD.Fx` layer at ZIndex 60 from a fixed pool) and
`attention` (an idle beat on something waiting: the Quests badge, a ready Claim, an affordable
crafting upgrade). Bars and counters ease to new values through `libraries/BarMotion`, and a
window with tabs (Quests, the Shop's stalls, Crafting's categories) slides a highlight between
them through `libraries/TabSlide`.
The Settings controller binds these nodes; `libraries/AudioSettings` owns the session-only
music and sound volumes through SoundGroups, preserving MusicController's track fades.
Side buttons use centred image icons (an ImageLabel `Icon`, `Shared/Icons`' white glyphs tinted
by `ImageColor3`; assets/icons/README.md) and authored `Tooltip` frames to their right;
`libraries/UI.bindButton` shows those labels on mouse hover or gamepad focus, hiding them
on exit or touch input. Labels expand right and fade in, then retract left and fade out;
interrupted tweens reverse from their current state, and reduced motion skips the transition.
The same layer springs a hovered button up and brightens its own stroke, squashes it on press
and springs it back on release, makes an image `Icon` hop and wobble once as the pointer
arrives, and hands a click on a button that is not Active to the screen's `onRefused`. The Menu
rows, every window's close button (a Cross) and the search boxes use the same glyph family; the
images and the nodes they replaced are authored by `tools/hud/polish_hud.luau`.
`PromptController` maps world proximity prompts to `Controls.INTERACT`, reserving the
inventory binding for inventory even beside shops and section purchases, and draws every
prompt in the Custom style: a clone of `Assets.UI.Prompt.Card` (authored by
`tools/hud/prompt_hud.luau`) with a key cap that fills while held, the action, the object and
an optional status line; a tap or click on the card holds the prompt, which is how touch works
it. A prompt with the `Highlight` attribute also outlines its model while its card shows.

```text
StarterGui.HUD [ScreenGui]
  Wallet [Frame]                         bottom-left in Scale, see-through, balance counts and pops (Wallet.luau)
    Coins [TextLabel]                   formatted 1,234
    Level [TextLabel]                   Lv 3
    XpBar [Frame]
      Fill [Frame]                     tweened X.Scale 0..1
      Text [TextLabel]                 "120 / 450 XP"
  Weather [Frame]                       initially hidden
    Title [TextLabel]                   the event name (Shared/World/Weather)
    Time [TextLabel]                    1:42
  DayClock [Frame]                      optional; top-right time of day, to the minute (DayClock.luau builds it if absent)
    Icon [Frame], Time, Phase [TextLabel], Bar.Fill [Frame]
  Toasts [Frame]                        bottom-stacked UIListLayout; at most four slots; Toasts.luau
                                        keeps it just above ItemName, so notices sit over the hotbar
  Banner [Frame]                        top centre, under Weather; holds one Banner card at a time (UIScale)
  Fx [Frame]                            full screen, clear, ZIndex 60, not interactable: Flair's sparks
  Shop [Frame]                         initially hidden
    UIScale [UIScale]
    Header [Frame]
      Title [TextLabel]
      Close [TextButton]                Icon [ImageLabel] (Cross), UIScale
      Divider [Frame]                   Sweep (clipping) > Light [Frame], Glint [ImageLabel]; hidden at rest
    Body [Frame]
      Tabs [Frame]                      SeedShop and GearShop tiles, a vertical rail
      Restock [TextLabel]               Restocks in 3:12
      List [ScrollingFrame]            UIGridLayout of cards; AutomaticCanvasSize Y
  Robux [Frame]                        initially hidden; Header like Shop's
    Body.List [ScrollingFrame]         UIGridLayout of Assets.UI.Robux.Pack
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
  Robux [Folder]
    Pack [Frame]                        Coin, Name, Coins, Caption, Buy [TextButton] (Label)
  Toast [Folder]
    Toast [Frame]                       a stack slot (UIScale) holding Card [TextButton]: Border, UIScale,
                                        Icon, Item [ViewportFrame], Text, Count, Go
    Banner [TextButton]                 the banner card: Border, UIScale, Brackets, Row (Icon, Item,
                                        Column (Title, Text), Go)
    Icons [Folder]                      one white ImageLabel per notice kind (Shared/Icons; Toasts tints it)
                                        All built by tools/hud/notice_hud.luau, the icons then swapped
                                        by polish_hud.luau; Toasts.luau's header owns how they behave
  Tab [Folder]
    Highlight [Frame]                   the box TabSlide slides between tabs (UICorner, UIStroke, UIGradient)
  Flair [Folder]
    Flash [Frame]                       a bright band (UIGradient) Flair.pulse sweeps across a piece
    Spark [ImageLabel]                  one spark of a Flair.burst, cloned into HUD.Fx's pool
```

Wallet, Weather, Toasts, Shop and Sell each have their own client module. Existing
BlockInfo and its row template show crop stage, mutation, countdown and ripe harvest value.
No row sizes, fonts, responsive breakpoints or UI geometry are generated by these modules;
those belong to the authored assets. Existing Backpack/MachinePanel contracts still apply.
The Index window (opened from the Menu popup) is in [inventory.md](inventory.md#index); the Research
window and its side button in [research.md](research.md#window), and the Crafting window in
[factory.md](factory.md#crafting).

`HUD.NowPlaying` is a small card at the top right, in the top bar's row so it sits above
Roblox's player list: Caption ("Now playing"), Title (the track), three Bars, Brackets and a
UIScale, authored in Scale with a UIAspectRatioConstraint and a 320 x 46 px cap. MusicController
sets the playing track's name as SoundService.Music's `Track` attribute;
`UIController/NowPlaying` slides the card in from the right when it changes, bobs the bars for
six seconds and slides it out (reduced motion: in place, still bars).

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

Run `python tools/balance/model.py` from the repo root. Flags: `--plain` removes all mutations,
`--runs N` samples more reproducible stock rolls, `--miners N` is how many players mine the
quarry at once, `--quarry-share S` (0-1] scales this player's share of it further, and
`--build-share B` (0-1) is the share of hand time gathering trips may take from farming. No dependencies are needed. The script reads the Luau content
owners (crops, rarities, products, `Shared/Crafting`, the research a recipe needs, the quarry
and forest nodes) and compares against `tools/balance/before.json`, the pre-polish fixture,
which still has the coin Machine Shop. The fixture is historical evidence, never game content.
The last runs are in `tools/balance/results-ev.md` and `results-plain.md`.

**The policy** (the script's header owns every assumption). A new player has 50 coins, tools and an
all-grass garden, and crafts from the side Crafting button. Each hand action takes two seconds; selling and seed
buying work from anywhere; every planted cell is tilled first. The player hand-farms up to 8
Carrot, 12 Wheat and 24 Strawberry cells from the actual stock rolls (no Rare+ seeds) and
crafts the machines in one fixed order: Shipping Bin, Smelter, Workshop tier, Assembler, Seed
Planter, Sprinkler, Machine Works tier, Harvester, Mill, Juicer, Crate Packer, Oven, with four
belts for the Harvester line and two per processor. Wood comes from the forest and stone, coal
and ore from the hub quarry (a 20 s round trip each; rocks respawn on their own timers); bars
smelt at 10 s each on coal and parts are made on one Assembler. Gathering trips take up to half
of hand time and farming has the rest. After the Harvester the player stops hand harvesting and
one Harvester, Sprinkler and Planter tend a 20-cell patch (12 Wheat, 8 Strawberry); wheat goes
through the Mill, fruit through the Juicer and Crate Packer, flour and fruit through the Oven,
and one Shipping Bin sells at most sixty items a minute.

Left out: belt geometry and backpressure, placing and collecting time, inventory limits, weather
growth, research bonuses, the Rock Drill, digging the plot's own stone, buying Stone or Wood
Planks from the Gear Shop, garden sections and Mk II machines. Mutations are expected fractional
yields, never a sampled lucky payout. The numbers are medians of nine stock rolls: a
reproducible hypothesis, not a measured player session.

### Levels

| Milestone (minutes from join) | Coin shop (before.json) | Crafted, mutation EV | Crafted, plain only |
|---|---:|---:|---:|
| Level 2 | 9.6 | 1.9 | 2.0 |
| Level 3 | 18.8 | 8.1 | 8.0 |
| Level 4 | 27.4 | 14.9 | 15.8 |
| Level 5 | 34.4 | 21.0 | 23.5 |
| Level 6 | 42.7 | 26.2 | 28.6 |
| Level 7 | 53.2 | 32.2 | 34.8 |
| Level 8 | 65.8 | 37.3 | 41.1 |
| Level 9 | 82.8 | 43.8 | 46.7 |
| Level 10 | 99.4 | 48.5 | 51.9 |
| Level 11 | 109.4 | 52.7 | 58.4 |
| Level 12 | 120.4 | 59.9 | 66.4 |
| Level 15 (extrapolated) | 162.7 | 86.2 | 100.8 |
| Level 20 (extrapolated) | 270.3 | 165.1 | 203.6 |
| Level 30 (extrapolated) | 640.6 | 514.2 | 658.1 |
| Level 40 (extrapolated) | 1,258.2 | 1,237.0 | 1,599.0 |
| Level 50 (extrapolated) | 2,161.8 | 2,481.9 | 3,219.9 |

The coin-shop column is the original `100 * n^1.5` curve with machines bought at their unlock
level. Levels 2-12 are simulated. Levels 13-50 are extrapolated: the model plays one more hour
after level 12, takes the XP per minute earned in that hour (about 340 with mutation EV, 260
plain; every tier-one machine owned, no new soil, no Mk II machines, no rare crops) and holds
it flat. Real players keep expanding, which raises the rate, so those times are upper bounds
for an engaged player: level 20 in about 2.8 hours (3.4 plain), level 30 in about 8.5 (11),
level 50 in about 41 (54).

Lifetime XP at the milestones (`Economy.required(n)` is the cost of advancing from level n):

| Level | 2 | 5 | 10 | 12 | 15 | 20 | 30 | 40 | 50 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Lifetime XP to reach it | 12 | 428 | 4,562 | 8,338 | 17,321 | 44,071 | 162,431 | 407,448 | 829,520 |
| Cost of the level before it | 12 | 236 | 1,351 | 2,081 | 3,494 | 6,738 | 16,724 | 31,621 | 51,654 |

### Crafted machines

Minutes from join when each is crafted, with the quarry to yourself. Raw is what one costs from
an empty inventory, its belts and the Smelter's coal included.

| Step | Crafting tier | Mutation EV | Plain | Level then | Raw |
|---|---:|---:|---:|---:|---|
| Shipping Bin | 1 | 2.5 | 2.5 | 2 | 3 wood |
| Smelter | 1 | 3.6 | 3.6 | 2 | 16 stone, 1 wood |
| Workshop (tier 2, level 3) | - | 8.1 | 8.1 | 3 | 8 iron, 3 coal, 30 stone, 10 wood |
| Assembler | 2 | 11.1 | 11.7 | 3 | 8 iron, 2 copper, 4 coal, 2 wood |
| Seed Planter | 2 | 14.2 | 14.2 | 3 | 10 iron, 4 coal, 2 wood |
| Sprinkler | 2 | 16.1 | 16.1 | 4 | 4 iron, 4 copper, 3 coal |
| Machine Works (tier 3, level 6) | - | 27.8 | 28.8 | 6 | 48 iron, 12 copper, 20 coal, 8 wood |
| Harvester | 3 | 33.2 | 34.0 | 7 | 17 iron, 4 copper, 7 coal, 5 wood |
| Mill | 2 | 35.3 | 36.1 | 7 | 7 iron, 3 coal, 20 stone, 3 wood |
| Juicer | 2 | 37.6 | 38.4 | 8 | 11 iron, 4 coal, 1 wood, 4 Glass |
| Crate Packer | 3 | 41.9 | 42.6 | 8 | 17 iron, 6 coal, 5 wood |
| Oven | 3 | 43.9 | 44.5 | 9 | 7 iron, 2 copper, 3 coal, 1 wood, 20 Bricks |

Everything up to the first Harvester costs 95 Iron Ore, 22 Copper Ore, 41 Coal, 46 Stone and
31 Wood, about 14 minutes of hand time gathering (walks, mining, chopping, waiting at rocks)
out of the 34. Alone at the quarry the materials are ready as the levels arrive: the Workshop
is crafted the moment level 3 is reached and the Machine Works a minute after level 6, so the
level gates, not the ore, set the pace. The Machine Works upgrade is the big ticket (half the
iron), which is why the Harvester follows it by five minutes and the whole tier-one roster
lands in about 45 minutes. Mutations barely matter here, because materials, not coins, buy
machines: coins only pay for seeds, the Axe, Glass, Bricks and research.

**The quarry is shared, so its rocks keep up with the miners.** Three iron rocks giving two ore
every 45 seconds each are 8 ore a minute. With fixed timers that was 8 a minute for the whole
server, and the ore set the pace from four players up (the table: every rock's respawn
stretched by the other players' mining, `--quarry-share`). The Rock Drill could not help, since
it came after the Machine Works then, the step the wall stood in front of (it is a Workshop
recipe now, retention.md).

| Players mining | Workshop | Machine Works | Harvester | Oven | Level 12 |
|---:|---:|---:|---:|---:|---:|
| 1 | 8.1 | 27.8 | 33.2 | 43.9 | 59.9 |
| 2, fixed timers | 8.8 | 29.0 | 34.1 | 46.3 | 62.1 |
| 4, fixed timers | 10.5 | 42.1 | 51.0 | 71.6 | 77.0 |
| 6, fixed timers | 12.3 | 57.8 | 70.9 | 101.4 | 72.4 |
| 2 to 6, as built | 8.1 | 27.8 | 33.2 | 43.9 | 59.9 |

The fixed-timer rows were run before juice went to 4.5x and before the first four crops grew
faster; their level 12 would now be about a minute sooner. As built, a quarry rock's respawn is divided by the players mining (factory.md § The quarry),
so each miner's share is what one player gets alone and `--miners 4` or `6` gives the solo row
exactly. That equality is the model's: it shares the rocks out evenly and never has two players
reach for the same rock, so real sessions will be a little slower. A lone miner on a full
server gains nothing, because only players who mined in the last two minutes count.

How hard the player pushes changes little once gathering has half the hand time (`--build-share
0.75`: Harvester at 32.5), but a player who mostly farms (`0.25`) reaches it at 67 minutes and
level 12: levels then run ahead of the workshop.

### Income

| Stage, net coins/minute | Coin shop, mutation EV | Crafted, mutation EV | Crafted, plain only |
|---|---:|---:|---:|
| Hand farming | 459.2 | 277.8 | 170.8 |
| Harvester line, before the Mill | 1,079.5 | 1,605.3 | 1,165.2 |
| With processors, to level 12 | 1,696.8 | 2,303.2 | 1,923.0 |

Income is realized sales less purchased seeds, averaged over time in that stage; it excludes
onboarding grants. Hand farming earns less than in the coin-shop model because half the hand
time goes to gathering and every cell is tilled first. The Harvester stage lasts two minutes
here and includes the first sales of what it queued, so its figure is noisy. Crop values and
machine speeds are unchanged; the stages are just reached sooner.

### Mk II machines

Each is crafted at the Fabricator (tier 4, level 9) from the machine it replaces plus parts.
The parts alone, from ore, with one Smelter and one Assembler working serially and mining left
out (the script asserts 4-10 minutes for each):

| Machine | Parts | Supplied minutes | Raw |
|---|---|---:|---|
| Seed Planter Mk II | 3 Steel Frame, 6 Gear | 4.7 | 24 iron, 8 coal, 3 stone |
| Sprinkler Mk II | 4 Circuit, 6 Copper Wire | 5.0 | 8 iron, 14 copper, 8 coal |
| Grain Mill Mk II | 2 Steel Frame, 8 Gear | 4.7 | 24 iron, 8 coal, 2 stone |
| Harvester Mk II | 3 Steel Frame, 6 Circuit | 7.9 | 24 iron, 12 copper, 12 coal, 3 stone |

The Fabricator upgrade itself (8 Steel Frame, 6 Circuit, 12 Gear, 10 Copper Wire) is another
68 iron, 22 copper, 30 coal and 8 stone. The Rock Drill (2 Steel Frame, 4 Gear, 4 Copper Wire:
16 iron, 4 copper, 7 coal, 2 stone) makes about 3 Iron and 2 Copper Ore a minute on its own
coal, so a few drills cover a Mk II bundle in 10-15 unattended minutes.

### Mid-game products and the late game

The model reads the `chained` products and prints them with a late-game audit (`late_game`);
it simulates none of their machines. Values at the present crop prices:

| Product | Machine | Machines deep | Crops inside | Their worth | Value |
|---|---|---:|---|---:|---:|
| Crisps | Roaster | 1 | 2 Potato | 220 | 330 |
| Popcorn | Roaster | 1 | 2 Corn | 720 | 1,100 |
| Roast Pumpkin | Roaster | 1 | 1 Pumpkin | 1,600 | 2,400 |
| Tomato Sauce | Kettle | 1 | 4 Tomato | 180 | 270 |
| Strawberry / Blueberry / Apple / Grape Jam | Kettle | 2 | 5 of the fruit | 75 / 150 / 450 / 1,300 | 230 / 450 / 1,400 / 3,900 |
| Pizza | Oven | 2 | 2 Wheat, 4 Tomato | 204 | 610 |
| Pumpkin Pie | Oven | 2 | 2 Wheat, 1 Pumpkin | 1,624 | 4,900 |
| Strawberry / Blueberry / Apple / Grape Jam Tart | Oven | 3 | 2 Wheat, 5 of the fruit | 99 / 174 / 474 / 1,324 | 450 / 780 / 2,100 / 6,000 |
| Watermelon Sorbet | Chiller | 2 | 1 Watermelon, 3 Strawberry | 4,045 | 12,000 |
| Starfruit Sorbet | Chiller | 2 | 2 Starfruit, 3 Blueberry | 3,690 | 11,000 |

The audit takes one Harvester Mk II patch (35 cells) of a crop, plain, and compares selling it
raw with the best product it is the main crop of, with the other inputs grown elsewhere and as
many machines as it takes. No mutations, weather or research.

| Crop | Raw coins/min | Best product | Through it | Machines for it |
|---|---:|---|---:|---|
| Potato | 1,925 | Crisps | 2,888 | 0.9 Roaster |
| Corn | 3,150 | Popcorn | 4,812 | 0.4 Roaster |
| Tomato | 3,150 | Pizza | 10,675 | 2.3 Oven |
| Strawberry | 2,100 | Strawberry Pie | 17,500 | 9.3 Oven |
| Blueberry | 5,040 | Blueberry Pie | 33,600 | 11.2 Oven |
| Pumpkin | 7,000 | Pumpkin Pie | 21,438 | 0.6 Oven |
| Apple | 6,300 | Apple Jam Tart | 29,400 | 1.9 Oven |
| Watermelon | 14,000 | Watermelon Sorbet | 42,000 | 0.6 Chiller |
| Grape | 18,200 | Grape Jam Tart | 84,000 | 1.9 Oven |
| Starfruit | 50,400 | Starfruit Sorbet | 154,000 | 2.3 Chiller |

The new chains sit in the range the pies already set: a Blueberry Pie patch earns more than a
Pumpkin Pie or Apple Jam Tart patch, on far more Ovens and wheat. What the audit shows about
the late game is older than these products. Every one-off coin sink in the game (research
8,629,400, counting each Mastery's first rank once, and garden sections 1,027,500) comes to
9,656,900 coins. One raw Starfruit patch pays for all of it in 3.2 hours and one raw Grape
patch in 8.8. The brake is seeds (a Mythic seed is 2% of restocks), not prices. The sink that
keeps going is the five Mastery projects (research.md § Mastery): each rank costs 1.25 times the
last, so the twentieth rank of Farming Mastery alone is 21,000,000 coins.

### Orders and daily quests

The model also prints what an order and a day's quests are worth against a level
(`orders` in the script). It is arithmetic, not simulation: an order replaces the sale of the
goods it takes, paying 1.5 times their coins and twice their sale XP.

| Level | Order's goods | Order XP | Over selling them | Level costs | Order / level | Day's quests / level |
|---:|---:|---:|---:|---:|---:|---:|
| 5 | 2,000 | 400 | +200 | 382 | 105% | 15% |
| 10 | 6,000 | 1,200 | +600 | 1,695 | 71% | 15% |
| 15 | 11,000 | 2,200 | +1,100 | 4,053 | 54% | 15% |
| 20 | 18,000 | 3,600 | +1,800 | 7,523 | 48% | 15% |
| 30 | 35,000 | 7,000 | +3,500 | 17,988 | 39% | 15% |

An order looks large beside a level, but half its XP is what selling the same goods would have
given, and the goods are several minutes of the garden's whole income. The script asserts that
one order never adds more than 60% of a level over a sale. The most orders can do is double the
sale XP of everything sold: in the steady hour that is 230 XP a minute on top of 339 (192 on 260
without mutations), which only a player hand-delivering every sale as an order would see.

| Milestone | No orders | Every sale an order, from level 12 |
|---|---:|---:|
| Level 15 | 86.2 | 75.7 |
| Level 20 | 165.1 | 122.8 |
| Level 30 | 514.2 | 330.4 |

So orders can take at most a quarter off the run to level 20 and a third off level 30, and far
less for a factory that ships through bins. The order numbers stay as they are.

**Timing a real run.** In Studio the server prints a line at every level
(`Pace: level 12 at 58:20 played, 61,400 coins earned, 1,930 crops harvested`, from
ProgressService and the saved play-time stat), so a fresh garden played to level 20 can be set
beside the tables above. That run has not been played yet (retention.md § R7).

### History

All valued products beat their immediate inputs, plain and in every mutation; the script
asserts this for every recipe, that a single crop's seed (and any Common or Uncommon seed)
repays in one plain harvest, and that each rarity's crops earn at least the best of the rarity
below per cell on a Harvester (plain coins a minute: Common 36, Uncommon 60-79, Rare 90-144,
Epic 180-200, Legendary 400-520, Mythic 1,440).

| Owner / number | Before -> after | Reason |
|---|---|---|
| World.CROPS, Strawberry seed | 50 -> 45 | Its first plain harvest yields 3 x 15 = 45 |
| World.CROPS, Potato / Tomato / Corn / Pumpkin value | 70 / 35 / 160 / 1,100 -> 110 / 45 / 360 / 1,600 | Corn and Pumpkin sold for less than their seed, which a hand harvest spends; Uncommon out-earned Rare and Rare out-earned Epic per cell (retention.md) |
| World.CROPS, Carrot / Wheat / Strawberry / Potato grow seconds | 60 / 75 / 90 / 120 -> 30 / 40 / 60 / 84 | The first minutes were mostly waiting. Regrow times are unchanged: a 32 s Strawberry regrow swamped the Harvester line in the model (level 12 at 65 minutes, not 60) |
| World.CROPS, Watermelon seed and value | 6,000 and 3,500 -> 3,000 and 4,000 | A hand harvest lost 2,500 coins |
| Products, juice | 3.5x one fruit -> 4.5x | From three fruit it added 17%, never worth a machine; one machine now adds half |
| Products, mid-game | none -> sixteen `chained` products on three machines and two Recipe Books | Levels 13-35 unlocked only percentages, and Potato, Corn, Tomato, Pumpkin, Watermelon and Starfruit had only a crate or juice (retention.md § Mid-game machines) |
| Economy.required | `100 * n^1.5` -> `20 * n^2.75` -> `12 * n^2.15` | The first made level 2 too slow; the second put level 12 at 259 minutes and level 50 at about 600 hours. The current curve is a plain power law: 12 XP for level 2, about 52,000 for level 49 to 50. Lifetime XP is kept, so levels only move up when recalculated |
| Mk II parts | sized to 24-36 bars each | A first pass needed 80-120 hand-mined bars per machine from the shared quarry, a grind wall the calm target rules out |
| Machines | coins at a Machine Shop -> crafted at the Crafting Bench -> crafted in the Crafting window from the side button | factory.md § Crafting. The coin prices and unlock levels in overhaul.md § Machines are the old shop's; crafting tiers at levels 3, 6 and 9 gate machines now |

Studio verification remains: timed fresh sessions alone and on a full server, low-stock windows,
actual belt and chest backpressure, hand loading and routing overhead, and how much players keep
hand farming after automation.

## Onboarding

`Shared/Onboarding.STEPS` is the content owner. `OnboardingService` observes server
`GardenEvents` and pays through EconomyService. There is no inbound objective remote and
no tutorial gate; ordinary play can satisfy later steps before their prompts appear. New
players start with only a Hammer, Pickaxe and Hoe, 50 coins and an all-grass garden, so the
first five steps teach farming by hand: buy seeds, till, plant, harvest, sell.

| Step | Objective | Server evidence | Coins |
|---|---|---|---:|
| 1 | Open the Shop and buy some Carrot Seeds | Bought a World.PLANTS seed | 10 |
| 2 | Hold your Hoe and click the grass in your garden to till Farmland | Tilled, or restored tilled ground/crops/discoveries | 10 |
| 3 | Hold your seeds and click the Farmland to plant them | Planted, or restored crops/discoveries | 10 |
| 4 | Wait for a crop to ripen, then click it to harvest | Harvested, or restored discoveries | 20 |
| 5 | Open Sell and sell your harvest for coins | Sold with positive coins and no position | 20 |
| 6 | Reach level 2 | LevelUp >= 2, or current level already >= 2 | 30 |
| 7 | Open Crafting and craft a Shipping Bin from 10 Wood Planks | Crafted ShippingBin (or bought one), or restored owned Bin | 20 |
| 8 | Place your Shipping Bin on your plot | Placed ShippingBin, or restored placed Bin | 50 |
| 9 | Mine Stone at the quarry, then craft a Smelter | Had Smelter | 100 |
| 10 | Place the Smelter and smelt an Iron Bar | Had IronBar | 100 |
| 11 | Reach level 3, then upgrade crafting to Workshop | Crafting tier >= 2 | 250 |
| 12 | Craft an Assembler and place it | Placed Workbench | 250 |
| 13 | Make a Gear in the Assembler | Had Gear | 150 |
| 14 | Craft a Seed Planter | Had SeedPlanter | 300 |
| 15 | Start a research project and complete it | Any research finished | 200 |
| 16 | Craft a Sprinkler | Had Sprinkler | 250 |
| 17 | Craft a Rock Drill | Had RockDrill | 250 |
| 18 | Reach level 6, then upgrade crafting to Machine Works | Crafting tier >= 3 | 1,000 |
| 19 | Craft a Harvester and place it | Placed Harvester | 1,000 |
| 20 | Sell 50 items through a Shipping Bin | 50 bin sales | 500 |
| 21 | Craft a Grain Mill and mill Flour | Had Flour | 750 |
| 22 | Craft a Baking Oven and bake a pie | Had any pie | 1,500 |
| 23 | Open Quests and deliver an order | An order filled | 1,000 |
| 24 | Reach level 9, then upgrade crafting to Fabricator | Crafting tier >= 4 | 2,500 |
| 25 | Build your first Mk II machine | Had any Mk II machine | 4,000 |

Step 2 was inserted later; DataService moves a save's step past it once (layout 5). Steps 9-25
(retention.md § Goal chain, which gives the reason for each reward) were appended, which needs
no migration: a save that had finished holds step 9, now the first new goal. Step 23, the
order, was inserted once orders existed; a save at or past it moves along once (layout 6).

Steps 9-25 are goals (`Shared/Onboarding` `Goal`) checked against the garden, not named
conditions. **Had** an item means it was crafted in the Crafting window, made by a machine on
the plot (`GardenEvents.Processed`, a mutated product counting as its product), or placed; on
load the Index, the inventory and the plot's blocks stand in. **Placed** means it stands on the
plot or was just placed. The crafting tier is read whenever a goal is checked. Bin sales count
each Shipping Bin sale live and, on load, start from the bins' saved `sold` counts. The order
goal hears `GardenEvents.OrderFilled` and, on load, reads the saved ordersFilled stat. A goal with
progress sends it as the snapshot's `detail` ("12 / 50 sold", every fifth sale; "Level 2 / 3"
while a tier goal waits on the level), and the panel shows it in place of the step count.

Each completion advances the saved next step before paying once and sending
`Done! +N coins`; completion sends `Your garden is yours to grow. Happy gardening!`.
Total rewards are 170 coins for steps 1-8 and 14,100 for steps 9-25. There is no extra
finishing grant.

Once every goal is done the panel stays, titled "Next unlock": the next level that opens
something and the XP left to it ("Level 10: Efficient Study I and new research", "550 XP to
go"), worked out on the client from `Shared/Unlocks`, the wallet and finished research, and
hidden only when no level opens anything more. `Shared/Unlocks` reads crafting tiers, Gear Shop
offers and research levels; it names a research project only when the Research window would
show it and counts the rest as "new research". The level-up notice uses the same module:
"Level 6! You can now upgrade crafting to Machine Works. New research too." or
"Level 13! New research: Haggling II.".

Earlier live actions are
remembered for the session; restored crops, discoveries, level and inventory/placed Bin
provide evidence on rejoin. A starter seed is not evidence of buying, and a Shipping Bin
sale is not evidence of selling at the stand. Those two events must be observed live.
Only the next step persists, with the profile integration in [plots.md](plots.md#profile-contents).

The server sends `Objective {step, total, text, done, detail}` on load, on every step change
and as a goal's progress moves.
Its read-only `OnboardingStep` player attribute lets a late HUD recover without a client
request. `UIController/Objective` receives `init(hud)`, binds with `Hud.find`, warns once
for missing/mistyped nodes, and leaves gameplay usable if the authored screen is absent.

```text
StarterGui.HUD.Objective [Frame]       top-left below side buttons; initially hidden
  Title [TextLabel]                    Next step (the authored text), or Next unlock
  Text [TextLabel]                     current objective, or "Level 10: ..."
  Progress [TextLabel]                 Step 2 of 25, a goal's progress, or "550 XP to go"
  Check [ImageLabel or Frame]          initially hidden
```

A completion shows the check and softly fades the old text for 0.3 seconds, then displays
the latest objective. Later updates cancel old tweens; a progress update for the same step
changes the label in place. Releasing the garden (the save menu) hides the panel and forgets
the step, so the next save starts from its own. Reduced
motion applies the new state immediately, including if enabled mid-transition. Baseline
transparencies come from the authored objects, and HUD destruction disconnects listeners
and invalidates delayed transitions. Place-file layout and assets remain Studio work.

Played through in Studio (2026-11-09) on a fresh garden in an empty save slot, deleted after:
steps 1-8 from announced actions; then real Crafting requests for the Smelter, both the
Workshop and Machine Works upgrades, Seed Planter, Sprinkler, Rock Drill (at Workshop),
Fabricator and Grain Mill Mk II; real batches in a Smelter, Assembler, Grain Mill (Golden
Wheat, counted as Flour) and Baking Oven; a real research project started and completed; 50
real Shipping Bin sales with the label counting up in fives, and a quit to the save menu and
reload at 15 sold, which resumed at 18 and finished. Each step paid once. The tail then read
"Next unlock", "Level 10: Efficient Study I and new research", "550 XP to go". The level-up
notices read as above. A finished older save (step 9) moved to step 12 on load from its Smelter,
Iron Bars and crafting tier. Placing the Assembler and the Harvester was announced by the test,
not done with the build tool.

Still to verify in Studio: plant/harvest/buy/place ahead of the prompt; machine sales not
counting as stand sales; corrupt/missing step sanitization; late/missing HUD; reduced motion and
respawn; the panel on a phone-sized screen with the longest goal texts. Static checks do not
verify these interactions.
