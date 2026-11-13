# Icons

The HUD's image icons and the soft textures its motion uses, drawn by `python tools/hud/icons.py
[Name ...]` with Pillow (supersampled 4x, then scaled down). The glyphs are one family: soft,
rounded, slightly chunky white shapes on transparent, lighter at the top with a darker rim and a
soft shadow, so an ImageLabel's `ImageColor3` gives each its button's colour. Details are cut out
of the shapes rather than drawn in a second colour.

Each file was uploaded as an image asset through the Studio MCP (`upload_image`, from the repo
served on `127.0.0.1:34998`). `src/shared/Icons.luau` owns the ids the game uses; to swap one,
redraw it, upload the new file and replace its id there and here.
`tools/hud/polish_hud.luau` puts the glyphs on the authored HUD.

## Glyphs (128 px)

| Name | File | Asset id | Used for |
|---|---|---|---|
| Shop | Icon_Shop.png | 127767520251085 | SideButtons.Shop |
| Coin | Icon_Coin.png | 133837907702735 | SideButtons.Sell; Reward notices |
| Flask | Icon_Flask.png | 86195398839667 | SideButtons.Research (and the Research hub, which clones it) |
| Menu | Icon_Menu.png | 88868341984519 | SideButtons.Menu |
| Quests | Icon_Quests.png | 85555061479373 | SideButtons.Quests; Quest notices |
| Hammer | Icon_Hammer.png | 81099156450387 | SideButtons.Crafting |
| Book | Icon_Book.png | 108461104617235 | Menu: Index |
| Medal | Icon_Medal.png | 101592650420845 | Menu: Achievements; Achievement notices |
| Chart | Icon_Chart.png | 116465044425811 | Menu: Stats |
| Gear | Icon_Gear.png | 129767158874012 | Menu: Settings |
| Info | Icon_Info.png | 114281201578067 | Info notices |
| Check | Icon_Check.png | 114442165606293 | Success notices |
| Cross | Icon_Cross.png | 96146042420376 | every window's close button, the search boxes' clear buttons; Error notices |
| Sparkle | Icon_Sparkle.png | 134493256912200 | Rare and Stock notices |
| Level | Icon_Level.png | 82265484384417 | Level notices |
| Search | Icon_Search.png | 140388053023208 | the Backpack and Crafting search boxes |

The Menu's Robux row keeps Roblox's own Robux mark.

## Textures

| Name | File | Asset id | Used for |
|---|---|---|---|
| Glow | UI_Glow.png | 72829196661123 | the Research sky's tinted glow; its motes |
| Vignette | UI_Vignette.png | 78344255927008 | the Research sky's darkened corners |
| Ring | UI_Ring.png | 134383753463972 | the pulses spreading from the Research hub |
| Streak | UI_Streak.png | 110304708655123 | the Research sky's shooting stars |
| Nebula | UI_Nebula.png | 84022196244617 | the Research sky's drifting clouds |
| Spark | UI_Spark.png | 91088343461209 | Flair's bursts; the glint on a window's divider |
