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
close button, the category tabs along the top and the running project's strip along the bottom.
HudVisibility arbitrates `HUD.Enabled` by named requests, so the save menu (HUD only) and the
Research view never fight over it. `Body.Tabs.Farming`, `Automation`, `Economy`, `Tools` and
`Crafting` pick a category, whose tree is drawn on `Research.Canvas`:

- **Layout.** A project's column is how many projects lead to it in its tree; it hangs off its
  latest need. Children that continue its line (Yield1 -> Yield2) run straight along its row;
  each other child starts a row of its own below. Tiles are cloned from
  `Assets.UI.Research.Node`, 140 px apart across and 136 down, with the name under each.
- **Lines.** Each need in the same tree is joined to the project by an elbowed line of
  `Assets.UI.Research.Link` pieces: across, down at the gap before the project, across into it.
  Lines out of a finished project are lit green.
- **States.** A tile's border says its state: green done, yellow can start, red locked (its item
  and name faded), blue running (with a progress bar), gold and pulsing ready to complete.
- **Cost badge.** Open and locked tiles show the optional `Node.Cost` label: plain coins below
  1,000, then K/M with one decimal and no trailing .0. Red when unaffordable, otherwise its
  authored text colour; updates with the wallet. Hidden for running, ready and done projects.
- **Info.** Pressing a tile selects it: the canvas glides to bring it just below the middle of the
  screen and `Research.Info` stands above it, with its name (in its state's colour), description,
  level and state, cost (red when you can't afford it), and the time, items and blocker, and an
  Action button: Research, Complete, Running, Busy, Locked, Need coins, Need items or Done.
  Hovering (or gamepad-selecting) another tile shows the same in `Research.Tooltip` above that
  one, without the button. On opening a tab, the running project is selected, else the first that
  can start, else the root.
- **Active strip.** `Body.Active` shows the running project (Text, Time, Bar.Fill) with Cancel;
  once its timer runs out it reads "<name> is ready!" and `Complete` (gold, pulsing) replaces
  Cancel.
- **Panning and zoom.** Dragging the background pans the canvas; the mouse wheel zooms it
  (`Canvas.UIScale`, 0.6 to 1.4). Two fingers pinch to zoom without also panning. While open,
  the gamepad's right stick pans smoothly (0.2 dead zone); ButtonL2/ButtonR2 zoom out/in.
  The left stick and D-pad keep their tile selection.

A press waits for the next sync. A tile's icon is an item standing for its line (Belts a belt,
Rich Soil a carrot, a crafting project its recipe's output).

**Completing.** When a sync adds a finished project while the window is open, the screen switches
to its tree, glides to it and bursts it: the tile pops, a gold flash and a green ring spread from
it, sparks fly out, and the lines to what it unlocks light up one after another. These are
transient frames; under reduced motion only the flash and ring play, without moving. In the
world, FxService sends `Research` and FxController plays the `ResearchComplete` effect
(`Shared/VFX/Effects`, through `VFXPlayer`) round the player: a soft flash, a gold ground ring and
glow, two strands of motes spiralling up (gold and leaf green), a slow column of light motes,
rising sparkles, a warm Highlight and a light, with the ResearchDone sound.

```text
StarterGui.ResearchView [ScreenGui]      ResetOnSpawn off, IgnoreGuiInset, ScreenInsets None,
                                         DisplayOrder 5
  Research [Frame]   full screen, black, Active; UIScale; Header.Close
    Body.Tabs.<Category> [TextButton]
    Body.Active [Frame]  Text, Time [TextLabel]; Bar.Fill [Frame]; Cancel, Complete [TextButton]
    Canvas [Frame]  UIScale; Links, Nodes [Frame]
    Info [Frame]     auto-height list: Name, Description, Level, Cost, Needs [TextLabel];
                     Action [TextButton] with Label
    Tooltip [Frame]  the same without Action
ReplicatedStorage.Assets.UI.Research.Node [TextButton]  84 px; UIStroke (the state border),
                     UIScale, Icon [ViewportFrame], Name, Cost [TextLabel], Progress.Fill [Frame]
ReplicatedStorage.Assets.UI.Research.Link [Frame]  one 4 px line piece; its colour is the unlit one
StarterGui.HUD.SideButtons.Research [TextButton]  a flask icon, Tooltip
```

Played through in Studio: the trees, the HUD hiding and coming back, hover and selected info, a
ready project's gold state and Complete, completing it (the view switching to its tree, the tile
turning green, its lines lit and three projects unlocking), an early Complete refused, and a start
and cancel with its exact refund. The ready project was loaded from a snapshot. The save's
research was restored afterwards, and a fresh session confirmed it had saved.

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
