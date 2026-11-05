# Research

`Shared/Research` owns the ordered projects, costs, prerequisites, descriptions, categories,
effect numbers and shared start/duration rules. Crafting recipes (`Shared/Crafting`) name the
project that unlocks them; research stores no recipe links. The Research window shows it all
(§ Window).

Each category is one upgrade tree: a single root project and every other project needing one in
its own category (Farming from Rich Soil I, Automation from Faster Belts I, Economy from Quick
Learner I, Tools from Sharp Axe I, Crafting from Crate Making). Only Master Gardener reaches
across trees, for its Farming needs. `Shared/Research` asserts the shape at load. Finished saves
stay valid however the links change, because needs are checked only when a project starts.

## Flow

```text
DataService: assign plot -> ResearchService.load -> restore ground, blocks, crops
    -> inventory/economy/garden/onboarding -> DataReady
Research Start -> readiness/cooldown/id/level/prerequisites/items/coins -> pay -> active -> sync
Research Cancel -> timer still running -> all refund items fit -> refund coins/items -> clear active -> sync
one-second loop, DataReady only -> timer just ran out -> Notify "ready" once a session -> sync
Research Complete -> timer ran out -> done -> Bonuses + BeltSpeed -> GardenEvents.ResearchDone
    -> Notify -> sync
DataService: snapshot research with balances -> clear research before releasing the plot
```

One project runs at a time on fractional Unix seconds. When its timer runs out it is not done:
it stays active (and saved) until the player presses Complete, which is when its bonus applies
and the completion effects play. `Research.isReady` is the rule; the server accepts a Complete up
to `Research.READY_EARLY` (0.5 s) before the deadline, so a press as a client's countdown ends is
never refused. A ready project cannot be cancelled, and starting another one says to complete it
first. Duration is fixed when it starts,
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
  id; Complete finishes the running project once its timer has run out.
- `ResearchSync`, server to client: `{done = {id, ...}, active = {id, endsAt, seconds}?,
  bonuses = {[stat] = number}}`. Sent on load, start, cancel, complete, when a timer runs out,
  and every refusal. `active` stays past `endsAt` until completed.
  Finished ids follow catalogue order. The deadline converts saved Unix seconds to
  `workspace:GetServerTimeNow()`, so device clocks do not affect the countdown.
- `Notify` explains successful actions and refusals and announces completion.

## Saving

The profile's `research` defaults to `{done = {}, active = nil}`. Done is an id-to-boolean
map; active holds `{id, startedAt, seconds}`. Snapshots copy both tables. Research loads
immediately after plot assignment, before machines and crops, so restored crops' offline
mutation rolls see finished bonuses. Load never announces garden actions or finishes a
project: a project that ran out offline waits for its Complete, and the one-second loop tells
the arriving player it is ready once DataReady is true.

Unknown finished ids, malformed entries and unknown/malformed active projects are dropped
with warnings. Active timestamps and durations must be finite, the timestamp nonnegative
and the duration a positive whole second; an already-finished active id is dropped too.
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
| researchSpeed | `ResearchService.start` calls `Research.duration` once |
| chopYield / mineYield | `WorldService.onInteract` adds the acting player's bonus to the node's named boost item before checking room |

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

**Opening and closing.** The view fades in over 0.4 s while settling from 4% larger, and fades
out over 0.28 s the same way, so the world and the tree cross-fade (the HUD returns as it starts
to fade). The screen animates itself through HubWindow's optional `animate` argument: it takes
every transparency under the view (backgrounds, text, strokes, images and the tiles'
ViewportFrames) from where it stands and eases it to clear and back. A CanvasGroup was tried and
does not work here: Studio rendered its children unfaded and unclipped, and ViewportFrames ignore
`GroupTransparency`. The canvas also glides in from 82% zoom. Reduced motion shows and hides it at
once.

All the projects form one tree on `Research.Canvas`, growing out of a round hub in its middle (the
side button's flask). The view always opens centred on the hub with nothing selected.

- **Arms.** Each category is an arm out of the hub: Farming up, Automation right, Economy down,
  Crafting left, and Tools up and to the left (its first project 2.2 hub-steps out on both axes,
  growing up, its first branch to the left). An arm's first project sits 150 px from the hub.
- **Layout along an arm.** A project's step out is how many projects lead to it in its category,
  140 px apart; it hangs off its latest need. Children that continue its line (Yield1 -> Yield2)
  run straight on; the other branches take alternate sides of the arm, nearest first, 136 px
  apart. Tiles are cloned from `Assets.UI.Research.Node`, with the name under each.
- **Lines.** Each arm's first project is joined to the hub by a straight line. Each need in the
  same category is joined to the project by an elbowed line of `Assets.UI.Research.Link` pieces:
  on along the need's branch, across at the gap before the project, on into it. Each piece is a
  turned Link holding a green `Lit` fill; lines out of a finished project are lit (a line from the
  hub once its project is done). Master Gardener's needs in other categories draw no line.
- **Only what is in reach.** A tile shows when it is an arm's first project, done, running, or
  needs a finished project in its own category. Lines show when both ends do.
- **States.** A tile's border says its state: green done, yellow can start, red locked (its item
  and name faded), blue running (with a progress bar), gold and pulsing ready to complete.
- **Cost badge.** Open and locked tiles show the optional `Node.Cost` label: plain coins below
  1,000, then K/M with one decimal and no trailing .0. Red when unaffordable, otherwise its
  authored text colour; updates with the wallet. Hidden for running, ready and done projects.
- **Info.** Pressing a tile selects it: the canvas glides it 210 px left of the middle and
  `Research.Info` (400 px wide) stands beside it, on its right or, without room, its left, level
  with it and clear of the close button and the strip. It shows the name (in its state's colour),
  description, level and state, cost (red when you can't afford it), then under "Requirements" a
  card per required item, cloned from `Assets.UI.Research.Requirement`: the item's picture in a box
  with "x20 Wheat" under it, its outline and words green once you carry that many. Then the time
  behind an hourglass ("2:00", "1:30:00"; for the running project, the time left), any blocker,
  and an Action button: Research, Complete, Running, Busy, Locked, Need coins, Need items or Done.
  Done hides the requirements and the time. Cards are rebuilt only when the project changes.
  Without the Requirement template the items are listed as words. Hovering (or gamepad-selecting)
  another tile shows the same in `Research.Tooltip`, without the button.
- **Putting the info away.** A press on empty space (not a tile, the hub, the info or the strip)
  that never becomes a drag deselects, centring the tile. Pressing the hub glides home.
- **Active strip.** `Body.Active` shows the running project (Text, Time, Bar.Fill) with Cancel;
  once its timer runs out it reads "<name> is ready!" and `Complete` (gold, pulsing) replaces
  Cancel.
- **Panning and zoom.** Dragging the background pans the canvas; the mouse wheel zooms it
  (`Canvas.UIScale`, 0.5 to 1.4). Two fingers pinch to zoom without also panning. While open,
  the gamepad's right stick pans smoothly (0.2 dead zone); ButtonL2/ButtonR2 zoom out/in.
  The left stick and D-pad keep their tile selection.

A press waits for the next sync. A tile's icon is an item standing for its line (Belts a belt,
Rich Soil a carrot, a crafting project its recipe's output).

**Completing.** When a sync adds a finished project while the window is open, the view glides to
take in it and everything it leads to, and puts the info away. The tile bursts: it pops, a gold
flash and a green ring spread from it, and sparks fly out. After 0.35 s a glow (a white-hot head
in a pulsing gold halo) runs down every line out of it, drawing the line in gold turning green as
it goes, at 420 px a second (each line 0.3 to 0.75 s). Each project it reaches that was out of
reach before pops in: it grows from a fifth of its size with a bounce, a pale flash and a gold
ring spread from it, and sparks scatter. These are transient frames. Under reduced motion only the
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
    Canvas [Frame]  UIScale; Links, Nodes [Frame] (the hub and tiles are drawn round 0,0)
    Info [Frame]     400 px, opaque, auto-height list: Name, Description, Level, Cost,
                     Requirements [TextLabel], Items [Frame, wrapping row], Time, Needs
                     [TextLabel]; Action [TextButton] with Label
    Tooltip [Frame]  the same without Action
ReplicatedStorage.Assets.UI.Research.Node [TextButton]  84 px; UIStroke (the state border),
                     UIScale, Icon [ViewportFrame], Name, Cost [TextLabel], Progress.Fill [Frame]
ReplicatedStorage.Assets.UI.Research.Link [Frame]  one 4 px line piece; its colour is the unlit one
ReplicatedStorage.Assets.UI.Research.Requirement [Frame]  92 x 104: Box [Frame] with UIStroke
                     (the outline) and Icon [ViewportFrame]; Label [TextLabel] under it
StarterGui.HUD.SideButtons.Research [TextButton]  a flask icon (cloned for the hub), Tooltip
```

Played through in Studio: the fade in and out, the tree opening on the hub with only what is in
reach, selecting a tile and pressing empty space, the info beside a tile with a requirement card
green (enough Wheat) and white (no Wood), and the hourglass time. Unlocks were driven by a
client-only fake ResearchSync from a temporary server script, so nothing was saved: Sharp Axe I
revealing Sharp Axe II and Strong Pickaxe I, Crate Making revealing Carpentry, and Carpentry's
three glows (one straight, two elbowed) with Wooden Belts popping in as its glow arrived. Earlier
(category tabs): a ready project's gold state and Complete, an early Complete refused, and a start
and cancel with its exact refund.

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
