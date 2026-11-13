# Research

`Shared/Research` owns the ordered projects, costs, prerequisites, descriptions, categories,
effect numbers and shared start/duration rules. Crafting recipes (`Shared/Crafting`) name the
project that unlocks them; research stores no recipe links. The Research window shows it all
(§ Window).

Each category is one upgrade tree: a single root project and every other project needing one in
its own category (Farming from Rich Soil I, Automation from Faster Belts I, Economy from Quick
Learner I, Tools from Sharp Axe I, Crafting from Crate Making). Only Master Gardener reaches
across trees, for its Farming needs. The Crafting tree also carries the mid-game line, each
needing the one before: Roaster Plans (level 13), Kettle Plans (18), Recipe Book I (22), Recipe
Book II (26), Chiller Plans (30) and Heavy Processor Plans (35). The Recipe Books unlock no
crafting recipe: `Shared/Factory/Products` names them on the bakes they open, and a Baking Oven
checks its owner's finished research (factory.md § Processors). Their tiles show a Pumpkin Pie
(`ResearchScreen` ICONS), having no recipe output to show. `Shared/Research` asserts the shape at load. Finished saves
stay valid however the links change, because needs are checked only when a project starts.

76 projects in all. The lines added on 2026-11-11, with their new bonuses:

| Line | Tree, levels | Each tier | Placed |
|---|---|---|---|
| Deep Watering I-II | Farming, 7 and 31 | `waterPower` +0.05: a watering can splash takes 25%, then 30%, of what's left of a stage | off Green Thumb I |
| Seed Saver I-II | Farming, 16 and 34 | `seedSaver` +0.1: a planted seed is kept 10%, then 20%, of the time | off Rich Soil II |
| Lucky Swing I-III | Tools, 10, 21, 37 | `luckyDrop` +0.1: a chop or mine gives its whole drop twice | off Sharp Axe I |
| Sharp Axe III, Strong Pickaxe III | Tools, 30 and 33 | +1 Wood, +1 of a rock's main drop | ends their lines |
| Night Shift I-III | Economy, 11, 21, 41 | `offlineShare` +0.05 and `offlineCap` +60 minutes (welcome.md § Offline coins) | off Haggling I |
| Contracts I-II | Economy, 12 and 36 | `rewardBonus` +0.15: daily quest and order coins (XP unchanged) | in the Seed Contacts line: Seeds1 -> Contract1 -> Seeds2 -> Contract2 |
| Lab Notebook I-II | Economy, 14 and 38 | `researchQueue` +1 (§ The queue) | in the Efficient Study line: Study1 -> Notebook1 -> Study2 -> Notebook2 -> Study3 |
| The five Masteries | each tree, 40-50 | ranked (§ Mastery) | off each tree's last project |

Seeds2, Study2 and Study3 now need the projects slotted in before them; finished saves keep them.

No project branches more than three ways (2026-11-12), so a tree opens out ring by ring rather
than all at its root: Seed Contacts I and Night Shift I need Haggling I (the trade bonuses, off
the sales line), and Wide Sprinklers I needs Swift Reapers I (beside the farm machines), not the
trees' first projects.

## Mastery

A `ranked` project is never done. Completing it adds a rank (`ranks[id]`), and every rank adds
its effects again. Rank r costs `coins * 1.25^(r-1)` to two significant figures (300,000,
380,000, 470,000...) and the same items, and takes `seconds * min(2, 1 + 0.1 * (r-1))`
(`Research.price`). Nothing may need a ranked project (asserted). The same Mastery may be lined
up more than once; each costs the rank it buys (`Research.nextRank`: finished ranks + those lined
+ 1), and cancelling one refunds the highest lined rank, so what stays lined stays paid for.

| Project | Tree, level, needs | Each rank | First rank |
|---|---|---|---|
| Farming Mastery | Farming 46, Rich Soil V | cropYield +0.02 | 300,000 coins, 10 Pumpkin, 1 h |
| Automation Mastery | Automation 42, Faster Belts V | machineSpeed +0.02 | 300,000, 4 Circuit, 1 h |
| Economy Mastery | Economy 50, Master Gardener | sellPrice +0.01 | 600,000, 1 h |
| Tools Mastery | Tools 42, Lucky Swing III | luckyDrop +0.01 | 250,000, 10 Iron Bar, 1 h |
| Crafting Mastery | Crafting 40, Heavy Processor Plans | researchSpeed +0.03 | 250,000, 4 Circuit, 1 h |

`luckyDrop` and `waterPower` are clamped to 1 where they are used; research speed divides time,
so endless ranks only approach instant. `Bonuses.has` is true for a ranked project with a rank.

## The queue

One project runs (`active`). Others can be lined up behind it in `queue`, each paid in full
when lined up, its duration fixed then (with the research-speed bonus of that moment), with the
Unix second it was lined up (`at`). `Research.advance` moves the line: while the running
project's timer has run out and something is queued, the finished one goes to `ready` and the
next starts where it ended, or at its `at` if later (so time spent waiting for Complete before
it was lined up is not credited). Projects in `ready` wait for Complete like a lone finished
project; only completing applies a bonus.

The line's room is `Research.ROOM` (1) plus `researchQueue`, and queued and ready projects share
it (`Research.fits`): with the running slot taken, another may join only while `#queue + #ready`
is under the room. So a player who never completes cannot stack projects up, and a full line
says to complete one. With nothing running, a project always starts. A queued project's needs
count once they are done or lined (`Research.blocker`'s `lined`), so Rich Soil II can queue
behind Rich Soil I.

Cancelling the running project (not once ready) or a queued one refunds it; any queued project
whose needs are then neither done nor lined is taken out and refunded with it, all or nothing
against the inventory. When the running one goes the next queued starts now. Complete takes an
id or, without one, the first ready project, else the running one once its timer has run out.

## Flow

```text
DataService: assign plot -> ResearchService.load -> restore ground, blocks, crops
    -> inventory/economy/garden/onboarding -> DataReady
Research Start -> readiness/cooldown/id -> advance -> level/needs (done or lined)/room
    -> rank price: items/coins -> pay -> active, or queued behind it -> sync
Research Cancel (id?) -> queued, or running and not ready -> it and queued projects left without
    their needs -> all refund items fit -> refund -> next starts -> sync
one-second loop, DataReady only -> advance -> more finished than told -> Notify "ready" -> sync
Research Complete (id?) -> advance -> a ready one, else the running one past its timer
    -> done (or a rank) -> Bonuses + BeltSpeed -> GardenEvents.ResearchDone -> Notify -> sync
DataService: snapshot research with balances -> clear research before releasing the plot
```

One project runs at a time on fractional Unix seconds, with others queued behind it (§ The
queue). When its timer runs out it is not done: it stays active (and saved), or moves to
`ready` when the next starts, until the player presses Complete, which is when its bonus applies
and the completion effects play. `Research.isReady` is the rule; the server accepts a Complete up
to `Research.READY_EARLY` (0.5 s) before the deadline, so a press as a client's countdown ends is
never refused. A ready project cannot be cancelled. Duration is fixed when it is lined up,
using the current research-speed bonus. Starting and cancelling validate before changing
anything and do not yield between checks and mutation. Requests share a per-player cooldown;
each one, including a refusal or malformed payload, gets a toast and authoritative snapshot.
Cancellation leaves everything unchanged if the refund cannot fit.

`server/libraries/Bonuses` stores copies of finished ids and summed stats; it imports only
shared modules and Signal. Services read `get` or `at`, and crafting can read `has`, without
requiring ResearchService. `ownerAt` uses Plot's owned-section check and the plot's Owner
attribute. `changed(player)` fires after set/clear. Missing players/stats have zero bonus.
ResearchService publishes the multiplier `BeltSpeed` on the assigned plot model on load and
completion, then removes it before release.

## Remotes

`Shared/Remotes` owns payload contracts; `default.project.json` authors the events.

- `Research`, client to server: `("Start" | "Cancel" | "Complete", id?)`. Start requires a known
  id and starts or queues it; Cancel takes a queued id, else the running project; Complete takes
  a finished id, else the first finished one.
- `ResearchSync`, server to client: `{done = {id, ...}, ranks = {[id] = n}, active = {id,
  endsAt, seconds}?, queue = {{id, seconds}, ...}, ready = {id, ...}, room, bonuses = {[stat] =
  number}}`. Sent on load, start, cancel, complete, when the line moves or a timer runs out,
  and every refusal. `active` stays past `endsAt` until completed or the next one starts.
  Finished ids follow catalogue order. The deadline converts saved Unix seconds to
  `workspace:GetServerTimeNow()`, so device clocks do not affect the countdown.
- `Notify` explains successful actions and refusals and announces completion.

## Saving

The profile's `research` defaults to `{done = {}, ranks = {}, active = nil, queue = {},
ready = {}}`; older saves without the new fields load as empty. Done is an id-to-boolean map of
unranked projects; ranks maps ranked ids to whole ranks; active holds `{id, startedAt,
seconds}`, each queue entry `{id, seconds, at}`, ready a list of ids. Snapshots copy every
table. Research loads immediately after plot assignment, before machines and crops, so restored
crops' offline mutation rolls see finished bonuses. Load moves the line along for the time away
(`Research.advance`) but never announces garden actions or finishes a project: what ran out
offline waits for its Complete, and the one-second loop tells the arriving player once DataReady
is true.

Unknown finished ids, ranked ids in done, bad ranks, malformed entries and unknown/malformed
active, queued or ready projects are dropped with warnings. Timestamps and durations must be
finite, timestamps nonnegative and durations positive whole seconds; an unranked id already
finished or already in the line is dropped too, and a queue left with nothing running starts
its first entry.
These errors never fail a profile load. Quit, session loss and failed-load cleanup clear
bonuses and the plot multiplier. XP and Shipping Bin fractional carries are session-only
and reset with the profile. See [plots.md](plots.md) for the full lifecycle.

## Effect hooks

All numbers and additive tier totals stay in `Shared/Research`.

| Effect | Runtime owner |
|---|---|
| beltSpeed | `Shared/Factory.beltMultiplier` reads the plot attribute; `FactoryService.stepLanes` scales advance and throw-off; `FactoryController.apply/render` scales every item lane, including machine belts and router arms; `ConveyorRideController.step` scales existing conveyor/router riding |
| machineSpeed | `FactoryService.stepMachines` supplies Machine.Env; `Machine.step` scales recipe-time progression for processors, Workbench and Smelter, including coal burn so fuel per bar stays the same |
| harvesterSpeed | The same Env scales Harvester and Seed Planter progression in `Machine.step` |
| sprinklerRadius | `FactoryService.sprinklerAt` expands the rectangle horizontally, still inside its own plot and at its own level |
| cropYield | `WorldService.harvestCount` rolls floor plus fractional chance; hand `onInteract` and machine `FactoryService.envFor` / `Machine.stepProducer` share that result between capacity and output |
| growSpeed | `WorldService.growthSpeed` multiplies the sprinkler provider; `bankGrowth/grow` bank online credit with rain and update deadlines; offline time stays normal |
| mutationChance | `WorldService.chanceModifiers` supplies the owner's multiplier; `World/Mutations.roll` multiplies every final chance before clamping, including Rainbow, weather and offline always-on rolls |
| sellPrice | `GardenService.sell` floors the boosted whole transaction; `FactoryService.paySale` carries fractional coins per player and bases sale XP on paid coins |
| xpGain | `EconomyService.addXp` multiplies all earned XP and carries its fraction per player |
| seedStock | `GardenService.restock` adds to positive rolls only; load validation allows boosted saved stock |
| researchSpeed | `ResearchService.start` calls `Research.duration` once, on the rank's seconds |
| chopYield / mineYield | `WorldService.onInteract` adds the acting player's bonus to the node's named boost item before checking room |
| luckyDrop | `WorldService.onInteract` then rolls it: a hit doubles every drop if both fit (else one), with a "Lucky swing!" notice |
| waterPower | `WorldService.water` adds it to `WATER_SHARE` (0.2) |
| seedSaver | `WorldService.keepsSeed` rolls it: `BuildService` gives a hand-planted seed back (if it fits, with a notice); `Machine.stepPlanter` skips taking the seed when the planter's `env.keepsSeed` hits |
| offlineShare / offlineCap | `WelcomeService.load` passes them to `Welcome.offlineCoins` (research loads first) |
| rewardBonus | `ProgressService` `boosted`: quest and order coins, paid and shown in ProgressSync |
| researchQueue | `ResearchService` room (§ The queue) |

Unripe digging and uprooting keep their original yields. Full inventories and machine outputs
leave the crop or node intact. Research alone does not make Farmland wet: GroundService's
sprinkler-speed query stays separate from combined growth speed. Sprinkler placing previews
and the machine panel still show the base area; those UI modules are unchanged.
Machine belts retain their existing item-only behavior: enabling player riding there would
change play even with zero research. Their item simulation and drawing still use BeltSpeed.

## Window

`UIController/ResearchScreen` binds the Research window, opened by `SideButtons.Research` from
anywhere (HubWindow, with no stalls and not modal, so nothing blurs behind it).
`client/libraries/ResearchClient` keeps the latest ResearchSync. The window is a full-screen
black view in its own ScreenGui, `StarterGui.ResearchView`. While it is open,
`client/libraries/HudVisibility` hides the HUD, Roblox's player list and chat, leaving only the
close button and the running project's strip along the bottom. HudVisibility arbitrates
`HUD.Enabled` by named requests, so the save menu (HUD only) and the Research view never fight
over it.

**Opening and closing.** The screen animates itself through HubWindow's optional `animate`
argument, as a ripple: every transparency under the view (backgrounds, text, strokes, images and
the tiles' ViewportFrames) is taken from where it stands and eased to clear and back, each piece
of the tree at its own moment by its distance from the middle. Opening, the backdrop and strip
come first, then the hub, then the guide rings, lines and tiles outward over 0.55 s, each taking
0.34 s, tiles growing in from 30% with a bounce; the canvas also glides in from 80% of its zoom.
Closing runs the other way: the furthest pieces go first (0.32 s spread, 0.22 s each, tiles
shrinking), the backdrop last. A CanvasGroup was tried and does not work here: Studio rendered
its children unfaded and unclipped, and ViewportFrames ignore `GroupTransparency`. Reduced motion
shows and hides it at once.

**The night field.** Behind the canvas, `Research.Sky` (`client/libraries/ResearchSky`, authored by
`tools/hud/polish_hud.luau`) is the loading screen's night sky made livelier, back to front: three
huge nebula clouds that drift, turn and breathe (one tinted like the glow, one violet, one teal);
a radial glow leaning toward the colour of the fan nearest the view's middle, or the selected
tile's category, or the hub's gold near home; 34 far and 22 mid stars that twinkle; 12 glowing
seed motes rising; a shooting star every 1.6 to 4.2 s; and a vignette over it all. Each layer
follows the canvas's pan and zoom at its own rate (nebulae 4%, far 8%, mid 22%, motes 45%), the
stars wrapping round the screen. It is a fixed pool of about 80 nodes made once, none catching
input; its own RenderStepped runs only from the opening until the closing ripple ends, and the
ripple leaves it out, fading it instead with the backdrop's timing (first in, last out). On the
Low lighting quality every other star, the motes and the shooting stars rest hidden and the
nebulae stop turning; under reduced motion the field holds still but still follows the canvas.
The images are `Shared/Icons` textures (`assets/icons/README.md`). Played through on 2026-11-12:
opening and closing (and a close and reopen mid-ripple, which left the view shown, interactable
and fully faded in), the tint following a pan toward Automation, the pulses, a shooting star,
and the field at a 667 x 375 view; the Low quality thinning was not tried (it needs the saved
setting changed).

All the projects form one five-fold tree on `Research.Canvas`. The view always opens centred on
its middle with nothing selected, at 0.72 zoom.

- **Hub.** A round tile with the side button's flask and a soft gold glow, a ring of dots
  turning slowly round it and a fainter ring with three bright motes turning the other way. Its
  border breathes, its glow and a wider halo swell out of step with each other, and two rings of
  light (the `Ring` texture) keep spreading from it to just past the first ring of tiles, one
  every 1.6 s. Faint guide rings mark each step out from it.
- **Fans.** Each category is a fan in its own fifth of the circle, clockwise from the top:
  Farming, Automation, Economy, Tools, Crafting. Each has a colour (green, sky blue, gold, coral,
  violet) carried by its tag, its tiles' fill, a finished tile's ring, its lit lines, the unlock
  glow and the sap. A fan's first project sits on its middle line 260 px from the hub, on a stem
  that carries the category's tag.
- **Layout along a fan.** A project's ring is how many projects lead to it in its category, 180 px
  apart; it hangs off its latest need. Children that continue its line (Yield1 -> Yield2), or a
  need's only child, run straight on. Lanes are numbered across the fan with every branch's
  lanes together, so no two lines cross, and the line a project continues sits in the middle of
  its branches (half the others before it, half after). The lanes spread evenly about the fan's
  middle, 18 degrees apart, closer when they would span more than 54 degrees (`FAN_SPREAD`), so
  each fan stays inside its fifth. Measured with every project shown: no two tiles closer than
  103 px, and 138 px across fans.
- **Tiles.** Cloned from `Assets.UI.Research.Node`, a clear button holding `Shape`, a rounded
  square turned 45 degrees into a diamond (filled dark in the category's colour, brighter once
  finished) with its ring, the item picture upright on top and the name under it. A tile that
  can be researched (or completed) has a larger diamond halo breathing round it.
- **Lines.** A stem joins the hub to each first project; each need in the same category is
  joined to the project by a line of `Assets.UI.Research.Link` pieces that leaves the need heading
  for the project's line and flows into it (a quadratic curve, eight pieces), or runs straight
  when they share a line. Each piece is a turned Link holding a `Lit` fill in the category's
  colour; lines out of a finished project are lit. Motes of sap drift outward along lit lines,
  one setting off every 0.3 s, at most 12 at once. Master Gardener's needs in other categories
  draw no line.
- **What shows.** A tile is shown when it is a fan's first project, done, running, or needs a
  finished project in its own category. Past each shown tile that isn't locked by level, the
  nearest (lowest level) project it leads to appears undiscovered, one per tile: a dark diamond
  with "?", no name, picture or cost, on a fainter line. Its info says which project to research
  to discover it, and its button reads "Undiscovered". Nothing shows past a locked tile, so a
  level-1 garden sees only the five first projects, and a tile's other branches appear when it
  is finished, each grown in as the unlock glow reaches it. Nothing further out is drawn.
- **States.** A shown tile's ring says its state: its category's colour when done, yellow can
  start, red locked (its item and name faded), blue running (with a progress bar), lilac queued,
  gold and pulsing ready to complete (every finished project waiting, not only the running
  one). A Mastery tile is never done: its name carries its rank ("Farming Mastery 3") and its
  fill brightens once it has one.
- **Cost badge.** Open and locked tiles show the optional `Node.Cost` label: plain coins below
  1,000, then K/M with one decimal and no trailing .0, for the next rank of a Mastery. Red when
  unaffordable, otherwise its authored text colour; updates with the wallet. A queued tile shows
  its place instead, "Next" or "#2", in lilac. Hidden for running, ready and done projects.
- **Info.** Pressing a tile selects it: the canvas glides it 210 px left of the middle and
  `Research.Info` (400 px wide) stands beside it, on its right or, without room, its left, level
  with it and clear of the close button and the strip. It shows the name (in its state's colour),
  description, level and state, cost (red when you can't afford it), then under "Requirements" a
  card per required item, cloned from `Assets.UI.Research.Requirement`: the item's picture in a box
  with "x20 Wheat" under it, its outline and words green once you carry that many. Then the time
  behind an hourglass ("2:00", "1:30:00"; for the running project, the time left; for a queued
  one, its fixed time), any blocker, and an Action button: Research (nothing running), Queue
  (something running), Complete, Cancel (the running project), Remove (a queued one), Queue
  full, Locked, Need coins, Need items, Undiscovered or Done. A Mastery's info adds "Ranks so
  far: 3. Next: rank 4." and prices that rank; while a rank of it runs it can be queued again.
  Done hides the requirements and the time. Cards are rebuilt only when the project changes.
  Without the Requirement template the items are listed as words. Hovering (or gamepad-selecting)
  another tile shows the same in `Research.Tooltip`, without the button.
- **Putting the info away.** A press on empty space (not a tile, the hub, the info or the strip)
  that never becomes a drag deselects, centring the tile. Pressing the hub glides home.
- **Active strip.** `Body.Active` shows the running project (Text, Time, Bar.Fill, eased by
  `client/libraries/BarMotion` like the running tile's own bar) with Cancel,
  then how many wait ("1 ready") and what is queued next ("Next: Rich Soil II +1"). Once its
  timer runs out, or while an earlier project waits, `Complete` (gold, pulsing) replaces Cancel
  and completes the first finished project; while it covers Time, the countdown moves into the
  text ("Researching Rich Soil II (4:10)"). With nothing running it reads "2 projects ready to
  complete!".
- **Panning and zoom.** Dragging the background pans the canvas; the mouse wheel zooms it
  (`Canvas.UIScale`, 0.4 to 1.4). Two fingers pinch to zoom without also panning. While open,
  the gamepad's right stick pans smoothly (0.2 dead zone); ButtonL2/ButtonR2 zoom out/in.
  The left stick and D-pad keep their tile selection.

A press waits for the next sync. A tile's icon is an item standing for its line (Belts a belt,
Rich Soil a carrot, a crafting project its recipe's output).

**Completing.** When a sync adds a finished project or a Mastery rank while the window is open, the view glides to
take in it and everything it leads to, and puts the info away. The tile bursts: it pops, a gold
flash and a green ring spread from it, and sparks fly out. After 0.35 s a glow (a white-hot head
in a pulsing halo of the category's colour) runs down every line out of it, drawing the line from
white to the category's colour as it goes, at 420 px a second (each line 0.3 to 0.75 s). Each
undiscovered project it reaches turns over into itself: it springs up from a fifth of its size
with a bounce, a pale flash and a gold ring spread from it, and sparks scatter, and what lies one
step past it grows in as a new "?". These are transient frames. Under reduced motion only the
flashes and rings play, the lines light at once and nothing moves. In the world, FxService sends
`Research` and FxController plays the `ResearchComplete` effect (`Shared/VFX/Effects`, through
`VFXPlayer`) round the player: a soft flash, a gold ground ring and glow, two strands of motes
spiralling up (gold and leaf green), a slow column of light motes, rising sparkles, a warm
Highlight and a light, with the ResearchDone sound.

```text
StarterGui.ResearchView [ScreenGui]      ResetOnSpawn off, IgnoreGuiInset, ScreenInsets None,
                                         DisplayOrder 5
  Research [Frame]   full screen, black, Active; UIScale (the fade's settle); Header.Close
    Body.Active [Frame]  Text, Time [TextLabel]; Bar.Fill [Frame]; Cancel, Complete [TextButton]
    Sky [Frame]      ZIndex 0, under the canvas: Nebulae (Nebula1-3 [ImageLabel], Tinted
                     attribute), Glow [ImageLabel], Far, Mid, Near [Frame] (the screen's clones),
                     Streaks (Streak1-3 [ImageLabel]), Vignette [ImageLabel]
    Canvas [Frame]  UIScale; Links, Nodes [Frame] (rings, hub, orbits, pulses, tags, lines and
                     tiles are drawn round 0,0 by the screen)
    Info [Frame]     400 px, opaque, auto-height list: Name, Description, Level, Cost,
                     Requirements [TextLabel], Items [Frame, wrapping row], Time, Needs
                     [TextLabel]; Action [TextButton] with Label
    Tooltip [Frame]  the same without Action
ReplicatedStorage.Assets.UI.Research.Node [TextButton]  80 px, clear; Shape [Frame] (74%, turned
                     45 degrees, UICorner, UIGradient, UIStroke: the state ring), UIScale, Icon
                     [ViewportFrame], Name, Cost, Mystery ("?") [TextLabel], Progress.Fill [Frame]
ReplicatedStorage.Assets.UI.Research.Link [Frame]  one 3 px line piece; its colour is the unlit one
ReplicatedStorage.Assets.UI.Research.Star [Frame], Mote [ImageLabel]  the sky's star and mote
ReplicatedStorage.Assets.UI.Research.Requirement [Frame]  92 x 104: Box [Frame] with UIStroke
                     (the outline) and Icon [ViewportFrame]; Label [TextLabel] under it
StarterGui.HUD.SideButtons.Research [TextButton]  a flask image Icon (cloned for the hub), Tooltip
```

Played through in Studio: the ripple in and out, the five fans with their colours, tags and
spacing, undiscovered "?" tiles past each shown one, the diamonds' rings (a template stroke with
a mitred join drew squares round rounded shapes; the screen now sets Round), selecting a tile and
pressing empty space, and the info beside a tile with a requirement card green (enough Wheat) and
white (no Wood). Unlocks were driven by a client-only fake ResearchSync from a temporary server
script, so nothing was saved: Sharp Axe I turning Strong Pickaxe I and Sharp Axe II from "?" into
tiles with a new "?" past the pickaxe, Crate Making revealing Carpentry, and Carpentry's three
glows. Earlier (category tabs): a ready project's gold state and Complete, an early Complete
refused, and a start and cancel with its exact refund.

Played through on 2026-11-11 (queue, Mastery, new bonuses), in a fresh garden in save slot 2
(deleted after), driven through the Research remote and the window, with a temporary server
Script to grant coins, XP and items and to load research states:

- Quick Learner I started, Faster Belts I queued behind it ("Next" badge, "Next: Faster Belts
  I" in the strip), a third project refused as the queue was full, and removing the queued one
  refunded 300 coins. When Quick Learner I ran out, Faster Belts I started by itself, one "is
  ready!" notice came, and Quick Learner I pulsed gold with Complete in the strip. Starting
  another then said to complete a finished project to make room; Complete finished it (+10% XP).
- Cancelling Sharp Axe I with Strong Pickaxe I queued behind it refunded both (1,000 coins).
- With every unranked project done: offlineShare 0.15, offlineCap 180, rewardBonus 0.3,
  waterPower 0.1, seedSaver 0.2, luckyDrop 0.3, researchQueue 2, machineSpeed 0.32 with one
  Automation Mastery rank. Two Mastery ranks lined up with their timers past completed as ranks
  2 and 3 (machineSpeed 0.36); ranks 4 and 5 and two other Masteries filled the room of 3.
- After Stop and Play the queue, ranks and finished projects loaded back from the save.
- In the window: Farming Mastery 3's info priced rank 4 (590,000 coins, 10 Pumpkin, 53:48 at
  +45% research speed) with Queue; pressing it queued the rank as "#2". Complete in the strip
  burst the finished Mastery tile. Two flaws found and fixed: Complete covered the countdown
  (now in the text), and a queued Mastery showed the next rank's price beside Remove.
- `Welcome.offlineCoins` at 1,000 a minute for 12 hours: 120,000 coins without research,
  264,000 with all three Night Shifts.

The tidier tree was looked at on 2026-11-12, again in a throwaway garden in slot 2 (deleted
after): a level-1 garden showed only the five first projects and no "?"; at level 4 each opened
first project had a single "?"; at level 15 with everything to level 14 finished, and with every
project finished, each fan opened in separate lanes with no lines crossing. Not checked: a
finished project's hidden branches growing in under the glow.

Not yet seen in play: a Lucky Swing double drop, a seed kept by hand or by a Seed Planter, a
stronger watering can splash, boosted quest and order payouts, and a real offline return with
Night Shift; each is a one-line hook (§ Effect hooks). The window on a phone or with a gamepad.

## Studio playtest

1. Join old and fresh saves without research; compare normal belts, machines, crops, sales,
   XP and stock. Inspect ResearchSync and BeltSpeed.
2. Start with enough coins/items and verify exact debit/deadline. Test low level, missing
   prerequisites/items/coins, unknown/non-string id, malformed action, spam, another active
   project, already-finished id and DataReady false. Refusals must resync without spending.
3. Cancel with room and a full inventory, including multi-item refunds. Verify exact refunds
   once or no changes, then retry after making room.
4. Let a timer run out online and offline, then Complete it; quit/reload another slot and lose
   the session before completing. Check one ready toast, Cancel refused once ready, one
   completion event/toast, saved duration, separate slot bonuses and BeltSpeed removal.
   Load malformed research, unknown ids, NaN/infinite times and already-done active ids;
   expect warnings and a playable garden.
5. Compare two owners' conveyor/router/machine item lanes, drawing and throw-off, plus
   conveyor/router riding.
   Check processor/Workbench/Smelter timing and coal per bar, Planter/Harvester intervals,
   and sprinkler reach at owned-section boundaries.
6. Hand/machine harvest with fractional yield and nearly full inventory/output; harvest by
   hand while a Harvester waits. Check all-or-nothing output and one XP award. Verify normal
   unripe digging/uprooting, growth with rain/sprinklers, normal offline growth, and every
   mutation during Golden Hour, storms and offline ripening.
7. Compare Sell Stand totals and repeated low-value sales from several Shipping Bins for
   one player. Check fractional coin/XP carry, all XP sources, positive/zero stock rolls,
   same-window rejoin and study speed on new projects.
8. Two players chop/mine shared nodes with different research: only the acting player's
   named drop increases; full inventory leaves the node intact.

Formatting, lint and static checks do not replace these Studio tests.
