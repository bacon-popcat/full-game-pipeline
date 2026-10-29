---
name: economy-progression
description: >
  Game economy and progression: a currency service, XP and level curves, item values,
  selling, restocking shops, unlocks gated by level, and balance tables. Use when adding
  coins, gems, XP or levels, a shop, a sell point or seller block, prices, rewards, unlocks
  or leaderstats, or when tuning balance or reviewing an economy for exploits and dead ends.
---

# Economy and progression

This skill covers soft currency. For real-money purchases on Roblox, see
`roblox-skills:roblox-monetization`.

## The service

- **One service owns live balances** and exposes a small API: `get` (returns a copy), `add`,
  `trySpend` and `addXp`. Every mutator rejects negative, non-integer and non-finite amounts.
  An overspend fails without changing anything. A purchase is: if `trySpend` succeeds, give
  the item.
- **No client message can set a balance.** A client asks to buy or sell something; the
  server prices it, checks stock and the inventory, takes the money, then gives the item.
- **Work out the level from XP; never save it.** Save lifetime XP and compute the level from
  a curve (for example level n costs `round(100 * n^1.5)` more). Then the two can never
  disagree, and retuning the curve moves everyone consistently.
- **Show balances in two places:** leaderstats (on Roblox) for the player list, and a sync
  message (`{coins, xp, level}`) sent on load and on every change, for the HUD.
- The balances live in the player's saved data (`player-saves-and-plots`). The economy
  service doesn't save; the data service hands it state and reads snapshots back.

## Content

- **Value belongs to content** (each item's `value`, each seed's price). The price of a
  variant is the base value times the variant's multiplier.
- **XP comes from the core loop:** harvesting (scaled by rarity), selling (for example 1 XP
  per 10 coins), crafting. Never give XP for anything that can be repeated for free.
- **Unlocks are gated by level.** Higher tiers also cost crafted parts, so a second
  progression feeds the first.
- **Restocking shops:** one restock clock per server, but each player's stock is rolled
  separately (per rarity band, with a chance for each band). Save the stock together with the
  restock time it belongs to, so rejoining can't reroll it. Show a countdown to the next
  restock.
- **Selling:** a sell point (sell what's in hand, or sell all of a category) and, for
  automation, a seller block that pays its owner.

## Balance

Make a table before choosing numbers: unlock level, cost, income per minute, payback time,
and time to reach that level. Aim for:

- a first reward within a minute, and a first upgrade within the first session;
- payback times that shrink as tiers rise, so upgrading always feels like progress;
- no early wall that only waiting can pass;
- rare outcomes that feel great but aren't needed to progress.

Mark numbers that are first guesses, and tune them during polish. The numbers live in the
content tables; the reasoning lives in the design doc.

## Exploit review

- **Buy then sell:** an item's buy price must be higher than any sell price for the same id.
- **Loops:** no crafting or processing chain may pay out more than its inputs and time are
  worth, unless that's intended.
- **Yields:** don't yield between a balance or stock check and the spend.
- **Ownership:** sellers pay their owner, drops keep their owner, and other players can't
  absorb them.
- **Bad saves:** a saved balance that isn't a valid integer fails the load and leaves the
  stored profile untouched.
