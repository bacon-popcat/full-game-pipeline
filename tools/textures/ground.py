"""Draws the game's own dirt and grass textures into assets/textures, simple and soft, so the ground
never uses Roblox's Grass or Ground material look: `python tools/textures/ground.py`.

Every tile is TILE pixels square and seamless (anything crossing an edge is drawn again on the
other side), drawn at SUPER times the size and scaled down so the edges come out soft. Flat
colour with a few soft speckles: the light warm soil and meadow green of the rest of the game
(Map.GRASS, the SOIL of IslandsMachines/build/assets.py).

- Ground_Dirt.png: dirt, for Farmland, paths and the sides of the ground (Texture objects).
- Ground_GrassTop.png: grass seen from above, for the meadow (Texture objects).
- Ground_GrassAtlas.png, Ground_DirtAtlas.png: one image per cube mesh (Shared/World/GroundLook),
  three tiles side by side, each with a GUTTER of wrapped pixels round it so filtering never
  bleeds one tile into the next: the top, the four sides, the bottom. The Grass block's top is
  grass, its sides dirt with a band of grass hanging over the top edge, its bottom dirt. The
  Dirt block is dirt all round.
"""
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw

TILE = 256
SUPER = 4
GUTTER = 8
OUT = Path(__file__).resolve().parents[2] / "assets" / "textures"

DIRT = (164, 116, 70)
DIRT_DARK = (151, 105, 63)
DIRT_LIGHT = (178, 130, 82)
PEBBLE = (196, 160, 118)
GRASS = (142, 186, 112)
GRASS_DARK = (126, 170, 98)
GRASS_LIGHT = (162, 204, 128)
GRASS_EDGE = (116, 156, 88)


def canvas(color):
    return Image.new("RGB", (TILE * SUPER, TILE * SUPER), color)


def wrapped(draw, shape, box, fill):
    """Draws `shape` ("ellipse" or "polygon") at `box` and again shifted by a tile each way, so it
    crosses the edges seamlessly."""
    size = TILE * SUPER
    for dx in (-size, 0, size):
        for dy in (-size, 0, size):
            if shape == "ellipse":
                x0, y0, x1, y1 = box
                draw.ellipse((x0 + dx, y0 + dy, x1 + dx, y1 + dy), fill=fill)
            else:
                draw.polygon([(x + dx, y + dy) for x, y in box], fill=fill)


def speckles(draw, count, colors, radius, stretch=1.0, region=None):
    """Soft round (or, stretched, blade-like) flecks scattered over the tile or a band of it."""
    top, bottom = region or (0, TILE)
    for _ in range(count):
        x = random.uniform(0, TILE) * SUPER
        y = random.uniform(top, bottom) * SUPER
        r = random.uniform(*radius) * SUPER
        wrapped(draw, "ellipse", (x - r, y - r * stretch, x + r, y + r * stretch), random.choice(colors))


def done(image):
    return image.resize((TILE, TILE), Image.LANCZOS)


def dirt():
    image = canvas(DIRT)
    draw = ImageDraw.Draw(image)
    speckles(draw, 24, [DIRT_DARK], (5, 10))
    speckles(draw, 18, [DIRT_LIGHT], (4, 7))
    speckles(draw, 10, [PEBBLE], (1.6, 2.6))
    return done(image)


def grass_top():
    image = canvas(GRASS)
    draw = ImageDraw.Draw(image)
    speckles(draw, 26, [GRASS_DARK], (6, 12))
    speckles(draw, 70, [GRASS_LIGHT, GRASS_DARK], (1.2, 2.0), stretch=3.0)
    return done(image)


def grass_side():
    """Dirt with the grass growing over the top edge: a band about a quarter of the height whose
    lower edge rolls gently and hangs down in a few rounded tufts, with a darker rim under it."""
    image = canvas(DIRT)
    draw = ImageDraw.Draw(image)
    speckles(draw, 26, [DIRT_DARK], (5, 11), region=(80, TILE))
    speckles(draw, 20, [DIRT_LIGHT], (4, 8), region=(80, TILE))
    speckles(draw, 8, [PEBBLE], (1.6, 2.6), region=(90, TILE))
    phase = random.uniform(0, math.tau)
    tufts = [(random.uniform(0, TILE), random.uniform(14, 26), random.uniform(10, 16)) for _ in range(4)]

    def edge(x):
        y = 58 + 6 * math.sin(math.tau * x / TILE * 2 + phase) + 3 * math.sin(math.tau * x / TILE * 5)
        for at, drop, width in tufts:
            gap = min(abs(x - at), TILE - abs(x - at))
            if gap < width:
                y += drop * math.cos(gap / width * math.pi / 2) ** 2
        return y

    def band(offset, color):
        points = [(0, 0)]
        for step in range(TILE * 2 + 1):
            x = step / 2
            points.append((x * SUPER, (edge(x) + offset) * SUPER))
        points.append((TILE * SUPER, 0))
        draw.polygon(points, fill=color)

    band(4, GRASS_EDGE)
    band(0, GRASS)
    speckles(draw, 30, [GRASS_LIGHT, GRASS_DARK], (1.2, 2.0), stretch=3.0, region=(4, 50))
    return done(image)


def atlas(tiles):
    """The tiles side by side, each in a cell GUTTER pixels bigger all round, filled with the
    tile wrapped."""
    cell = TILE + GUTTER * 2
    sheet = Image.new("RGB", (cell * len(tiles), cell))
    for index, tile in enumerate(tiles):
        block = Image.new("RGB", (cell, cell))
        for dx in (-TILE, 0, TILE):
            for dy in (-TILE, 0, TILE):
                block.paste(tile, (GUTTER + dx, GUTTER + dy))
        sheet.paste(block, (index * cell, 0))
    return sheet


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    random.seed("Dirt")
    soil = dirt()
    random.seed("GrassTop")
    top = grass_top()
    random.seed("GrassSide")
    side = grass_side()
    soil.save(OUT / "Ground_Dirt.png")
    top.save(OUT / "Ground_GrassTop.png")
    side.save(OUT / "Ground_GrassSide.png")
    atlas([top, side, soil]).save(OUT / "Ground_GrassAtlas.png")
    atlas([soil, soil, soil]).save(OUT / "Ground_DirtAtlas.png")
    print("wrote", ", ".join(sorted(p.name for p in OUT.glob("Ground_*.png"))))


if __name__ == "__main__":
    main()
