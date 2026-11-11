"""Garden progression model. Run from the repo root: python tools/balance/model.py

Standard library only; --capture-before writes the immutable pre-polish input fixture.
--runs N samples N reproducible seed-shop rolls; --plain disables mutation EV;
--miners N is how many players are mining the quarry at once, each taking an equal share;
--quarry-share S (0-1] scales this player's share of it further (1 = an equal share);
--build-share B (0-1) is the share of hand time gathering trips may take from farming.
Current numbers are read from the Luau owners, not copied into this script. before.json
is historical evidence, not runtime content. Results are estimates, not Studio timings.

Two paths, chosen by the content. before.json still has the coin Machine Shop: machines
are bought at their unlock level (the original policy, kept for comparison). The current
content has no Machine Shop: every machine is crafted in the Crafting window (Shared/
Crafting) from wood, quarry stone and ore, bars from a Smelter and parts from the Assembler,
behind four crafting tiers upgraded with materials at levels 3, 6 and 9.

Shared policy: 2 s per hand action, Sell All roughly once a minute, seeds bought one per
click, no Rare+ seeds. Stock rolls use every rarity's actual bands and 300 s restocks; a
fresh window begins at join (conservative). After the Harvester, one 20-cell patch (12
Wheat, 8 Strawberry) is tended automatically and hand harvesting stops; one Sprinkler and
one Harvester cover it, and the Seed Planter fills soil from bought seeds. One Mill, Juicer,
Crate Packer and Oven, actual recipe times, same-variant fractional EV inventories, one
60-item/min Shipping Bin. Mutations roll independently and stack; they are expected
fractional yields, never sampled jackpots. Weather growth is omitted; mutation EV uses clear
weather for the first 10 min, then long-run event weights.

Before path: 50 coins and the old starter seeds, a 96-cell farm already tilled, 20 s
round trips to the hub for selling and shopping, one of each tier-one machine bought at
unlock (two 25-coin belts per farm/processing machine).

Crafted path: the current starter kit (50 coins, no seeds, all grass), so every planted
cell is tilled by hand first (one action). Selling and seed buying work from anywhere (one
action, no trip). The player hand-farms up to 8 Carrot, 12 Wheat and 24 Strawberry cells
and crafts machines in the order of CRAFT_ORDER, working toward one target at a time:
- Quick workshop actions come first: the craft itself, bench crafts (planks, frames, belts),
  loading the Smelter (ore and the coal it burns) and the Assembler (gears, wire, circuits,
  steel frames), buying Glass and Bricks, starting a recipe's research. Gathering trips for
  what is still short then take up to build-share of hand time (half by default); farming
  (sell, buy seeds, till and plant, harvest) has the rest, and either uses time the other
  cannot. Hand farming this many cells would otherwise fill every second.
- Gathering: the Axe is bought first (Gear Shop). Wood comes from the forest (a 20 s round
  trip, then 2 s chops 3 s apart, a random species' wood each). Stone, Coal, Iron and Copper
  Ore come from the hub quarry (a 20 s round trip, 2 s mines 1 s apart), whose rocks respawn
  on their own timers: divided by the miners for `crowd` rocks (World.respawnAfter), then
  stretched by miners / quarry-share for the rocks the other players take. With no
  needed rock up within 10 s the player goes home. Stone and planks bought from the Gear Shop,
  digging the plot's own stone, research yield bonuses and the Rock Drill are not used.
- Belts: 4 for the Harvester line, 2 per processor. Machines and bars arrive in the
  inventory with no placing or collecting time beyond the loading actions.
- Bench tiers wait for their level; materials for them are gathered ahead of it.

Levels 13-50 are extrapolated, not simulated. After level 12 the run plays one more
hour; the XP/min earned in that hour (every tier-one machine owned, no new expansion, no
tier-two machines, no rare crops) is held flat, so a level's time is the lifetime XP it
needs divided by that rate. Real players keep adding soil, Mk II machines and rare crops.

The mid-game products (Products.luau `chained`) are read and audited but not simulated:
late_game prints their values, what a Harvester Mk II patch of each crop earns raw and through
its best product, and how long that takes to pay for every coin sink.
"""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict, deque
from copy import deepcopy
from itertools import combinations
import json
import math
from pathlib import Path
import random
import re
import statistics

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
ACTION = 2
TRAVEL = 20
CELLS = 96
HORIZON = 12 * 60 * 60
STEADY_WINDOW = 60 * 60
MILESTONES = (15, 20, 30, 40, 50)
MUTATIONS = ("Wet", "Shocked", "Golden", "Rainbow")
# Plain, then every stacked set of mutations as a Mutations key ("Wet+Golden").
VARIANTS = ("Plain",) + tuple("+".join(names) for size in range(1, 5) for names in combinations(MUTATIONS, size))

# Crafted path. The order a player crafts machines in, the belts each needs, and gathering.
CRAFT_ORDER = ("ShippingBin", "Smelter", "BenchTier2", "Workbench", "SeedPlanter", "Sprinkler",
               "BenchTier3", "Harvester", "Mill", "Juicer", "CratePacker", "Oven")
BELTS = {"Harvester": 4, "Mill": 2, "Juicer": 2, "CratePacker": 2, "Oven": 2}
BENCH_ITEMS = ("WoodPlanks", "TimberFrame", "ConveyorBelt")
SMELTED = {"IronBar": "IronOre", "CopperBar": "CopperOre"}
QUARRY_ITEMS = ("Stone", "Coal", "IronOre", "CopperOre")
ROCK_STEP, TREE_STEP = 1, 3
ROCK_PATIENCE = 10
HAND_FARM = {"Carrot": 8, "Wheat": 12, "Strawberry": 24}


def source(path):
    return (ROOT / path).read_text(encoding="utf-8-sig")


def number(text, pattern):
    match = re.search(pattern, text, re.S)
    assert match, pattern
    return float(match[1])


def counts(text):
    return {key: int(value) for key, value in re.findall(r'(\w+)\s*=\s*(\d+)', text or "")}


def read_crafting(world):
    """The crafting recipes and tiers, the research they need, and the gathering nodes."""
    text = source("src/shared/Crafting.luau")
    recipes = {key: dict(count=int(count), inputs=counts(inputs), tier=int(tier), research=research or None, level=1)
               for key, count, inputs, tier, research
               in re.findall(r'define\("(\w+)", (\d+), \{([^}]*)\}, (\d+)(?:, "(\w+)")?\)', text)}
    block = re.search(r'Crafting\.TIERS = \{(.*?)\} :: \{ Tier \}', text, re.S)[1]
    tiers = [dict(name=name, level=int(level), inputs=counts(inputs))
             for name, level, inputs in re.findall(r'name = "([^"]+)",\s*level = (\d+),\s*inputs = \{([^}]*)\}', block)]
    assert len(tiers) == 4, tiers
    for index, tier in enumerate(tiers[1:], start=2):
        # Matches CraftingService's upgrade recipe ids.
        recipes[f"BenchTier{index}"] = dict(count=0, inputs=tier["inputs"], tier=index - 1, research=None,
                                            level=tier["level"])
    for key in CRAFT_ORDER:
        assert key in recipes, f"no crafting recipe for {key}"
    research = {key: dict(level=int(level), coins=int(coins), items=counts(items), seconds=int(seconds))
                for key, level, coins, items, seconds in re.findall(
                    r'id = "(\w+)",[^{]*?level = (\d+),\s*coins = (\d+),\s*items = \{([^}]*)\},\s*seconds = (\d+)',
                    source("src/shared/Research.luau"))}
    for recipe in recipes.values():
        assert recipe["research"] is None or recipe["research"] in research, recipe
    # `crowd` rocks come back sooner the more players are mining (World.respawnAfter).
    rocks = {key: dict(drops=counts(drops), respawn=int(respawn), crowd=bool(crowd))
             for key, drops, respawn, crowd in re.findall(
        r'(\w+) = \{\s*name = "[^"]+",\s*hint = "[^"]+",\s*tool = "Pickaxe",\s*drops = \{([^}]*)\},\s*respawn = (\d+)'
        r'(,\s*crowd = true)?', world)}
    if any(rock["crowd"] for rock in rocks.values()):
        assert re.search(r'return node\.respawn / math\.max\(1, miners\)', world), "World.respawnAfter changed"
    assert set(rocks) == {"StoneRock", "CoalRock", "IronRock", "CopperRock"}, rocks
    layout = source("src/shared/World/Layout.luau")
    return dict(crafting=recipes, tiers=tiers, research=research, rocks=rocks,
                rocks_each=int(number(layout, r'for row = 0, (\d+) do')) + 1,
                trees=[int(wood) for wood in re.findall(r'= tree\("[^"]+", (\d+)\)', world)])


def read_chains(products, crops, recipes):
    """The mid-game products (Products.luau `chained`): each is worth the plain crops inside it
    times CHAIN[depth], to two significant figures. Kept apart from `recipes`, which the
    simulated factory runs; the simulation builds none of these machines."""
    chain = [float(value) for value in re.search(r'local CHAIN = \{([^}]+)\}', products)[1].split(",")]
    chains = {}

    def crops_in(inputs):
        inside = Counter()
        for item, count in inputs.items():
            made = chains.get(item) or recipes.get(item)
            for crop, each in (crops_in(made["inputs"]) if made else {item: 1}).items():
                inside[crop] += each * count
        return inside

    def add(key, machine, inputs, depth, seconds):
        inside = crops_in(inputs)
        worth = sum(crops[crop]["value"] * count for crop, count in inside.items())
        value = worth * chain[depth - 1]
        step = 10 ** (math.floor(math.log10(value)) - 1)
        chains[key] = dict(machine=machine, inputs=inputs, depth=depth, time=seconds, crops=dict(inside),
                           worth=worth, value=math.floor(value / step + 0.5) * step)

    pattern = r'chained\(\s*"(\w+)",\s*"[^"]+",\s*"[^"]+",\s*"(\w+)",\s*\{([^}]+)\},\s*(\d),\s*(\d+),'
    explicit = re.findall(pattern, products)
    fruits = [fruit.strip(' "') for fruit in re.search(r'local JAM_FRUITS = \{([^}]+)', products)[1].split(",")]
    jam_fruit = int(number(products, r'JAM_FRUIT_COUNT = (\d+)'))
    # In the file's order, so each product's inputs are already known: the jams come after the
    # Kettle's sauce, the tarts after the Recipe Book I bakes.
    for key, machine, ingredients, depth, seconds in explicit:
        if key == "Pizza":
            for fruit in fruits:
                add(fruit + "Jam", "Kettle", {fruit + "Juice": 1, fruit: jam_fruit}, 2, number(products, r'JAM_TIME = (\d+)'))
        if key == "WatermelonSorbet":
            for fruit in fruits:
                add(fruit + "JamTart", "Oven", {"Flour": 1, fruit + "Jam": 1}, 3, number(products, r'TART_TIME = (\d+)'))
        add(key, machine, counts(ingredients), int(depth), int(seconds))
    assert len(chains) == len(explicit) + 2 * len(fruits) and len(explicit) == 8, len(chains)
    return chains


def read_content():
    world = source("src/shared/World/init.luau")
    crops = {}
    pattern = r'(\w+) = defineCrop\(\s*"[^"]+",\s*"(\w+)",\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*(nil|\d+)'
    for key, rarity, price, value, grow, amount, regrow in re.findall(pattern, world):
        crops[key] = dict(rarity=rarity, price=int(price), value=int(value), grow=int(grow),
                          yield_count=int(amount), regrow=None if regrow == "nil" else int(regrow))
    assert len(crops) == 12
    content = source("src/shared/Economy/Content.luau")
    rarities = {}
    for key, body in re.findall(r'\t(\w+) = \{ ([^\n]+) \}', content):
        rarities[key] = {field: number(body, rf'\b{field} = ([\d.]+)')
                         for field in ("xp", "min", "max", "chance")}
    shops = source("src/shared/Economy/Shops.luau")
    offers = {}
    for key, price, level, category, parts in re.findall(
        r'offer\("(\w+)", (\d+), (\d+), "(\w+)"(?:, \{ ([^}]+) \})?\)', shops
    ):
        offers[key] = dict(price=int(price), level=int(level), category=category, parts=counts(parts))
    blocks = source("src/shared/Factory/Blocks.luau")
    products = source("src/shared/Factory/Products.luau")
    recipes = {"Flour": dict(machine="Mill", value=number(products, r'value = (\d+)'),
                             inputs={"Wheat": 2}, time=number(products, r'time = ([\d.]+)'))}
    for fruit in re.search(r'local JUICE_FRUITS = \{([^}]+)', products)[1].split(","):
        fruit = fruit.strip(' "')
        recipes[fruit + "Juice"] = dict(machine="Juicer", inputs={fruit: int(number(products, r'JUICE_FRUIT_COUNT = (\d+)'))},
            value=math.floor(crops[fruit]["value"] * number(products, r'JUICE_MULTIPLIER = ([\d.]+)') + .5),
            time=number(products, r'machine = "Juicer".*?time = ([\d.]+)'))
    for fruit, value in counts(re.search(r'local PIES[^=]*= \{([^}]+)', products)[1]).items():
        recipes[fruit + "Pie"] = dict(machine="Oven", inputs={"Flour": 1, fruit: 2}, value=value,
                                     time=number(products, r'machine = "Oven".*?time = ([\d.]+)'))
    for crop, data in crops.items():
        recipes[crop + "Crate"] = dict(machine="CratePacker", inputs={crop: int(number(products, r'CRATE_SIZE = (\d+)'))},
            value=data["value"] * number(products, r'CRATE_MULTIPLIER = ([\d.]+)'),
            time=number(products, r'machine = "CratePacker".*?time = ([\d.]+)'))
    for key, ingredients, seconds in re.findall(r'part\(\s*"(\w+)",\s*"[^"]+",\s*"[^"]+",\s*\{([^}]+)\},\s*(\d+)', products):
        recipes[key] = dict(machine="Workbench", inputs=counts(ingredients), time=int(seconds), value=0)
    assert len([r for r in recipes.values() if r["machine"] == "Workbench"]) == 4
    chains = read_chains(products, crops, recipes)
    economy = source("src/shared/Economy/init.luau")
    data = source("src/server/services/DataService.luau")
    mutations = source("src/shared/World/Mutations.luau")
    rewards = [int(v) for v in re.findall(r'reward = (\d+)', source("src/shared/Onboarding.luau"))]
    config = dict(crops=crops, rarities=rarities, offers=offers, recipes=recipes, chains=chains,
        coefficient=number(economy, r'math.round\(([\d.]+) \* level'),
        exponent=number(economy, r'level \^ ([\d.]+)'),
        # Optional linear term; the pre-rework curve (before.json) has none.
        linear=float(m[1]) if (m := re.search(r'\+ ([\d.]+) \* level\)', economy)) else 0.0,
        starter_coins=number(data, r'local PROFILE_TEMPLATE.*?coins = (\d+)'),
        starter_seeds={key: int(value) for key, value in re.findall(r'itemId = "(\w+)Seeds", count = (\d+)', data)},
        restock=int(number(content, r'RESTOCK_SECONDS = (\d+)')),
        harvest_seconds=number(blocks, r'Harvester = harvester\(\d+, \d+, ([\d.]+)\)'),
        plant_seconds=number(blocks, r'SeedPlanter = planter\(\d+, \d+, ([\d.]+)\)'),
        growth_speed=number(blocks, r'Sprinkler = sprinkler\(\d+, ([\d.]+)'),
        wet=number(blocks, r'Sprinkler = sprinkler\(\d+, [\d.]+, ([\d.]+)'),
        smelt_seconds=number(blocks, r'recipe\(\{ IronOre = 1 \}, \{ IronBar = 1 \}, ([\d.]+)\)'),
        coal_seconds=number(blocks, r'Smelter = processor\(.*?\{ Coal = ([\d.]+) \}'),
        multipliers=stacked({key: int(value) for key, value in re.findall(r'(\w+) = \{ multiplier = (\d+)', mutations)}),
        rewards=rewards)
    if "ShippingBin" not in offers:
        config.update(read_crafting(world))
    return config


def stacked(single):
    """Every variant's multiplier: 1 plus each of its mutations' bonus over plain."""
    return {variant: 1 + sum(single[name] - 1 for name in variant.split("+") if name != "Plain") for variant in VARIANTS}


def parts_time(config, parts):
    raw = Counter()
    bench_seconds = 0

    def expand(item, amount):
        nonlocal bench_seconds
        recipe = config["recipes"].get(item)
        if recipe and recipe["machine"] == "Workbench":
            bench_seconds += recipe["time"] * amount
            for ingredient, count in recipe["inputs"].items():
                expand(ingredient, count * amount)
        else:
            raw[item] += amount

    for item, amount in parts.items():
        expand(item, amount)
    smelt = (raw["IronBar"] + raw["CopperBar"]) * config["smelt_seconds"]
    return dict(minutes=(smelt + bench_seconds) / 60, raw=dict(raw), coal=math.ceil(smelt / config["coal_seconds"]))


def target_inputs(config, key):
    """What crafting `key` takes, with the belts its line needs."""
    inputs = dict(config["crafting"][key]["inputs"])
    if BELTS.get(key):
        inputs["ConveyorBelt"] = inputs.get("ConveyorBelt", 0) + BELTS[key]
    return inputs


def raw_materials(config, inputs):
    """Gathered and bought materials behind `inputs`, from an empty inventory."""
    raw = Counter()
    bars = 0

    def take(item, amount):
        nonlocal bars
        if item in BENCH_ITEMS:
            recipe = config["crafting"][item]
            for ingredient, count in recipe["inputs"].items():
                take(ingredient, count * math.ceil(amount / recipe["count"]))
        elif item in SMELTED:
            bars += amount
            raw[SMELTED[item]] += amount
        elif config["recipes"].get(item, {}).get("machine") == "Workbench":
            for ingredient, count in config["recipes"][item]["inputs"].items():
                take(ingredient, count * amount)
        else:
            raw[item] += amount

    for item, amount in inputs.items():
        take(item, amount)
    raw["Coal"] += math.ceil(bars * config["smelt_seconds"] / config["coal_seconds"])
    return raw


class Model:
    def __init__(self, config, seed=0, plain=False, quarry_share=1.0, build_share=0.5, miners=1):
        self.c = config
        self.crafted = "crafting" in config
        self.rng = random.Random(seed)
        # Its own stream, so gathering never changes the seed-stock rolls.
        self.tree_rng = random.Random(seed + 1000)
        self.plain = plain
        self.coins = config["starter_coins"]
        self.xp = 0
        self.level = 1
        self.threshold = self.required(1)
        self.seeds = Counter(config["starter_seeds"])
        self.plants = []
        self.stock = {}
        self.owned = set()
        self.bought = {}
        self.afford = {}
        self.wallet_at_unlock = {}
        self.levels = {}
        self.hand = defaultdict(float)
        self.queue = defaultdict(float)
        self.jobs = {}
        self.hand_at = TRAVEL // 2
        self.harvest_at = 0
        self.plant_at = 0
        self.hopper = Counter()
        self.sell_at = 60
        self.bin_remainder = 0
        self.step = 0
        self.met = set()
        self.stats = defaultdict(lambda: [0, 0., 0.])
        self.time = 0
        # The crafted path's workshop, inventory of materials and whereabouts.
        self.tilled = 0 if self.crafted else CELLS
        self.trip = TRAVEL if not self.crafted else 0
        self.mat = Counter()
        self.tier = 1
        self.target = 0
        self.location = "home"
        self.smelter = deque()
        self.smelt_progress = 0
        self.smelter_coal = 0
        self.fuel = 0
        self.assembler = deque()
        self.assembly_progress = 0
        self.researched = set()
        self.research_job = None
        self.crafted_at = {}
        self.level_at = {}
        self.gathering = 0
        self.gathered = Counter()
        self.quarry_share = quarry_share
        self.miners = miners
        self.build_share = build_share
        self.spent = Counter()
        if self.crafted:
            self.rocks = {key: [0.] * config["rocks_each"] for key in config["rocks"]}

    def required(self, level):
        return math.floor(self.c["coefficient"] * level ** self.c["exponent"] + self.c.get("linear", 0) * level + .5)

    def event(self, name):
        self.met.add(name)
        # The till step was inserted at 2; the before fixture has the seven older steps.
        sequence = ("buy", "till", "plant", "harvest", "sell", "level", "bin", "place")
        if len(self.c["rewards"]) < len(sequence):
            sequence = tuple(step for step in sequence if step != "till")
        while self.step < len(sequence) and sequence[self.step] in self.met:
            self.coins += self.c["rewards"][self.step]
            self.step += 1

    def gain_xp(self, amount):
        self.xp += amount
        while self.xp >= self.threshold:
            self.level += 1
            self.levels[self.level] = self.time / 60
            self.threshold += self.required(self.level)
            self.event("level")
            for item, offer in self.c["offers"].items():
                if offer["level"] == self.level:
                    self.wallet_at_unlock[item] = self.coins

    def stage(self):
        if "Mill" in self.owned:
            return "processors"
        return "automation" if "Harvester" in self.owned else "hand"

    def sale(self, amount, stand):
        self.coins += amount
        self.stats[self.stage()][1] += amount
        if stand:
            self.gain_xp(math.floor(amount / 10))
            self.event("sell")
        else:
            self.bin_remainder += amount
            xp = math.floor(self.bin_remainder / 10)
            self.bin_remainder -= xp * 10
            self.gain_xp(xp)

    def distribution(self):
        if self.plain:
            return {"Plain": 1}
        wet = self.c["wet"] if "Sprinkler" in self.owned else 0
        golden, shocked = .01, 0
        if self.time >= 600:
            wet += .25 * (120 + 90) / (3 * 600)
            shocked = .05 * 90 / (3 * 600)
            golden += .04 * 60 / (3 * 600)
        chances = dict(Wet=wet, Shocked=shocked, Golden=golden, Rainbow=.001)
        odds = {}
        for variant in VARIANTS:
            names = set(variant.split("+")) - {"Plain"}
            odds[variant] = math.prod(chances[name] if name in names else 1 - chances[name] for name in MUTATIONS)
        return odds

    def price(self, item, variant):
        base = self.c["crops"].get(item) or self.c["recipes"][item]
        return base["value"] * self.c["multipliers"][variant]

    def harvest(self, plant, automatic):
        crop = self.c["crops"][plant[0]]
        target = self.queue if automatic else self.hand
        for variant, probability in self.distribution().items():
            target[plant[0], variant] += crop["yield_count"] * probability
        self.gain_xp(self.c["rarities"][crop["rarity"]]["xp"])
        self.event("harvest")
        if crop["regrow"] or automatic:
            plant[1] = crop["regrow"] or crop["grow"]
        else:
            self.plants.remove(plant)

    def desired(self):
        present = Counter(p[0] for p in self.plants)
        if self.crafted:
            goal = {"Wheat": 12, "Strawberry": 8} if "Harvester" in self.owned else HAND_FARM
        elif "ShippingBin" not in self.owned:
            goal = {"Strawberry": 1}
        else:
            goal = {"Wheat": 12, "Strawberry": 8 if "Harvester" in self.owned else 24}
        return {item: max(0, count - present[item] - self.seeds[item] - self.hopper[item]) for item, count in goal.items()}

    def own(self, item):
        self.owned.add(item)
        self.bought[item] = self.time / 60
        if item == "ShippingBin":
            self.event("bin")
            self.event("place")
        if item == "Harvester":
            # Extra soil is available for expansion, not assumed to be automated.
            present = Counter()
            for plant in self.plants:
                present[plant[0]] += 1
                plant[2] = present[plant[0]] <= {"Wheat": 12, "Strawberry": 8}.get(plant[0], 0)

    def buy_machine(self):
        order = ("ShippingBin", "SeedPlanter", "Sprinkler", "Harvester", "Mill", "Juicer", "CratePacker", "Oven", "Smelter", "Workbench", "StorageChest")
        for item in order:
            offer = self.c["offers"][item]
            if item in self.owned or offer["level"] > self.level:
                continue
            belts = 0 if item in ("Sprinkler", "Smelter", "Workbench", "StorageChest") else 2 * self.c["offers"]["ConveyorBelt"]["price"]
            if self.coins < offer["price"] + belts:
                continue
            self.coins -= offer["price"] + belts
            self.own(item)
            self.hand_at = self.time + TRAVEL + 4 * ACTION
            return True
        return False

    # Crafted path -------------------------------------------------------------------

    def current(self):
        return CRAFT_ORDER[self.target] if self.target < len(CRAFT_ORDER) else None

    def shortfall(self, inputs):
        """Every item still missing for `inputs`, counting what the workshop already has queued,
        and the bars still to smelt."""
        have = Counter(self.mat)
        for bar in self.smelter:
            have[bar] += 1
        for part, _ in self.assembler:
            have[part] += 1
        need = Counter()

        def take(item, amount):
            use = min(have[item], amount)
            have[item] -= use
            amount -= use
            if amount <= 0:
                return
            need[item] += amount
            if item in BENCH_ITEMS:
                recipe = self.c["crafting"][item]
                for ingredient, count in recipe["inputs"].items():
                    take(ingredient, count * math.ceil(amount / recipe["count"]))
            elif item in SMELTED:
                take(SMELTED[item], amount)
            elif self.c["recipes"].get(item, {}).get("machine") == "Workbench":
                for ingredient, count in self.c["recipes"][item]["inputs"].items():
                    take(ingredient, count * amount)

        for item, amount in inputs.items():
            take(item, amount)
        bars = need["IronBar"] + need["CopperBar"] + len(self.smelter)
        burn = math.ceil(max(0, bars * self.c["smelt_seconds"] - self.fuel) / self.c["coal_seconds"])
        need["Coal"] += max(0, burn - self.smelter_coal - self.mat["Coal"])
        return need

    def wanted(self):
        """The current target's inputs, with its research's items while that is not started."""
        key = self.current()
        inputs = target_inputs(self.c, key)
        research = self.c["crafting"][key]["research"]
        if research and research not in self.researched and not self.research_job:
            for item, count in self.c["research"][research]["items"].items():
                inputs[item] = inputs.get(item, 0) + count
        return inputs

    def workshop(self):
        if self.smelter:
            if self.fuel <= 0 and self.smelter_coal > 0:
                self.smelter_coal -= 1
                self.fuel += self.c["coal_seconds"]
            if self.fuel > 0:
                self.fuel -= 1
                self.smelt_progress += 1
                if self.smelt_progress >= self.c["smelt_seconds"]:
                    self.mat[self.smelter.popleft()] += 1
                    self.smelt_progress = 0
        if self.assembler:
            self.assembly_progress += 1
            part, seconds = self.assembler[0]
            if self.assembly_progress >= seconds:
                self.mat[part] += 1
                self.assembler.popleft()
                self.assembly_progress = 0
        if self.research_job and self.time >= self.research_job[1]:
            self.researched.add(self.research_job[0])
            self.research_job = None

    def try_craft(self):
        key = self.current()
        recipe = self.c["crafting"][key]
        inputs = target_inputs(self.c, key)
        if recipe["tier"] > self.tier or recipe["level"] > self.level:
            return False
        if recipe["research"] and recipe["research"] not in self.researched:
            return False
        if any(self.mat[item] < count for item, count in inputs.items()):
            return False
        for item, count in inputs.items():
            self.mat[item] -= count
        if key.startswith("BenchTier"):
            self.tier += 1
        else:
            self.own(key)
        self.crafted_at[key] = self.time / 60
        self.level_at[key] = self.level
        self.target += 1
        self.hand_at = self.time + ACTION
        return True

    def prepare(self):
        """One hand action toward the current target: research, shop, bench, Smelter or Assembler."""
        key = self.current()
        research = self.c["crafting"][key]["research"]
        if research and research not in self.researched and not self.research_job:
            project = self.c["research"][research]
            if (self.level >= project["level"] and self.coins >= project["coins"]
                    and all(self.mat[item] >= count for item, count in project["items"].items())):
                self.coins -= project["coins"]
                for item, count in project["items"].items():
                    self.mat[item] -= count
                self.research_job = (research, self.time + project["seconds"])
                self.hand_at = self.time + ACTION
                return True
        need = self.shortfall(self.wanted())
        for item in ("Glass", "Bricks"):
            price = self.c["offers"][item]["price"]
            if need[item] and self.coins >= price * need[item]:
                self.coins -= price * need[item]
                self.mat[item] += need[item]
                self.hand_at = self.time + ACTION
                return True
        for item in BENCH_ITEMS:
            recipe = self.c["crafting"][item]
            crafts = math.ceil(need[item] / recipe["count"])
            if crafts:
                crafts = min([crafts] + [self.mat[i] // n for i, n in recipe["inputs"].items()])
            if crafts > 0:
                for ingredient, count in recipe["inputs"].items():
                    self.mat[ingredient] -= count * crafts
                self.mat[item] += recipe["count"] * crafts
                self.hand_at = self.time + ACTION
                return True
        loaded = False
        for bar, ore in SMELTED.items():
            if self.mat[ore]:
                self.smelter.extend([bar] * self.mat[ore])
                self.mat[ore] = 0
                loaded = True
        burn = math.ceil(max(0, len(self.smelter) * self.c["smelt_seconds"] - self.fuel) / self.c["coal_seconds"])
        coal = min(self.mat["Coal"], max(0, burn - self.smelter_coal))
        if coal:
            self.mat["Coal"] -= coal
            self.smelter_coal += coal
            loaded = True
        if "Workbench" in self.owned:
            for part in ("Gear", "CopperWire", "SteelFrame", "Circuit"):
                recipe = self.c["recipes"][part]
                while need[part] > 0 and all(self.mat[i] >= n for i, n in recipe["inputs"].items()):
                    for ingredient, count in recipe["inputs"].items():
                        self.mat[ingredient] -= count
                    self.assembler.append((part, recipe["time"]))
                    need[part] -= 1
                    loaded = True
        if loaded:
            self.hand_at = self.time + ACTION
        return loaded

    def gather_need(self, need):
        if need["Wood"] > 0 and "Axe" in self.mat:
            return "forest"
        if any(need[item] > 0 for item in QUARRY_ITEMS):
            return "quarry"
        return None

    def gather(self, need):
        """One gathering action, or a walk out or home. False when there is nothing to gather."""
        if need["Wood"] > 0 and "Axe" not in self.mat:
            price = self.c["offers"]["Axe"]["price"]
            if self.coins < price:
                return False
            self.coins -= price
            self.mat["Axe"] = 1
            self.hand_at = self.time + ACTION
            return True
        place = self.gather_need(need)
        if place and self.location == "home":
            if place == "quarry" and self.next_rock(need)[1] > self.time + ROCK_PATIENCE:
                return False
            self.location = place
            self.hand_at = self.time + TRAVEL / 2
            self.gathering += TRAVEL / 2
            return True
        if place != self.location:
            if self.location != "home":
                self.go_home()
                return True
            return False
        if place == "forest":
            wood = self.tree_rng.choice(self.c["trees"])
            self.mat["Wood"] += wood
            self.gathered["Wood"] += wood
            self.hand_at = self.time + ACTION + TREE_STEP
            self.gathering += ACTION + TREE_STEP
            return True
        rock, ready = self.next_rock(need)
        if ready > self.time + ROCK_PATIENCE:
            self.go_home()
            return True
        if ready > self.time:
            self.hand_at = ready
            self.gathering += ready - self.time
            return True
        index = self.rocks[rock].index(ready)
        # The other miners take their rocks; a crowd rock's respawn is shared out between all.
        respawn = self.c["rocks"][rock]["respawn"] / (self.miners if self.c["rocks"][rock]["crowd"] else 1)
        self.rocks[rock][index] = self.time + respawn * self.miners / self.quarry_share
        for item, count in self.c["rocks"][rock]["drops"].items():
            self.mat[item] += count
            self.gathered[item] += count
        self.hand_at = self.time + ACTION + ROCK_STEP
        self.gathering += ACTION + ROCK_STEP
        return True

    def next_rock(self, need):
        """The soonest rock that drops something still needed, and when it is up."""
        best, best_score = (None, math.inf), math.inf
        for rock, data in self.c["rocks"].items():
            if any(need[item] > 0 for item in data["drops"]):
                ready = min(self.rocks[rock])
                # Prefer the rock whose main drop is needed over one giving only its stone.
                main = next(iter(data["drops"]))
                score = max(ready, self.time) + (0 if need[main] > 0 else ROCK_PATIENCE)
                if score < best_score:
                    best, best_score = (rock, ready), score
        return best

    def go_home(self):
        self.location = "home"
        self.hand_at = self.time + TRAVEL / 2
        self.gathering += TRAVEL / 2

    def farm_action(self):
        """Selling, seed buying, tilling, planting and hand harvesting, in that order."""
        if self.time >= self.sell_at and sum(self.hand.values()) > 0:
            self.sale(sum(count * self.price(item, variant) for (item, variant), count in self.hand.items()), True)
            self.hand.clear()
            self.hand_at = self.time + self.trip + ACTION
            self.sell_at = self.time + 60
            return True
        if not self.crafted and self.buy_machine():
            return True
        # Buy an initial carrot to perform onboarding without spending the whole wallet.
        wanted = {"Carrot": 1} if "buy" not in self.met else self.desired()
        for item, count in wanted.items():
            price = self.c["crops"][item]["price"]
            if count and self.stock[item] and self.coins >= price:
                self.stock[item] -= 1
                self.seeds[item] += 1
                self.coins -= price
                self.stats[self.stage()][2] += price
                self.hand_at = self.time + ACTION
                # Shopping while already at the hub is batched; one trip per stock window.
                if getattr(self, "shop_window", -1) != self.time // self.c["restock"]:
                    self.shop_window = self.time // self.c["restock"]
                    self.hand_at += self.trip
                self.event("buy")
                return True
        if len(self.plants) < CELLS:
            for item in ("Carrot", "Wheat", "Strawberry"):
                if self.seeds[item] > 0:
                    if "SeedPlanter" in self.owned:
                        amount = min(10, self.seeds[item])
                        self.hopper[item] += amount
                        self.seeds[item] -= amount
                        # Two actions allow loading and repositioning its 15-cell patch.
                        self.hand_at = self.time + 2 * ACTION
                        return True
                    if self.tilled <= len(self.plants):
                        self.tilled += 1
                        self.hand_at = self.time + ACTION
                        self.event("till")
                        return True
                    self.seeds[item] -= 1
                    self.plant(item)
                    self.hand_at = self.time + ACTION
                    self.event("plant")
                    return True
        # The planter plants only on Farmland, so its patch is tilled by hand ahead of it.
        if sum(self.hopper.values()) and self.tilled <= len(self.plants):
            self.tilled += 1
            self.hand_at = self.time + ACTION
            self.event("till")
            return True
        if "Harvester" not in self.owned:
            ripe = next((p for p in self.plants if p[1] <= 0), None)
            if ripe:
                self.harvest(ripe, False)
                self.hand_at = self.time + ACTION
                return True
        return False

    def act(self):
        started = self.time
        kind = self.choose()
        if kind:
            self.spent[kind] += self.hand_at - started

    def choose(self):
        """Does one hand action and says whether it was farming or building."""
        if not self.crafted:
            return "farm" if self.farm_action() else None
        key = self.current()
        need = self.shortfall(self.wanted()) if key else Counter()
        if self.location != "home":
            # Out gathering: keep at it while something is needed here, else walk home.
            if not self.gather(need):
                self.go_home()
            return "build"
        # Crafting and loading the workshop are a few seconds and always come first.
        if key and (self.try_craft() or self.prepare()):
            return "build"
        # Gathering trips take their share of hand time; farming has the rest.
        share = self.build_share
        behind = self.spent["build"] * (1 - share) <= self.spent["farm"] * share
        if key and behind and self.gather(need):
            return "build"
        if self.farm_action():
            return "farm"
        if key and self.gather(need):
            return "build"
        return None

    # ---------------------------------------------------------------------------------

    def process(self):
        for machine in ("Mill", "Oven", "Juicer", "CratePacker"):
            if machine not in self.owned:
                continue
            if machine in self.jobs:
                end, item, variant = self.jobs[machine]
                if self.time < end:
                    continue
                self.queue[item, variant] += 1
                del self.jobs[machine]
            for item, recipe in self.c["recipes"].items():
                if recipe["machine"] != machine:
                    continue
                # Reserve wheat for flour, and fruit for pies once the Oven is owned.
                if machine == "CratePacker" and item == "WheatCrate":
                    continue
                for variant in VARIANTS:
                    if machine == "Juicer" and "Oven" in self.owned and self.queue["Strawberry", variant] < 4:
                        continue
                    if machine == "CratePacker" and item == "StrawberryCrate" and self.queue["Strawberry", variant] < 14:
                        continue
                    if all(self.queue[ingredient, variant] + 1e-9 >= count for ingredient, count in recipe["inputs"].items()):
                        for ingredient, count in recipe["inputs"].items():
                            self.queue[ingredient, variant] -= count
                        self.jobs[machine] = (self.time + recipe["time"], item, variant)
                        break
                if machine in self.jobs:
                    break

    def retained(self, item):
        return ((item == "Wheat" and "Mill" in self.owned)
                or (item == "Strawberry" and "Juicer" in self.owned)
                or (item == "Flour" and "Oven" in self.owned))

    def tick(self):
        self.stats[self.stage()][0] += 1
        if self.time % self.c["restock"] == 0:
            for item, crop in self.c["crops"].items():
                band = self.c["rarities"][crop["rarity"]]
                self.stock[item] = self.rng.randint(int(band["min"]), int(band["max"])) if self.rng.random() < band["chance"] else 0
        speed = self.c["growth_speed"] if "Sprinkler" in self.owned else 1
        for plant in self.plants:
            plant[1] = max(0, plant[1] - (speed if plant[2] else 1))
        if self.time >= self.plant_at and len(self.plants) < min(CELLS, self.tilled):
            item = next((item for item, count in self.hopper.items() if count), None)
            if item:
                self.hopper[item] -= 1
                self.plant(item)
                self.plant_at = self.time + self.c["plant_seconds"]
        if "Harvester" in self.owned and self.time >= self.harvest_at:
            ripe = next((p for p in self.plants if p[2] and p[1] <= 0), None)
            if ripe:
                self.harvest(ripe, True)
                self.harvest_at = self.time + self.c["harvest_seconds"]
        self.process()
        if self.crafted:
            self.workshop()
        if "ShippingBin" in self.owned and ("Harvester" in self.owned or not self.crafted):
            left = 1.
            for (item, variant), count in list(self.queue.items()):
                if self.retained(item):
                    continue
                amount = min(left, count)
                if amount > 0:
                    self.queue[item, variant] -= amount
                    self.sale(amount * self.price(item, variant), False)
                    left -= amount
                if left <= 1e-9:
                    break
        for item, offer in self.c["offers"].items():
            if self.level >= offer["level"] and self.coins >= offer["price"]:
                self.afford.setdefault(item, self.time / 60)
        if self.time >= self.hand_at:
            self.act()

    def plant(self, item):
        covered = sum(p[2] and p[0] == item for p in self.plants) < {"Wheat": 12, "Strawberry": 8}.get(item, 0)
        self.plants.append([item, self.c["crops"][item]["grow"], covered])

    def run(self):
        end_at = None
        rates = {}
        gathering_to_harvester = None
        for self.time in range(HORIZON):
            self.tick()
            assert len(self.plants) <= CELLS and self.coins >= -1e-9
            assert all(count >= 0 for count in self.mat.values()), self.mat
            if gathering_to_harvester is None and "Harvester" in self.owned:
                gathering_to_harvester = (self.gathering / 60, self.time / 60)
            if self.level >= 12 and end_at is None:
                end_at = self.time + STEADY_WINDOW
                xp_at_12 = self.xp
                # Stage rates are reported up to level 12, before the steady-state hour.
                rates = {stage: (gross - seeds) * 60 / seconds for stage, (seconds, gross, seeds) in self.stats.items() if seconds}
            if end_at is not None and self.time >= end_at:
                break
        # Steady late-game XP rate: XP/min over the hour after level 12, with every
        # tier-one machine owned. Used only to extrapolate past the simulated levels.
        steady = (self.xp - xp_at_12) * 60 / STEADY_WINDOW if end_at is not None else None
        return dict(levels=self.levels, afford=self.afford, bought=self.bought, wallet_at_unlock=self.wallet_at_unlock,
                    xp_end=self.xp, minutes_end=self.time / 60, steady_xp=steady,
                    rates=rates, crafted=self.crafted_at, level_at=self.level_at,
                    gathering=gathering_to_harvester, gathered=dict(self.gathered))


def audit(config):
    values = {key: crop["value"] for key, crop in config["crops"].items()}
    values.update({key: recipe["value"] for key, recipe in config["recipes"].items()})
    losses = []
    for key, recipe in config["recipes"].items():
        if recipe["value"]:
            cost = sum(values[item] * count for item, count in recipe["inputs"].items())
            assert recipe["value"] > cost, (key, cost, recipe["value"])
            for multiplier in config["multipliers"].values():
                assert recipe["value"] * multiplier > cost * multiplier
    for key, product in config.get("chains", {}).items():
        cost = sum(values.get(item, config.get("chains", {}).get(item, {}).get("value", 0)) * count
                   for item, count in product["inputs"].items())
        assert product["value"] > cost, (key, cost, product["value"])
    for key, crop in config["crops"].items():
        # A hand harvest spends a single crop's seed, so one plain harvest must repay it whatever
        # its rarity. A multi crop keeps its plant; only the cheap ones must repay at the first fruit.
        once = crop["regrow"] is None or crop["rarity"] in ("Common", "Uncommon")
        if once and crop["value"] * crop["yield_count"] < crop["price"]:
            losses.append(key)
    return losses


def cell_bands(config):
    """Plain coins a minute from one cell on a Harvester (a single crop restarts free, a multi
    crop regrows), as (rarity, lowest, highest), common first."""
    rates = {}
    for crop in config["crops"].values():
        cycle = crop["regrow"] or crop["grow"]
        rates.setdefault(crop["rarity"], []).append(crop["value"] * crop["yield_count"] * 60 / cycle)
    order = sorted(rates, key=lambda rarity: config["rarities"][rarity]["xp"])
    return [(rarity, min(rates[rarity]), max(rates[rarity])) for rarity in order]


PATCH = 35


def late_game(config):
    """Prints what the mid-game chains pay, and how a late patch compares with every coin sink.
    Not a simulation: one Harvester Mk II patch of a crop, its other inputs grown elsewhere,
    as many machines as it takes, no mutations, weather or research."""
    crops, chains = config["crops"], config["chains"]
    print("\nMid-game products: value over the plain worth of the crops inside (1 machine x1.5, 2 x3, 3 x4.5).")
    print("| Product | Machine | Machines deep | Crops inside | Their worth | Value |")
    print("|---|---|---:|---|---:|---:|")
    for key, product in chains.items():
        inside = ", ".join(f"{count} {crop}" for crop, count in product["crops"].items())
        print(f"| {key} | {product['machine']} | {product['depth']} | {inside} | {product['worth']:,} | {product['value']:,} |")

    everything = dict(config["recipes"])
    everything.update(chains)

    def crops_in(key):
        product = everything[key]
        if "crops" in product:
            return product["crops"]
        inside = Counter()
        for item, count in product["inputs"].items():
            for crop, each in (crops_in(item) if item in everything else {item: 1}).items():
                inside[crop] += each * count
        return inside

    print(f"\nOne Harvester Mk II patch ({PATCH} cells) of a crop, plain coins a minute: sold raw, and as the")
    print("best product it is the main crop of (other inputs grown elsewhere, machines as needed).")
    print("| Crop | Rarity | Raw | Best product | Through it | Machines for it |")
    print("|---|---|---:|---|---:|---|")
    top = 0
    for name, crop in crops.items():
        per_minute = crop["yield_count"] * 60 / (crop["regrow"] or crop["grow"]) * PATCH
        raw = per_minute * crop["value"]
        best = (raw, "-", "")
        for key, product in everything.items():
            if not product.get("value"):
                continue
            inside = crops_in(key)
            worth = {each: count * crops[each]["value"] for each, count in inside.items() if each in crops}
            if name not in worth or max(worth, key=worth.get) != name:
                continue
            made = per_minute / inside[name]
            if made * product["value"] > best[0]:
                best = (made * product["value"], key, f"{made * product['time'] / 60:.1f} {product['machine']}")
        top = max(top, best[0])
        print(f"| {name} | {crop['rarity']} | {raw:,.0f} | {best[1]} | {best[0]:,.0f} | {best[2]} |")

    research = sum(int(coins) for coins in re.findall(r'\bcoins = (\d+)', source("src/shared/Research.luau")))
    plot = source("src/shared/Plot.luau")
    prices = [int(price) for price in re.search(r'local PRICES = \{([^}]+)\}', plot)[1].split(",")]
    across, deep = (int(v) for v in re.search(r'SECTIONS_X, SECTIONS_Z = (\d+), (\d+)', plot).groups())
    start = {key: int(value) for key, value in re.findall(r'(\w\d) = (\d+)', re.search(r'local START = \{([^}]+)\}', plot)[1])}
    sections = 0
    for x in range(across):
        for z in range(deep):
            ring = max(start["x0"] - x, x - start["x1"], start["z0"] - z, z - start["z1"], 0)
            sections += prices[ring - 1] if ring else 0
    sinks = research + sections
    print(f"\nEvery coin sink: research {research:,} + garden sections {sections:,} = {sinks:,} coins.")
    for name in ("Blueberry", "Apple", "Grape", "Starfruit"):
        crop = crops[name]
        raw = crop["yield_count"] * 60 / (crop["regrow"] or crop["grow"]) * PATCH * crop["value"]
        print(f"One raw {name} patch pays for all of it in {sinks / raw / 60:.1f} hours.")
    print(f"The best patch above ({top:,.0f} a minute) pays for all of it in {sinks / top / 60:.1f} hours.")


def scale(level):
    """Economy.scale: the coin scale orders and daily quests grow by, to two significant figures."""
    text = source("src/shared/Economy/init.luau")
    raw = number(text, r"local raw = (\d+) \* math\.max\(1, level\)") * level ** number(text, r"level\) \^ ([\d.]+)")
    step = 10 ** (math.floor(math.log10(raw)) - 1)
    return math.floor(raw / step + .5) * step


def orders(config, results):
    """Prints what an order and a day's quests are worth against a level, and how far orders can
    shorten the run. Not simulated: an order replaces the sale of the goods it takes, so it adds
    its XP over a sale's and its coin premium, and nothing else changes."""
    progress = source("src/shared/Progress.luau")
    per_xp = number(progress, r"ORDER_COINS_PER_XP = (\d+)")
    premium = number(progress, r"ORDER_PREMIUM = ([\d.]+)")
    quests = int(number(progress, r"QUEST_SLOTS = (\d+)"))
    quest_share = number(progress, r"Economy\.required\(level\) \* ([\d.]+)")
    sale_per_xp = 10
    assert "a sale gives 1 per 10" in progress, "Progress.luau no longer states the sale XP rate this audit assumes"
    model = Model(config)
    print("\nOrders and daily quests against a level (an order asks for Economy.scale coins of goods):")
    print("| Level | Order's goods | Order XP | Over selling them | Level costs | Order / level | Day's quests / level |")
    print("|---:|---:|---:|---:|---:|---:|---:|")
    for level in (5, 10, 15, 20, 30):
        goods, cost = scale(level), model.required(level)
        xp = goods // per_xp
        extra = xp - goods // sale_per_xp
        daily = quests * max(3, math.floor(cost * quest_share + .5))
        print(f"| {level} | {goods:,.0f} | {xp:,.0f} | +{extra:,.0f} | {cost:,} | {xp / cost:.0%} | {daily / cost:.0%} |")
        assert extra / cost <= .6, "One order must not add more than 60% of a level over selling its goods"
    # The most orders can do: every coin the steady hour sells goes through an order instead.
    steady = statistics.median(r["steady_xp"] for r in results)
    sold = statistics.median(r["rates"]["processors"] for r in results)
    gain = sold / sale_per_xp * (sale_per_xp / per_xp - 1)
    print(f"An order pays {premium:g}x its goods' coins and {sale_per_xp / per_xp:g}x their sale XP. In the steady hour the run nets "
          f"{sold:,.0f} coins a minute, so delivering all of it as orders adds at most {gain:,.0f} XP a minute "
          f"to {steady:,.0f} ({gain / steady:.0%}).")
    print("Minutes from join, with orders at that most from level 12 on (the first column is the table above):")
    print("| Milestone | No orders | Every sale an order |\n|---|---:|---:|")
    for level in MILESTONES[:3]:
        plain = statistics.median(reach_minutes(config, r, level) for r in results)
        fast = statistics.median(r["levels"][12] + (cumulative(config, level) - cumulative(config, 12))
                                 / (r["steady_xp"] + gain) for r in results)
        print(f"| Level {level} | {plain:.1f} | {fast:.1f} |")


def band_overlaps(config):
    bands = cell_bands(config)
    return [f"{low[0]} over {high[0]}" for low, high in zip(bands, bands[1:]) if low[2] > high[1]]


def median(results, group, key):
    values = [r[group][key] for r in results if key in r[group]]
    return statistics.median(values) if len(values) == len(results) else None


def fmt(value):
    return "unreached" if value is None else f"{value:.1f}"


def cumulative(config, level):
    """Lifetime XP needed to reach `level` under a config's curve."""
    model = Model(config)
    return sum(model.required(n) for n in range(1, level))


def reach_minutes(config, result, level):
    """Minutes to a level: simulated where the run got there, else extrapolated at the steady XP rate."""
    if level in result["levels"]:
        return result["levels"][level]
    if not result["steady_xp"]:
        return None
    return result["minutes_end"] + (cumulative(config, level) - result["xp_end"]) / result["steady_xp"]


def median_reach(config, results, level):
    values = [reach_minutes(config, r, level) for r in results]
    return None if None in values else statistics.median(values)


def describe(raw):
    names = (("IronOre", "iron"), ("CopperOre", "copper"), ("Coal", "coal"), ("Stone", "stone"), ("Wood", "wood"),
             ("Glass", "glass"), ("Bricks", "bricks"))
    return ", ".join(f"{raw[key]} {name}" for key, name in names if raw.get(key))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture-before", action="store_true")
    parser.add_argument("--runs", type=int, default=9)
    parser.add_argument("--plain", action="store_true")
    parser.add_argument("--quarry-share", type=float, default=1.0)
    parser.add_argument("--build-share", type=float, default=0.5)
    parser.add_argument("--miners", type=int, default=1)
    args = parser.parse_args()
    assert args.runs > 0 and 0 < args.quarry_share <= 1 and 0 < args.build_share < 1 and args.miners >= 1
    current = read_content()
    if args.capture_before:
        assert not (HERE / "before.json").exists(), "Never overwrite historical input"
        baseline = deepcopy(current)
        baseline["rewards"] = [0] * 7
        (HERE / "before.json").write_text(json.dumps(baseline, indent=2) + "\n", encoding="utf-8")
    before = json.loads((HERE / "before.json").read_text(encoding="utf-8"))
    # Baselines from before stacking hold single multipliers only.
    before["multipliers"] = stacked({key: value for key, value in before["multipliers"].items() if "+" not in key and key != "Plain"})
    print(f"Median of {args.runs} stock rolls; {'plain' if args.plain else 'mutation EV'}; "
          f"miners {args.miners}; quarry share {args.quarry_share:g}; build share {args.build_share:g}; minutes from join.")
    print("Before = before.json with the coin Machine Shop; After = current content, machines crafted.")
    results = [[Model(config, seed, args.plain, args.quarry_share, args.build_share, args.miners).run() for seed in range(args.runs)]
               for config in (before, current)]
    print("| Milestone | Before | After |\n|---|---:|---:|")
    for level in range(2, 13):
        print(f"| Level {level} | " + " | ".join(fmt(median(r, "levels", level)) for r in results) + " |")
    print("\nBeyond level 12 the run is extrapolated, not simulated: the model keeps playing one hour past")
    print("level 12 and takes the XP/min earned in that hour (every tier-one machine owned, no new")
    print("expansion, no tier-two machines, no rare crops) as a flat rate for all later levels.")
    print("| Milestone | Before | After | After lifetime XP |\n|---|---:|---:|---:|")
    for level in MILESTONES:
        print(f"| Level {level} (extrapolated) | " + " | ".join(fmt(median_reach(c, r, level)) for c, r in zip((before, current), results))
              + f" | {cumulative(current, level):,} |")
    print("| steady XP/min | " + " | ".join(fmt(statistics.median(x["steady_xp"] for x in r)) for r in results) + " | |")
    for stage in ("hand", "automation", "processors"):
        print(f"| {stage} net coins/min | " + " | ".join(fmt(median(r, "rates", stage)) for r in results) + " |")

    after = results[1]
    print("\nCrafted machines, in the order the model builds them (median minutes from join; level then).")
    print("Raw is what one costs from an empty inventory, belts included; coal is the Smelter's fuel.")
    print("| Machine | Bench tier | Before bought | After crafted | Level then | Raw |\n|---|---:|---:|---:|---:|---|")
    for key in CRAFT_ORDER:
        recipe = current["crafting"][key]
        old = fmt(median(results[0], "bought", key)) if key in before["offers"] else "-"
        level = statistics.median(r["level_at"][key] for r in after) if all(key in r["level_at"] for r in after) else None
        print(f"| {key} | {recipe['tier'] + (1 if key.startswith('BenchTier') else 0)} | {old} | "
              f"{fmt(median(after, 'crafted', key))} | {'-' if level is None else int(level)} | "
              f"{describe(raw_materials(current, target_inputs(current, key)))} |")
    total = Counter()
    for key in CRAFT_ORDER[:CRAFT_ORDER.index("Harvester") + 1]:
        total += raw_materials(current, target_inputs(current, key))
    print(f"\nTo the first Harvester, from nothing: {describe(total)}.")
    gathering = [r["gathering"] for r in after if r["gathering"]]
    if len(gathering) == len(after):
        spent = statistics.median(g[0] for g in gathering)
        reached = statistics.median(g[1] for g in gathering)
        print(f"Hand time gathering (walks, mining, chopping, waiting at rocks) before it: {spent:.1f} of {reached:.1f} min.")

    print("\nMk II machines (Fabricator), parts only, not crafted in the run; supplied minutes are one")
    print("Smelter and one Assembler working serially from ore, excluding mining:")
    for key, recipe in current["crafting"].items():
        if key.endswith("Tier2") and recipe["count"] == 1 and not key.startswith("Conveyor"):
            parts = {item: count for item, count in recipe["inputs"].items() if item in current["recipes"]}
            timing = parts_time(current, parts)
            print(f"{key}: {parts}, {timing['minutes']:.1f} min supplied, {describe(raw_materials(current, parts))}")
            assert 4 <= timing["minutes"] <= 10, "Mk II parts are 4-10 min of supplied crafting (economy.md)"
    print("First-harvest seed losses before / after:", audit(before), "/", audit(current))
    assert not audit(current), "A single crop's seed, and any Common/Uncommon seed, must repay in one plain harvest"
    print("Coins a minute from one cell on a Harvester, plain, by rarity (lowest-highest):",
          ", ".join(f"{rarity} {low:.0f}-{high:.0f}" for rarity, low, high in cell_bands(current)))
    print("Rarities out-earned by the one below, before / after:", band_overlaps(before), "/", band_overlaps(current))
    assert not band_overlaps(current), "Each rarity's crops must earn at least the rarity below's best per cell"
    print("All valued recipes beat their immediate inputs, for every mutation.")
    late_game(current)
    orders(current, after)


if __name__ == "__main__":
    main()
