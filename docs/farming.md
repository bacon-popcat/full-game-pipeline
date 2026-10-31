# Farming

Crops are WorldService nodes in their owner's plot. [plots.md](plots.md) covers ownership
and saving; [economy.md](economy.md) covers stock, sales, XP and the authored HUD.

## Content ownership

`Shared/World.CROPS` is the only crop balance table: name, seed, produce, rarity, seed
price, sell value, total grow time, quarter duration, yield, optional regrow time, fallback
art and colour. The twelve crops and their target numbers are in [overhaul.md](overhaul.md#crops).
`regrow == nil` means single harvest; a number means a permanent multi-harvest plant.

The table generates node stages, `World.PLANTS`, seed/produce catalogue entries and picker
sources. `Inventory/Items` also generates every produce x mutation combination; `item.value`
already contains the multiplier. Seeds have no sell value. Planter seeds derive from the
same table. WheatSeeds, CarrotSeeds, PotatoSeeds and their produce ids remain compatible.

## Growth and harvesting

```text
PlaceBlock -> BuildService (held seed, soil, reach, ownership, overlap)
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
  removes it and returns its seed. Removing its soil still uproots it into owned drops.
- A full inventory leaves the entire hand harvest intact, with a toast. Picker output
  capacity is checked for the entire yield before changing the plant.
- Harvest XP is awarded once per harvest to the plot owner, including machine harvests;
  unripe digging and soil removal give no XP. Discovery is saved on the first harvest.

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

## Farming machines and the watering can

- **Sprinklers speed growth the same save-safe way rain does.** `WorldService.setSpeedModifier`
  takes FactoryService's provider (the best sprinkler over a cell, or 1). Every grow tick banks
  the extra growth since the last tick into `growthBonus`: rain's extra time times the cell's
  speed, plus wall time times (speed - 1). So rain and a sprinkler multiply, a sprinkler placed
  or picked up takes effect within half a second, and the credit is saved with the crop.
  `GrowsAt` divides what's left by both speeds.
- **The Watering Can** (Gear Shop) is used on a growing crop on your own plot: one splash
  banks a fifth of what's left of the crop's current stage into `growthBonus`, with a 1.5 s
  cooldown per player and a server-made splash of droplets. Ripe crops are left alone. The hand
  sends `Interact "Use"` while holding it (BuildController); WorldService checks the crop.
- **Seed Planter** and **Harvester** are in factory.md: the planter fills a 3 x 5 patch
  at its own level, the harvester reaps a 5 x 3 patch behind it at its own level and replants.

## Mutations

`Shared/World/Mutations` owns multipliers, colours and the exclusive roll. On reaching Ripe,
make one random draw with disjoint Rainbow, Golden, Shocked and Wet intervals, followed
by the plain interval. This keeps the stated probabilities exact without stacking mutations.
Golden Hour boosts Golden; storms also count as rain.
A crop has at most one mutation. `mutationRolled` saves a completed plain roll as well as a
variant, preventing rerolls on rejoin. Each harvest resets the next cycle's roll.

A crop that ripened offline rolls only the always-on chances when restored. A ripe saved
mutation or completed plain roll is preserved. `WorldService.setChanceModifiers(provider)`
is the cell hook FactoryService fills with the best sprinkler's +10% Wet;
`chanceModifiers(cell, offline)` combines additive Wet, Shocked and Golden chances with
weather and clamps each to 0..1.

Harvests use `<Produce>+<Mutation>`. Factory processing keeps each variant apart: a batch
takes all its inputs in one mutation and makes that mutation's product, and each variant has
its own input room (factory.md § Processors). The job records exact consumed variant ids for
save/pickup refunds. A Filter Conveyor sorts by picked item, each pick narrowed by its own
mutation checklist.

## Weather

`WeatherService` chooses equally among Rain, Thunderstorm and Golden Hour, with 8-12 minutes
between event starts. It begins clear and waits before the first event. Event lengths and
effects follow [overhaul.md](overhaul.md#weather). Rain and storms add 0.5 growth seconds per
real second, including regrowth. The bonus clock clips at the event end even if the scheduler
wakes late. No weather event harms crops.

`ReplicatedStorage.Weather` is a runtime Folder. `Event` is an event name or an empty string;
`EndsAt` is its end in server-time seconds (zero when clear). No weather remote is needed.
`WeatherController` reads those attributes for camera-local rain and eased lighting requests.
`libraries/Lighting` composes named weather/lightning requests into its own colour-correction
effect, preserving authored Lighting. Rain stops under cover. Lightning is infrequent and
subtle, and is disabled for reduced motion. Rain rate also decreases with reduced motion.

## Art and client effects

All twelve crops have their own art: Wheat, Carrot and Potato from `assets.py`, and the nine
the Garden loop added from `IslandsMachines/build/garden.py` (four stages, the produce item and,
through the finish script, each sprout copied as its seeds' block). They live in their own
showcase sets, `GardenWorld` and `GardenItems`, imported with `studio_import.luau` (SET) and
finished with `studio_blocks.luau`. A multi crop's Mature art is the full plant without fruit,
since it regrows on it; Ripe adds the fruit. Fruit, Vine, Stake and Glow parts don't collide.

`Shared/ItemArt` owns block/seed/produce lookup; Build delegates to it. An authored template
wins, so the tint fallback below now only covers a crop added before its art. Otherwise the crop table's `art` names Wheat, Carrot or Potato: clone that seed/produce
and tint non-Hitbox parts with the crop colour. WorldService's node-art lookup does the same
for stages. Expected fallbacks do not warn; a missing fallback base still uses the existing
placeholder warning. Mutated item icons, hands, drops and belt items use base produce art
with the mutation colour. No source assets are modified.

`CropMutationController` watches ripe nodes' Mutation attributes, tints their non-Hitbox
parts and adds soft particles. It restores captured colours on removal/change. Nearby
Rainbow crops cycle hue at 6 Hz; reduced motion keeps a static colour. Only crops within
100 studs emit, capped at 48 emitters. Art, rows and all screen shells remain place-file work.
