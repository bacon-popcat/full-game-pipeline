# Farming

Crops are WorldService nodes in their owner's plot, and grow only on Farmland: grass and dirt
tilled with the Hoe (§ Ground and Farmland). [plots.md](plots.md) covers
ownership and saving; [economy.md](economy.md) covers stock, sales, XP and the authored HUD.

## Content ownership

`Shared/World.CROPS` is the only crop balance table: name, seed, produce, rarity, seed
price, sell value, total grow time, quarter duration, yield, optional regrow time, fallback
art and colour. The twelve crops and their target numbers are in [overhaul.md](overhaul.md#crops).
`regrow == nil` means single harvest; a number means a permanent multi-harvest plant.

The table generates node stages, `World.PLANTS`, seed/produce catalogue entries and Harvester
sources. `Inventory/Items` also generates every produce x mutation combination; `item.value`
already contains the multiplier. Seeds have no sell value. Planter seeds derive from the
same table. WheatSeeds, CarrotSeeds, PotatoSeeds and their produce ids remain compatible.

## Growth and harvesting

```text
PlaceBlock -> BuildService (held seed, Farmland under it, reach, ownership, overlap)
              -> WorldService.plant -> crop node in Workspace.World
                 -> grow -> stage art + replicated attributes
Interact Take -> capacity check -> yield -> harvest XP/discovery
FactoryService -> source (current variant) -> output room check -> reap -> yield
DataService -> snapshot/restore crop cycle and rain credit
```

- Unripe hand digging returns one seed. Ripe single crops give only their yield and are
  removed. A machine restarts a single crop at Sprout without spending a seed.
- Ripe multi crops give their fruit and return to Mature. Each subsequent fruit cycle
  takes `regrow` seconds; harvesting never removes the plant. Hand digging while unripe
  removes it and returns its seed. Mining the Farmland under any crop uproots it into owned
  drops (`WorldService.uproot`).
- A full inventory leaves the entire hand harvest intact, with a toast. Harvester output
  capacity is checked for the entire yield before changing the plant.
  Yield research rolls once for both capacity and output; unripe digging and uprooting are unchanged (research.md).
- Harvest XP is awarded once per harvest to the plot owner, including machine harvests;
  unripe digging and soil removal give no XP. Discovery is saved on the first harvest.
  EconomyService applies XP research to that award and carries fractional XP.
- **Trees keep their column clear.** Apple and Starfruit grow four cells tall (`World.CROPS`
  `height`). From planting, each keeps that column, one cell wide, above its own cell: a seed
  (by hand or Seed Planter) won't plant unless the whole column is clear and on owned land
  (`World.plantColumn`, checked by BuildService, the placing ghost and `WorldService.canPlant`),
  and WorldService stretches those crops' template hitboxes to the column at startup, so no
  block can be placed in it. A tree saved before this rule loads even with blocks over it.

The initial grow time is four equal quarters. Sprout, Young and Mature use the first three;
the fourth is final ripening, still showing Mature art until the full listed duration is
reached. Ripe is immediately harvestable at that endpoint. This resolves the design's four
quarters versus only three transitions to a harvestable Ripe model. The hover panel calls
the fourth quarter Ripening. Multi regrowth stays Mature until its regrow deadline.

Growth uses `wallTime() - plantedAt + growthBonus`; wallTime is fractional Unix seconds
from DateTime. Phase 1 integer timestamps remain valid. `plantedAt` is the current cycle's Unix
start (reset by reaping), and `harvestCount` distinguishes initial growth from multi regrowth.
WorldService samples at 0.5 seconds and publishes deadlines only when they change; weather supplies an integrated clock of extra rain
seconds. Each growing crop banks only changes since its last sample, including a final
sample when saving. Completed fruit never accumulates credit for a future cycle.

Offline time advances at normal speed, with previously banked rain credit preserved. It
never simulates harvests, machines, or historical weather. Restoration starts a new live
weather-clock baseline, so rejoining cannot add the server's past rain again. Phase 1 crops
without the new optional fields default to zero bonus and an unrolled mutation.

Replicated crop attributes are `NodeType`, `Cell`, `PlantedAt`, `HarvestCount`, `Mutation`,
`Regrowing`, `Ripening` and `GrowsAt`. `GrowsAt` is the next quarter/regrow deadline in
`workspace:GetServerTimeNow()` seconds, adjusted for the current speed. BlockInfo reads
these for the crop/mutation name, stage, status, countdown and whole-harvest sale value.

## Ground and Farmland

Every garden's owned land is ground (`Shared/World/Ground`): grass at y = -1, its top flush with
y = 0, two levels of dirt under it, then stone down to `Plot.FLOOR` (-8), with bedrock below.
There is no untilled Farmland: every farm is tilled (older saves keep their old starter farm as
tilled cells, plots.md). Each cell is a
WorldService node marked `ground` (GrassGround, DirtGround, StoneGround, Farmland), but only
exposed cells, those with a face open to the air, stand as nodes, so an untouched garden is one
layer of blocks and digging uncovers the cells round the hole. `GroundService` owns it:

- **Digging.** The owner's Pickaxe mines a ground cell for the block it is: Grass, Dirt or Stone,
  and Farmland gives the Dirt it was tilled from. A crop on it is uprooted. A full inventory
  leaves the cell, with a toast. Blocks can be built in the holes, down to the floor.
- **Tilling.** The owner's Hoe turns grass or dirt into Farmland in the same cell: ground, or a
  placed Grass or Dirt block (`World.TILLABLE_BLOCKS`), which stops being a placed block and
  becomes Farmland ground in its cell. Stone does not till. Seeds, by hand or Seed Planter,
  plant only on Farmland (`Soil.isUnder` finds a `soil` node under the cell); grass, dirt and
  placed blocks no longer take seeds. The Hoe is in the starter kit and the Gear Shop.
- **Grass regrowth.** Dirt ground with open air above it (dug down to, or uncovered) grows
  over into grass after a random 60-120 seconds; something solid on top restarts the wait.
  Saved like digging and tilling (`grassed`).
- **Wet Farmland.** Farmland is wet while a sprinkler covers the crop cell above it (the
  sprinkler's own level, `WorldService.speedAt`) or it is raining (Rain or Thunderstorm), checked
  every second, and dries `Ground.WET_FOR` (120) seconds after neither reaches it. Wet is a darker
  look and a `Wet` attribute that the hover panel names ("Wet Farmland"); it changes nothing else
  and is not saved.
- **Art.** Grass, dirt and stone ground are copies of the Grass, Dirt and Stone blocks
  (`Assets.Blocks`, the node's `art`). Farmland is built in code by `server/libraries/GroundArt`:
  a cube of the game's dirt texture (World/GroundLook, Texture objects on its top and sides)
  shaded down into furrows, with three raised ridges in the dirt's own colour, all darkened when
  wet. `Assets.World.Farmland`, the old dark art, is no longer used.
- **Saving.** Only where a garden differs from untouched is kept: dug cells and tilled cells, plot
  relative ([plots.md](plots.md#profile-contents)). Building and restoring stand the exposed
  cells round each change; BuildService refuses any placement that takes solid ground
  (`GroundService.isClear`), even one a client aims into buried cells.

## Farming machines and the watering can

- **Sprinklers speed growth the same save-safe way rain does.** `WorldService.setSpeedModifier`
  takes FactoryService's provider (the best sprinkler over a cell, or 1). Every grow tick banks
  the extra growth since the last tick into `growthBonus`: rain's extra time times the cell's
  speed, plus wall time times (speed - 1). So rain and a sprinkler multiply, a sprinkler placed
  or picked up takes effect within half a second, and the credit is saved with the crop.
  `GrowsAt` divides what's left by both speeds.
  Growth research multiplies the cell speed and banks online credit the same way; offline growth stays normal.
- **The Watering Can** (Gear Shop) is used on a growing crop on your own plot: one splash
  banks a fifth of what's left of the crop's current stage into `growthBonus`, with a 1.5 s
  cooldown per player and a server-made splash of droplets. Ripe crops are left alone. The hand
  sends `Interact "Use"` while holding it (BuildController); WorldService checks the crop.
- **Seed Planter** and **Harvester** are in factory.md: the planter fills a 3 x 5 patch
  at its own level, the harvester reaps a 5 x 3 patch behind it at its own level and replants.

## Mutations

`Shared/World/Mutations` owns multipliers, colours, keys and the roll. Mutations stack: on
reaching Ripe, Wet, Shocked, Golden and Rainbow each roll on their own chance, so a crop can
come out Wet and Golden at once. A set of mutations is a key, its names in value order joined
by "+" (`Wet+Golden`); a set's multiplier is 1 plus each mutation's bonus over plain (Wet x2 +
Golden x20 = x21). Golden Hour boosts Golden; storms also count as rain.
`mutationRolled` saves a completed plain roll as well as a variant, preventing rerolls on
rejoin. Each harvest resets the next cycle's roll. A save from before stacking holds one
name, which is already a valid key.

A crop that ripened offline rolls only the always-on chances when restored. A ripe saved
mutation or completed plain roll is preserved. `WorldService.setChanceModifiers(provider)`
is the cell hook FactoryService fills with the best sprinkler's +10% Wet;
`chanceModifiers(cell, offline)` combines additive Wet, Shocked and Golden chances with
weather; Mutations.roll applies research to every final chance before clamping to 0..1.
Mutation research includes Rainbow and offline always-on rolls; sprinkler reach research is applied by FactoryService.

Harvests use `<Produce>+<key>` (`Carrot+Wet+Golden`); Items generates all fifteen sets for
every produce and valued product. Factory processing keeps each variant apart: a batch
takes all its inputs in one set of mutations and makes that set's product, and each variant has
its own input room (factory.md § Processors). The job records exact consumed variant ids for
save/pickup refunds. A Filter Conveyor sorts by picked item, each pick narrowed by its own
mutation checklist; a stacked item passes when any of its mutations is ticked.
`CropMutationController` tints a stacked crop in its most valuable mutation's colour and
sparkles it in all of them.

## Weather

`WeatherService` chooses equally among Rain, Thunderstorm and Golden Hour, with 8-12 minutes
between event starts. It begins clear and waits before the first event. Event lengths and
effects follow [overhaul.md](overhaul.md#weather). Rain and storms add 0.5 growth seconds per
real second, including regrowth. The bonus clock clips at the event end even if the scheduler
wakes late. No weather event harms crops.

`ReplicatedStorage.Weather` is a runtime Folder. `Event` is an event name or an empty string;
`EndsAt` is its end in server-time seconds (zero when clear). No weather remote is needed.
`WeatherController` reads those attributes for camera-local rain and eased lighting requests.
`libraries/Lighting` composes named weather/lightning requests on top of the look's colour
grade ([lighting.md](lighting.md)). Rain stops under cover. Lightning is infrequent and
subtle, and is disabled for reduced motion. Rain rate also decreases with reduced motion.

## Art and client effects

All twelve crops' growth stages and seeds are built by `IslandsMachines/build/crops.py` in Blender, kept simple: a
few curved, two-sided leaves with real outlines (strap, lance, ovate, palmate, compound), tapering stems, fruit
turned on a lathe, colour that drifts from base to tip and from plant to plant, and smooth shading (roblox_data
exports the normals; studio_import uses them). A crop has no soil of its own; it grows straight out of the
Farmland under it. Crops are drawn tall, standing up to almost two cells high and reaching a little into the
neighbouring cells (the two trees, Apple and Starfruit, are drawn at their real size instead,
uniformly scaled, about 13 studs when grown and 6.5 as saplings, their crowns within 2.7 studs of
the trunk), yet each is still one cell wide to the game: `studio_blocks.luau` pins GardenWorld's hitboxes to one
cell, and overlap tests count only hitboxes (`Build.isCoveredArt`), so the art never blocks planting or building
beside it. One scale per crop, so it never shrinks as it grows.

Each stage comes in five looks, so a field isn't rows of clones: `<Crop><Stage>` and `<Crop><Stage>Variant2` to
`Variant5` in `Assets.World` (`crops.VARIANTS`). Each is laid out differently, bent its own way (leaves higher on one
side, the plant twisting as it rises, so fruit hangs in other places), drawn at its own height and leaf tint, and
some are mirrored. Every leaf drifts a little from its crop's greens, and each fruit or vegetable is its own size and
shade.
WorldService picks one per cell from the cell's position, the same for every stage, so a plant keeps its look as
it grows and after a rejoin; nothing is saved. The node, its name and everything the client reads stay the stage's. The stages are imported as the
`GardenWorld` showcase set and the seeds as `GardenSeeds` with `studio_import.luau` (SET), then finished with
`studio_blocks.luau`. A multi crop's Mature art is built as its Ripe art with the fruit taken off (`crops.REGROWS`),
in every look, so a harvest changes nothing but the fruit: the leaves stay exactly where they were. WorldService
keeps the standing model between those two stages (`morph`): a harvest takes the fruit parts off it and ripening
adds them back, instead of swapping in the other stage's model, whose leaves are a different mesh and blinked the
first time one was drawn. Stages whose shared parts don't match exactly still swap the whole model. The produce items are still `garden.py`'s and `assets.py`'s.

Part keys decide what moves: `Stake` (canes, trellis posts, ties) and `Tuber` (roots and tubers in the ground)
never move; `Crop`, `Bark`, `Vine`, `Fruit`, `Bloom`, `Grain` and `Glow` sway. None of them collide, so players walk
through a field.

A seed is its own block, `Assets.Blocks.<Crop>Seeds`: a little open sack heaped with that crop's seed (potatoes:
small sprouting seed potatoes) and a label in the crop's colour. It is what the hand, icons and drops show. The
placement ghost instead shows the sprout the seed plants as (`BuildController`), green only over Farmland.

`Shared/ItemArt` owns block/seed/produce lookup; Build delegates to it. An authored template
wins, so the tint fallback below now only covers a crop added before its art. Otherwise the crop table's `art` names Wheat, Carrot or Potato: clone that seed/produce
and tint non-Hitbox parts with the crop colour. WorldService's node-art lookup does the same
for stages. Expected fallbacks do not warn; a missing fallback base still uses the existing
placeholder warning. Mutated item icons, hands, drops and belt items use base produce art
with the mutation colour. No source assets are modified.

### Plant movement

`PlantSwayController` makes crops sway in the wind and bend aside when someone walks through them, then spring
back. It is drawn only on each client and changes nothing on the server: no remote, no physics, and the server's
crop parts, saves and aim stay put.

- **One tilt per plant.** A crop's moving parts turn together about the centre of its cell's floor (from its
  `Cell` attribute), so taller plants sweep further at the top. `FLEX` makes trees and trained vines (Apple,
  Starfruit, Grape, Tomato, Corn) give less than soft plants.
- **Wind.** A small steady lean downwind, gusts that roll across the garden as a wave (so a field ripples rather
  than nodding in step), and a little flutter across the wind at each plant's own pace. The wind veers slowly.
  Rain blows harder, a Thunderstorm harder still, Golden Hour is calmer (`ReplicatedStorage.Weather`). Reduced
  motion stills the wind.
- **Walking through.** Every player character within `PUSH_RADIUS` of a plant (across the ground, and not far above
  or below it) pushes it away from them, more the closer they are, up to `PUSH_ANGLE`. A damped spring chases that
  target, so a plant bends as you pass and springs back with one soft overshoot. Reduced motion keeps this, since it
  answers the player's own movement. Other players push crops too.
- **Cost.** Plants are found by cell around each character, so pushes cost nothing away from players. Plants
  past `FAR` from the camera are put back at rest and skipped; those past `NEAR` update every other frame; a
  plant whose tilt barely changed isn't moved. Everything moves in one `workspace:BulkMoveTo` per frame.
- **Rest poses.** A part's rest pose is taken the first time the controller sees it, before moving it, and parts
  that stream in later join the plant at theirs. A new stage is a new model, so growing never inherits a lean.

`CropMutationController` watches ripe nodes' Mutation attributes, tints their non-Hitbox
parts and adds soft particles. It restores captured colours on removal/change. Nearby
Rainbow crops cycle hue at 6 Hz; reduced motion keeps a static colour. Only crops within
100 studs emit, capped at 48 emitters. Art, rows and all screen shells remain place-file work.
