Median of 9 stock rolls; mutation EV; miners 1; quarry share 1; build share 0.5; minutes from join.
Before = before.json with the coin Machine Shop; After = current content, machines crafted.
| Milestone | Before | After |
|---|---:|---:|
| Level 2 | 9.6 | 3.7 |
| Level 3 | 18.8 | 8.5 |
| Level 4 | 27.4 | 15.5 |
| Level 5 | 34.4 | 22.1 |
| Level 6 | 42.7 | 27.2 |
| Level 7 | 53.2 | 33.3 |
| Level 8 | 65.8 | 38.0 |
| Level 9 | 82.8 | 45.4 |
| Level 10 | 99.4 | 50.0 |
| Level 11 | 109.4 | 54.2 |
| Level 12 | 120.4 | 61.6 |

Beyond level 12 the run is extrapolated, not simulated: the model keeps playing one hour past
level 12 and takes the XP/min earned in that hour (every tier-one machine owned, no new
expansion, no tier-two machines, no rare crops) as a flat rate for all later levels.
| Milestone | Before | After | After lifetime XP |
|---|---:|---:|---:|
| Level 15 (extrapolated) | 162.7 | 90.1 | 17,321 |
| Level 20 (extrapolated) | 270.3 | 173.2 | 44,071 |
| Level 30 (extrapolated) | 640.6 | 542.3 | 162,431 |
| Level 40 (extrapolated) | 1258.2 | 1308.0 | 407,448 |
| Level 50 (extrapolated) | 2161.8 | 2626.2 | 829,520 |
| steady XP/min | 329.0 | 320.2 | |
| hand net coins/min | 459.2 | 269.2 |
| automation net coins/min | 1079.5 | 1661.7 |
| processors net coins/min | 1696.8 | 2197.5 |

Crafted machines, in the order the model builds them (median minutes from join; level then).
Raw is what one costs from an empty inventory, belts included; coal is the Smelter's fuel.
| Machine | Bench tier | Before bought | After crafted | Level then | Raw |
|---|---:|---:|---:|---:|---|
| ShippingBin | 1 | 9.9 | 2.0 | 1 | 3 wood |
| Smelter | 1 | 19.1 | 3.0 | 1 | 16 stone, 1 wood |
| BenchTier2 | 2 | - | 8.5 | 3 | 8 iron, 3 coal, 30 stone, 10 wood |
| Workbench | 2 | 19.6 | 11.5 | 3 | 8 iron, 2 copper, 4 coal, 2 wood |
| SeedPlanter | 2 | 27.8 | 14.5 | 3 | 10 iron, 4 coal, 2 wood |
| Sprinkler | 2 | 34.8 | 16.4 | 4 | 4 iron, 4 copper, 3 coal |
| BenchTier3 | 3 | - | 28.2 | 6 | 48 iron, 12 copper, 20 coal, 8 wood |
| Harvester | 3 | 43.1 | 33.6 | 7 | 17 iron, 4 copper, 7 coal, 5 wood |
| Mill | 2 | 53.2 | 35.7 | 7 | 7 iron, 3 coal, 20 stone, 3 wood |
| Juicer | 2 | 65.8 | 38.0 | 8 | 11 iron, 4 coal, 1 wood, 4 glass |
| CratePacker | 3 | 82.8 | 42.2 | 8 | 17 iron, 6 coal, 5 wood |
| Oven | 3 | 99.4 | 44.2 | 8 | 7 iron, 2 copper, 3 coal, 1 wood, 20 bricks |

To the first Harvester, from nothing: 95 iron, 22 copper, 41 coal, 46 stone, 31 wood.
Hand time gathering (walks, mining, chopping, waiting at rocks) before it: 13.8 of 33.6 min.

Mk II machines (Fabricator), parts only, not crafted in the run; supplied minutes are one
Smelter and one Assembler working serially from ore, excluding mining:
SeedPlanterTier2: {'SteelFrame': 3, 'Gear': 6}, 4.7 min supplied, 24 iron, 8 coal, 3 stone
SprinklerTier2: {'Circuit': 4, 'CopperWire': 6}, 5.0 min supplied, 8 iron, 14 copper, 8 coal
MillTier2: {'SteelFrame': 2, 'Gear': 8}, 4.7 min supplied, 24 iron, 8 coal, 2 stone
HarvesterTier2: {'SteelFrame': 3, 'Circuit': 6}, 7.9 min supplied, 24 iron, 12 copper, 12 coal, 3 stone
First-harvest seed losses before / after: ['Strawberry'] / []
All valued recipes beat their immediate inputs, for every mutation.
