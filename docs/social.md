# Social

`Shared/Social` owns the rules and numbers for what players do for each other: which harvests
the server hears about, liking a garden, gifting between players and the save's shape. `SocialService`
applies them; `LeaderboardService` keeps the hub's boards. Every number belongs in the shared
module; [retention.md](retention.md#social-phase-r6) gives the reasons.

## Rare-harvest notices

When a harvest carries Rainbow, or Golden on an Epic or better crop (`Social.isNews`),
SocialService sends a Rare notice ("Oscar harvested a Rainbow Pumpkin!") to every other loaded
player on the server. The harvester already has their own notice from GardenService. One
player's news goes out at most once every `NOTICE_COOLDOWN` seconds, so a mutation-heavy
factory cannot flood the server.

## Likes, at a garden's sign

Each garden's sign (PlotService's `PlotSign`) carries a `Visit` prompt, made once per garden by
SocialService and enabled while the garden is owned. Triggering it sends the visitor a
`VisitSync` with `via = "Sign"`, and the client opens `HUD.Visit` on it
(`UIController/VisitScreen`) showing the garden's likes and a Like button. The sign shows the
likes under the owner's name (`PlotService.setSignNote`).

A like is once per visitor per garden per UTC day, never one's own, and needs the visitor
within `Social.REACH` studs of the owner's sign. It adds one to the owner's `likes`, records
the owner's id in the visitor's `liked` for the day, repaints the sign and tells both players.

## Gifts, by walking up to a player

Gifting is between two players standing together, and only while both have the **Gifting**
setting On. The setting is `Shared/Settings`' `Gifting` ("On" by default, or "Off"), saved per
player by SettingsService and mirrored as a Player attribute every client can read
(`Social.gifting`). The Settings window's `Body.Gifting` row switches it
(`tools/hud/settings_hud.luau` authors the row).

`VisitScreen` hangs a `GiftPrompt` on every other player's character, on that client only, and
enables it while both attributes read On. Triggering it sends `Social("Meet", userId)`; the
server checks the two characters are within `Social.GIFT_REACH` studs and answers with a
`VisitSync` whose `via` is "Player", which opens the card for that player: what is held, Give 1
and Give as many as the day's cap allows. The prompt is a convenience; the server checks
everything again on `Social("Gift", userId, count)`.

A gift is one-way, of what the giver holds, never to oneself. Only crops (mutated ones too),
valued products and seeds can be given (`Social.giftWorth`): never coins, tools, machines, ores,
bars or parts. The checks, in order: the two players are together; the giver has Gifting on;
the receiver has it on; the giver is level `GIFT_LEVEL` or more; the count is a whole number of
at least one; the held item can be given; the receiver has taken fewer than `GIFTS_RECEIVED`
gifts today; the worth (sell value, or a seed's price, times the count) fits under what is left
of the giver's daily cap, `GIFT_SCALE * Economy.scale(level)`; and the receiver has room. Then
the items are taken from the hand and given without yielding, the counters move, both players
are told, `GardenEvents.Gifted` fires, and both profiles are saved at once through the saver
DataService registers (`SocialService.setSaver`, a `Profile:Save()` each).

The cap follows the giver's level so a fresh second account can pass on very little (300 coins
of goods a day at level 1, and nothing before level 5). A crash between the two saves can
leave one gift on both sides; the caps bound what that is worth.

## Requests and the card

`Social(action, userId, count?)` takes "Like", "Meet" or "Gift". The server needs both gardens
loaded and DataReady and a per-player cooldown, and moves each side's daily counters on to
today first. A well-formed request is answered with a new `VisitSync`; one naming a player who
is not here, oneself for a gift, or an unknown action, is ignored.

`HUD.Visit`: `Header.Title` is the garden's name (sign) or the player's (player). At a sign
`Body.Likes` and `Body.Like` show (Like, Liked today or Your garden). With a player
`Body.Held` says what is held and whether it can be given, `Body.GiftOne` gives one and
`Body.GiftAll` as many as the day's cap allows ("Give 24"), and they follow the hotbar while
the card is open. `Body.Note` says why something is closed (gifting off for one of you, level,
the receiver's gifts for today) or how much worth can still be given.
`tools/hud/visit_hud.luau` authors the card as a rose-coloured clone of the Welcome card; run
it after welcome_hud.

## Leaderboards

Three boards stand in the hub at (-72, 0, 0), west of the Orders Board: coins earned, crops
harvested (Progress stats) and garden likes. Each is an OrderedDataStore
(`Board_<id>_v1`); `LeaderboardService.record` writes a loaded garden's numbers whenever
DataService snapshots it (every autosave and on release), keeping the higher of the stored and
the new value, since a player's three save files share one row. The boards are read every
`REFRESH` seconds and show the top ten by display name. The store calls are pcalled and run on
their own threads; without API access the columns say the boards open when the game is live.
Studio uses its own stores (`_studio`), so playtests never write to the live boards. The board
is built from plain parts and a SurfaceGui until it has art.

## Saving

The profile's `social = { likes, likedDay, liked = {[ownerUserId] = true}, giftDay, given,
received }`. `likes` is lifetime; the rest are the day's counters, cleared when the UTC day
changes (`Social.roll`). `Social.sanitize` makes every number finite, whole and non-negative
and keeps only well-formed `liked` keys.

## Studio playtest

Played on 2026-11-10 with one player, which is all the Studio tools here can drive:

- (Before gifting moved from the sign to players, later the same day.) The garden's sign carried an enabled Visit prompt named for its owner; pressing the interact
  key at it opened the card titled with the garden's name, reading "0 likes", "Your garden"
  and "Visit another garden to like it or leave a gift.", with every button off.
- The held line followed the hotbar: "Hammer cannot be given.", then "Holding Blueberry x107".
- Requests against one's own garden (Like, Gift 1, Gift 2.5) were each refused with "This is
  your own garden."; a Like for a user id not on the server and an unknown action did nothing.
- The rules were checked directly: Golden Carrot is not news, Golden Pumpkin, any Rainbow and a
  Wet Golden Apple are; a Carrot counts 18, a Golden Carrot 360, a Strawberry Pie 250, a Grape
  seed 10,000, and a Hammer, an Iron Bar, a Harvester and a Gear cannot be given; the daily cap
  is 300 at level 1, 4,000 at level 5 and 80,000 at level 33.
- The leaderboards stood in the hub. Quitting to the save menu wrote the garden's coins earned
  and crops harvested to the Studio stores (read back directly), and the next refresh drew
  "1. yaoming 289,589" and "1. yaoming 4,301"; the likes column, with nothing above zero, read
  "No gardens yet." The slab and its text were enlarged after that session and not looked at
  again.

After gifting moved to players: the Settings window's Gifting row switched Off and back On,
the attribute following; no Gift prompt hangs on one's own character; a Meet and a Gift aimed
at oneself did nothing.

**Not verified, and needing two players** (Studio's Test tab, two clients): a like landing on
another garden, once a day, with the sign and both notices; the Gift prompt appearing on
another player only while both have Gifting on, and going when either turns it off; a gift
moving a stack, each refusal (too far apart, gifting off, level, the receiver's five gifts, the
giver's cap, no room, not holding that many), both saves, and the card's Give buttons; a rare-harvest notice reaching another player and its
cooldown. Also unverified: the boards with rows from more than one player, and the card on a
phone-sized screen and with a gamepad.
