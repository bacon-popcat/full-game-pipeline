Median of 9 stock rolls; mutation EV; miners 1; quarry share 1; build share 0.5; minutes from join.
Before = before.json with the coin Machine Shop; After = current content, machines crafted.
| Milestone | Before | After |
|---|---:|---:|
| Level 2 | 9.6 | 1.9 |
| Level 3 | 18.8 | 8.1 |
| Level 4 | 27.4 | 14.9 |
| Level 5 | 34.4 | 21.0 |
| Level 6 | 42.7 | 26.2 |
| Level 7 | 53.2 | 32.2 |
| Level 8 | 65.8 | 37.3 |
| Level 9 | 82.8 | 43.8 |
| Level 10 | 99.4 | 48.5 |
| Level 11 | 109.4 | 52.7 |
| Level 12 | 120.4 | 59.9 |

Beyond level 12 the run is extrapolated, not simulated: the model keeps playing one hour past
level 12 and takes the XP/min earned in that hour (every tier-one machine owned, no new
expansion, no tier-two machines, no rare crops) as a flat rate for all later levels.
| Milestone | Before | After | After lifetime XP |
|---|---:|---:|---:|
| Level 15 (extrapolated) | 162.7 | 86.2 | 17,321 |
| Level 20 (extrapolated) | 270.3 | 165.1 | 44,071 |
| Level 30 (extrapolated) | 640.6 | 514.2 | 162,431 |
| Level 40 (extrapolated) | 1258.2 | 1237.0 | 407,448 |
| Level 50 (extrapolated) | 2161.8 | 2481.9 | 829,520 |
| steady XP/min | 329.0 | 339.0 | |
| hand net coins/min | 459.2 | 277.8 |
| automation net coins/min | 1079.5 | 1605.3 |
| processors net coins/min | 1696.8 | 2303.2 |

Crafted machines, in the order the model builds them (median minutes from join; level then).
Raw is what one costs from an empty inventory, belts included; coal is the Smelter's fuel.
| Machine | Bench tier | Before bought | After crafted | Level then | Raw |
|---|---:|---:|---:|---:|---|
| ShippingBin | 1 | 9.9 | 2.5 | 2 | 3 wood |
| Smelter | 1 | 19.1 | 3.6 | 2 | 16 stone, 1 wood |
| BenchTier2 | 2 | - | 8.1 | 3 | 8 iron, 3 coal, 30 stone, 10 wood |
| Workbench | 2 | 19.6 | 11.1 | 3 | 8 iron, 2 copper, 4 coal, 2 wood |
| SeedPlanter | 2 | 27.8 | 14.2 | 3 | 10 iron, 4 coal, 2 wood |
| Sprinkler | 2 | 34.8 | 16.1 | 4 | 4 iron, 4 copper, 3 coal |
| BenchTier3 | 3 | - | 27.8 | 6 | 48 iron, 12 copper, 20 coal, 8 wood |
| Harvester | 3 | 43.1 | 33.2 | 7 | 17 iron, 4 copper, 7 coal, 5 wood |
| Mill | 2 | 53.2 | 35.3 | 7 | 7 iron, 3 coal, 20 stone, 3 wood |
| Juicer | 2 | 65.8 | 37.6 | 8 | 11 iron, 4 coal, 1 wood, 4 glass |
| CratePacker | 3 | 82.8 | 41.9 | 8 | 17 iron, 6 coal, 5 wood |
| Oven | 3 | 99.4 | 43.9 | 9 | 7 iron, 2 copper, 3 coal, 1 wood, 20 bricks |

To the first Harvester, from nothing: 95 iron, 22 copper, 41 coal, 46 stone, 31 wood.
Hand time gathering (walks, mining, chopping, waiting at rocks) before it: 13.8 of 33.2 min.

Mk II machines (Fabricator), parts only, not crafted in the run; supplied minutes are one
Smelter and one Assembler working serially from ore, excluding mining:
SeedPlanterTier2: {'SteelFrame': 3, 'Gear': 6}, 4.7 min supplied, 24 iron, 8 coal, 3 stone
SprinklerTier2: {'Circuit': 4, 'CopperWire': 6}, 5.0 min supplied, 8 iron, 14 copper, 8 coal
MillTier2: {'SteelFrame': 2, 'Gear': 8}, 4.7 min supplied, 24 iron, 8 coal, 2 stone
HarvesterTier2: {'SteelFrame': 3, 'Circuit': 6}, 7.9 min supplied, 24 iron, 12 copper, 12 coal, 3 stone
JuicerTier2: {'SteelFrame': 2, 'Circuit': 4}, 5.3 min supplied, 16 iron, 8 copper, 8 coal, 2 stone
OvenTier2: {'SteelFrame': 3, 'Circuit': 4}, 6.0 min supplied, 20 iron, 8 copper, 10 coal, 3 stone
First-harvest seed losses before / after: ['Strawberry', 'Corn', 'Pumpkin', 'Watermelon'] / []
Coins a minute from one cell on a Harvester, plain, by rarity (lowest-highest): Common 36-36, Uncommon 60-79, Rare 90-144, Epic 180-200, Legendary 400-520, Mythic 1440-1440
Rarities out-earned by the one below, before / after: ['Uncommon over Rare', 'Rare over Epic'] / []
All valued recipes beat their immediate inputs, for every mutation.

Mid-game products: value over the plain worth of the crops inside (1 machine x1.5, 2 x3, 3 x4.5).
| Product | Machine | Machines deep | Crops inside | Their worth | Value |
|---|---|---:|---|---:|---:|
| Crisps | Roaster | 1 | 2 Potato | 220 | 330 |
| Popcorn | Roaster | 1 | 2 Corn | 720 | 1,100 |
| RoastPumpkin | Roaster | 1 | 1 Pumpkin | 1,600 | 2,400 |
| TomatoSauce | Kettle | 1 | 4 Tomato | 180 | 270 |
| StrawberryJam | Kettle | 2 | 5 Strawberry | 75 | 230 |
| BlueberryJam | Kettle | 2 | 5 Blueberry | 150 | 450 |
| AppleJam | Kettle | 2 | 5 Apple | 450 | 1,400 |
| GrapeJam | Kettle | 2 | 5 Grape | 1,300 | 3,900 |
| Pizza | Oven | 2 | 2 Wheat, 4 Tomato | 204 | 610 |
| PumpkinPie | Oven | 2 | 2 Wheat, 1 Pumpkin | 1,624 | 4,900 |
| StrawberryJamTart | Oven | 3 | 2 Wheat, 5 Strawberry | 99 | 450 |
| BlueberryJamTart | Oven | 3 | 2 Wheat, 5 Blueberry | 174 | 780 |
| AppleJamTart | Oven | 3 | 2 Wheat, 5 Apple | 474 | 2,100 |
| GrapeJamTart | Oven | 3 | 2 Wheat, 5 Grape | 1,324 | 6,000 |
| WatermelonSorbet | Chiller | 2 | 1 Watermelon, 3 Strawberry | 4,045 | 12,000 |
| StarfruitSorbet | Chiller | 2 | 2 Starfruit, 3 Blueberry | 3,690 | 11,000 |

One Harvester Mk II patch (35 cells) of a crop, plain coins a minute: sold raw, and as the
best product it is the main crop of (other inputs grown elsewhere, machines as needed).
| Crop | Rarity | Raw | Best product | Through it | Machines for it |
|---|---|---:|---|---:|---|
| Carrot | Common | 1,260 | CarrotCrate | 1,512 | 0.3 CratePacker |
| Wheat | Common | 1,260 | Flour | 2,100 | 3.5 Mill |
| Strawberry | Uncommon | 2,100 | StrawberryPie | 17,500 | 9.3 Oven |
| Potato | Uncommon | 2,750 | Crisps | 4,125 | 1.2 Roaster |
| Tomato | Rare | 3,150 | Pizza | 10,675 | 2.3 Oven |
| Corn | Rare | 3,150 | Popcorn | 4,812 | 0.4 Roaster |
| Blueberry | Rare | 5,040 | BlueberryPie | 33,600 | 11.2 Oven |
| Pumpkin | Epic | 7,000 | PumpkinPie | 21,438 | 0.6 Oven |
| Apple | Epic | 6,300 | AppleJamTart | 29,400 | 1.9 Oven |
| Watermelon | Legendary | 14,000 | WatermelonSorbet | 42,000 | 0.6 Chiller |
| Grape | Legendary | 18,200 | GrapeJamTart | 84,000 | 1.9 Oven |
| Starfruit | Mythic | 50,400 | StarfruitSorbet | 154,000 | 2.3 Chiller |

Every coin sink: research 5,268,400 + garden sections 1,027,500 = 6,295,900 coins.
One raw Blueberry patch pays for all of it in 20.8 hours.
One raw Apple patch pays for all of it in 16.7 hours.
One raw Grape patch pays for all of it in 5.8 hours.
One raw Starfruit patch pays for all of it in 2.1 hours.
The best patch above (154,000 a minute) pays for all of it in 0.7 hours.

Orders and daily quests against a level (an order asks for Economy.scale coins of goods):
| Level | Order's goods | Order XP | Over selling them | Level costs | Order / level | Day's quests / level |
|---:|---:|---:|---:|---:|---:|---:|
| 5 | 2,000 | 400 | +200 | 382 | 105% | 15% |
| 10 | 6,000 | 1,200 | +600 | 1,695 | 71% | 15% |
| 15 | 11,000 | 2,200 | +1,100 | 4,053 | 54% | 15% |
| 20 | 18,000 | 3,600 | +1,800 | 7,523 | 48% | 15% |
| 30 | 35,000 | 7,000 | +3,500 | 17,988 | 39% | 15% |
An order pays 1.5x its goods' coins and 2x their sale XP. In the steady hour the run nets 2,303 coins a minute, so delivering all of it as orders adds at most 230 XP a minute to 339 (68%).
Minutes from join, with orders at that most from level 12 on (the first column is the table above):
| Milestone | No orders | Every sale an order |
|---|---:|---:|
| Level 15 | 86.2 | 75.7 |
| Level 20 | 165.1 | 122.8 |
| Level 30 | 514.2 | 330.4 |
