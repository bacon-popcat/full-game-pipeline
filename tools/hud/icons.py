"""Draws the HUD's icon set and its two soft UI textures into assets/icons:
`python tools/hud/icons.py [Name ...]` (no names draws them all).

The icons are one family: soft, rounded, slightly chunky glyphs, white on transparent so an
ImageLabel's ImageColor3 gives each one its button's colour. Each is drawn as a mask at SUPER times
the size and scaled down so its edges come out smooth, then shaded: lighter at the top than the
bottom, a slightly darker rim just inside its edge, and a soft dark shadow under it (black stays
black under ImageColor3, so the shadow keeps reading on any tint). Details are cut out of the
filled shapes rather than drawn in a second colour, since one tint colours the whole image.

Coordinates are shares of the square (0 to 1, y down). The textures are not tinted glyphs: Glow is
a white radial falloff (ResearchSky tints it) and Vignette a black ring darkening toward the edges.

assets/icons/README.md lists each file's uploaded asset id; src/shared/Icons.luau holds the same
ids for the game. After redrawing one, upload it again (Studio MCP upload_image, from the repo
served on 127.0.0.1) and replace its id in both.
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SIZE = 128
SUPER = 4
S = SIZE * SUPER
OUT = Path(__file__).resolve().parents[2] / "assets" / "icons"

# Top and bottom grey of the fill, the rim's darkening, and the shadow's offset, blur and strength.
TOP, BOTTOM = 255, 196
RIM, RIM_WIDTH = 0.84, 0.022
SHADOW_DROP, SHADOW_BLUR, SHADOW_ALPHA = 0.03, 0.025, 0.45


def px(value):
    return value * S


class Glyph:
    """A mask being drawn: `fill` adds a shape, `cut` takes one away."""

    def __init__(self):
        self.mask = Image.new("L", (S, S), 0)
        self.draw = ImageDraw.Draw(self.mask)

    def _ink(self, cut):
        return 0 if cut else 255

    def circle(self, cx, cy, r, cut=False):
        self.draw.ellipse([px(cx - r), px(cy - r), px(cx + r), px(cy + r)], fill=self._ink(cut))

    def ring(self, cx, cy, r, width):
        self.circle(cx, cy, r)
        self.circle(cx, cy, r - width, cut=True)

    def rect(self, x0, y0, x1, y1, r=0.0, cut=False):
        self.draw.rounded_rectangle([px(x0), px(y0), px(x1), px(y1)], radius=px(r), fill=self._ink(cut))

    def polygon(self, points, cut=False):
        self.draw.polygon([(px(x), px(y)) for x, y in points], fill=self._ink(cut))

    def line(self, points, width, cut=False):
        """A thick stroke with round caps and joins."""
        ink = self._ink(cut)
        self.draw.line([(px(x), px(y)) for x, y in points], fill=ink, width=round(px(width)), joint="curve")
        for x, y in points:
            self.circle(x, y, width / 2, cut=cut)

    def turned_rect(self, cx, cy, w, h, r, degrees, cut=False):
        """A rounded rectangle centred at (cx, cy), turned `degrees` clockwise."""
        layer = Image.new("L", (S, S), 0)
        ImageDraw.Draw(layer).rounded_rectangle(
            [px(cx - w / 2), px(cy - h / 2), px(cx + w / 2), px(cy + h / 2)], radius=px(r), fill=255
        )
        layer = layer.rotate(-degrees, resample=Image.BICUBIC, center=(px(cx), px(cy)))
        if cut:
            self.mask = ImageChops.subtract(self.mask, layer)
        else:
            self.mask = ImageChops.lighter(self.mask, layer)
        self.draw = ImageDraw.Draw(self.mask)


def shade(mask):
    """The finished RGBA icon from a full-size mask."""
    gradient = Image.new("L", (1, S))
    for y in range(S):
        gradient.putpixel((0, y), round(TOP + (BOTTOM - TOP) * y / (S - 1)))
    gradient = gradient.resize((S, S))
    # the rim: what an eroded mask no longer covers, darkened
    inner = mask.filter(ImageFilter.MinFilter(max(3, round(px(RIM_WIDTH)) | 1)))
    rim = ImageChops.subtract(mask, inner)
    darker = gradient.point(lambda v: round(v * RIM))
    grey = Image.composite(darker, gradient, rim)
    glyph = Image.merge("RGBA", (grey, grey, grey, mask))
    shadow_mask = mask.filter(ImageFilter.GaussianBlur(px(SHADOW_BLUR)))
    shadow_mask = ImageChops.offset(shadow_mask, 0, round(px(SHADOW_DROP)))
    shadow_mask = shadow_mask.point(lambda v: round(v * SHADOW_ALPHA))
    black = Image.new("L", (S, S), 0)
    shadow = Image.merge("RGBA", (black, black, black, shadow_mask))
    out = Image.alpha_composite(shadow, glyph)
    return out.resize((SIZE, SIZE), Image.LANCZOS)


# ---------------------------------------------------------------------------- the glyphs


def shop(g):
    # an awning with a scalloped edge over a little shopfront with a door
    g.rect(0.12, 0.14, 0.88, 0.36, 0.06)
    for x in (0.215, 0.405, 0.595, 0.785):
        g.circle(x, 0.36, 0.095)
    g.rect(0.18, 0.5, 0.82, 0.88, 0.06)
    g.rect(0.41, 0.6, 0.59, 0.9, 0.04, cut=True)
    g.rect(0.25, 0.6, 0.35, 0.7, 0.025, cut=True)
    g.rect(0.65, 0.6, 0.75, 0.7, 0.025, cut=True)
    # the awning's stripes
    for x in (0.31, 0.5, 0.69):
        g.rect(x - 0.025, 0.14, x + 0.025, 0.3, 0.0, cut=True)


def coin(g):
    # two coins, the front one with a groove round its face and a sparkle struck in it
    g.circle(0.64, 0.38, 0.27)
    g.circle(0.42, 0.58, 0.39, cut=True)
    g.circle(0.42, 0.58, 0.33)
    g.circle(0.42, 0.58, 0.245, cut=True)
    g.circle(0.42, 0.58, 0.205)
    points = []
    for index in range(48):
        angle = index / 48 * math.tau
        points.append((0.42 + math.cos(angle) ** 3 * 0.13, 0.58 + math.sin(angle) ** 3 * 0.13))
    g.polygon(points, cut=True)


def flask(g):
    def body(inset, cut=False):
        g.rect(0.39 + inset, 0.12, 0.61 - inset, 0.48, 0.02, cut=cut)
        g.circle(0.5, 0.65, 0.27 - inset, cut=cut)
        g.polygon([(0.39 + inset, 0.4), (0.61 - inset, 0.4), (0.7 - inset, 0.5), (0.3 + inset, 0.5)], cut=cut)

    body(0.0)
    body(0.075, cut=True)
    # the liquid, filling the bulb below a level line, with a bubble left clear
    liquid = Glyph()
    liquid.circle(0.5, 0.65, 0.27 - 0.115)
    liquid.rect(0.0, 0.0, 1.0, 0.6, cut=True)
    g.mask = ImageChops.lighter(g.mask, liquid.mask)
    g.draw = ImageDraw.Draw(g.mask)
    g.circle(0.44, 0.71, 0.035, cut=True)
    g.circle(0.47, 0.42, 0.03)
    g.circle(0.54, 0.32, 0.022)
    g.rect(0.32, 0.08, 0.68, 0.16, 0.04)


def menu(g):
    for y in (0.27, 0.5, 0.73):
        g.rect(0.16, y - 0.065, 0.84, y + 0.065, 0.065)


def quests(g):
    # a clipboard with three ticked lines
    g.rect(0.19, 0.15, 0.81, 0.91, 0.09)
    g.rect(0.33, 0.07, 0.67, 0.23, 0.05)
    g.rect(0.44, 0.11, 0.56, 0.16, 0.02, cut=True)
    for y in (0.42, 0.59, 0.76):
        g.line([(0.29, y), (0.33, y + 0.035), (0.4, y - 0.04)], 0.045, cut=True)
        g.line([(0.49, y), (0.7, y)], 0.06, cut=True)


def hammer(g):
    g.line([(0.27, 0.8), (0.56, 0.46)], 0.12)
    g.turned_rect(0.61, 0.36, 0.56, 0.22, 0.06, 45)
    # a band round the head where the handle goes in
    g.turned_rect(0.61, 0.36, 0.035, 0.3, 0.0, 45, cut=True)


def book(g):
    # an open book: two pages sloping from the spine, lines cut across them
    g.polygon([(0.08, 0.24), (0.47, 0.3), (0.47, 0.86), (0.08, 0.8)])
    g.polygon([(0.53, 0.3), (0.92, 0.24), (0.92, 0.8), (0.53, 0.86)])
    g.line([(0.08, 0.24), (0.47, 0.3)], 0.06)
    g.line([(0.53, 0.3), (0.92, 0.24)], 0.06)
    g.line([(0.08, 0.8), (0.47, 0.86)], 0.06)
    g.line([(0.53, 0.86), (0.92, 0.8)], 0.06)
    for y in (0.44, 0.57, 0.7):
        g.line([(0.17, y), (0.39, y + 0.03)], 0.045, cut=True)
        g.line([(0.61, y + 0.03), (0.83, y)], 0.045, cut=True)


def star_points(cx, cy, outer, inner, count=5, turn=-90):
    points = []
    for index in range(count * 2):
        radius = outer if index % 2 == 0 else inner
        angle = math.radians(turn + index * 180 / count)
        points.append((cx + math.cos(angle) * radius, cy + math.sin(angle) * radius))
    return points


def medal(g):
    g.turned_rect(0.38, 0.24, 0.17, 0.42, 0.04, -22)
    g.turned_rect(0.62, 0.24, 0.17, 0.42, 0.04, 22)
    g.circle(0.5, 0.64, 0.33, cut=True)
    g.circle(0.5, 0.64, 0.28)
    g.polygon(star_points(0.5, 0.645, 0.16, 0.07), cut=True)


def chart(g):
    for x0, top in ((0.16, 0.58), (0.41, 0.38), (0.66, 0.16)):
        g.rect(x0, top, x0 + 0.18, 0.84, 0.05)
    g.rect(0.1, 0.84, 0.9, 0.92, 0.04)


def gear(g):
    for index in range(8):
        angle = index * 45
        rad = math.radians(angle)
        g.turned_rect(0.5 + math.sin(rad) * 0.33, 0.5 - math.cos(rad) * 0.33, 0.17, 0.2, 0.04, angle)
    g.circle(0.5, 0.5, 0.34)
    g.circle(0.5, 0.5, 0.13, cut=True)


def info(g):
    g.circle(0.5, 0.5, 0.42)
    g.circle(0.5, 0.3, 0.07, cut=True)
    g.rect(0.435, 0.43, 0.565, 0.76, 0.06, cut=True)


def check(g):
    g.line([(0.18, 0.53), (0.41, 0.75), (0.82, 0.3)], 0.16)


def cross(g):
    g.line([(0.24, 0.24), (0.76, 0.76)], 0.15)
    g.line([(0.76, 0.24), (0.24, 0.76)], 0.15)


def sparkle(g):
    # a four-point star with curved sides, and a small one beside it
    def star(cx, cy, r):
        points = []
        steps = 64
        for index in range(steps):
            angle = index / steps * math.tau
            # an astroid: points out along the axes, curving in between
            x = math.cos(angle) ** 3
            y = math.sin(angle) ** 3
            points.append((cx + x * r, cy + y * r))
        g.polygon(points)
        g.circle(cx, cy, r * 0.2)

    star(0.44, 0.56, 0.42)
    star(0.79, 0.21, 0.17)


def level(g):
    g.line([(0.24, 0.46), (0.5, 0.2), (0.76, 0.46)], 0.15)
    g.line([(0.5, 0.24), (0.5, 0.82)], 0.15)


def search(g):
    g.ring(0.42, 0.42, 0.27, 0.095)
    g.line([(0.62, 0.62), (0.82, 0.82)], 0.13)


ICONS = {
    "Shop": shop,
    "Coin": coin,
    "Flask": flask,
    "Menu": menu,
    "Quests": quests,
    "Hammer": hammer,
    "Book": book,
    "Medal": medal,
    "Chart": chart,
    "Gear": gear,
    "Info": info,
    "Check": check,
    "Cross": cross,
    "Sparkle": sparkle,
    "Level": level,
    "Search": search,
}


# ---------------------------------------------------------------------------- the textures


def glow():
    size = 256
    image = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    for y in range(size):
        for x in range(size):
            r = math.hypot((x + 0.5) / size * 2 - 1, (y + 0.5) / size * 2 - 1)
            alpha = max(0.0, 1 - r) ** 2.2
            image.putpixel((x, y), (255, 255, 255, round(alpha * 255)))
    return image


def vignette():
    size = 256
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for y in range(size):
        for x in range(size):
            r = math.hypot((x + 0.5) / size * 2 - 1, (y + 0.5) / size * 2 - 1) / math.sqrt(2)
            t = min(1.0, max(0.0, (r - 0.38) / 0.62))
            alpha = t * t * (3 - 2 * t) * 0.92
            image.putpixel((x, y), (0, 0, 0, round(alpha * 255)))
    return image


def ring():
    """A soft glowing ring, for pulses that spread out."""
    size = 256
    image = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    for y in range(size):
        for x in range(size):
            r = math.hypot((x + 0.5) / size * 2 - 1, (y + 0.5) / size * 2 - 1)
            alpha = math.exp(-(((r - 0.86) / 0.07) ** 2)) + 0.25 * math.exp(-(((r - 0.8) / 0.18) ** 2))
            image.putpixel((x, y), (255, 255, 255, round(min(1.0, alpha) * 255)))
    return image


def streak():
    """A shooting star: a bright head on the right, its tail fading out to the left."""
    width, height = 256, 32
    image = Image.new("RGBA", (width, height), (255, 255, 255, 0))
    for y in range(height):
        for x in range(width):
            t = (x + 0.5) / width
            v = ((y + 0.5) / height * 2 - 1) / (0.15 + 0.85 * t)
            alpha = t**2.5 * math.exp(-(v * 2.2) ** 2)
            head = math.exp(-(((t - 0.96) / 0.03) ** 2 + (v * 1.6) ** 2))
            image.putpixel((x, y), (255, 255, 255, round(min(1.0, alpha + head) * 255)))
    return image


def nebula():
    """A soft cloud: blurred overlapping blobs inside a round falloff, for slow drifting colour."""
    import random

    rng = random.Random(7)
    size = 256
    blobs = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(blobs)
    for _ in range(26):
        cx, cy = rng.uniform(0.2, 0.8) * size, rng.uniform(0.2, 0.8) * size
        rx, ry = rng.uniform(0.08, 0.22) * size, rng.uniform(0.06, 0.16) * size
        draw.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=rng.randint(60, 140))
    blobs = blobs.filter(ImageFilter.GaussianBlur(18))
    image = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    for y in range(size):
        for x in range(size):
            r = math.hypot((x + 0.5) / size * 2 - 1, (y + 0.5) / size * 2 - 1)
            falloff = max(0.0, 1 - r) ** 1.4
            image.putpixel((x, y), (255, 255, 255, round(min(255, blobs.getpixel((x, y)) * 2.2 * falloff))))
    return image


def spark():
    """A four-point twinkle with a soft glow round it, for bursts."""
    size = 64
    image = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    for y in range(size):
        for x in range(size):
            u, v = abs((x + 0.5) / size * 2 - 1), abs((y + 0.5) / size * 2 - 1)
            # inside an astroid |u|^(2/3) + |v|^(2/3) <= 1, softened at its edge
            astroid = u ** (2 / 3) + v ** (2 / 3)
            core = min(1.0, max(0.0, (1 - astroid) * 6))
            glowing = max(0.0, 1 - math.hypot(u, v)) ** 3 * 0.6
            image.putpixel((x, y), (255, 255, 255, round(min(1.0, core + glowing) * 255)))
    return image


TEXTURES = {
    "Glow": glow,
    "Vignette": vignette,
    "Ring": ring,
    "Streak": streak,
    "Nebula": nebula,
    "Spark": spark,
}


def main(names):
    OUT.mkdir(parents=True, exist_ok=True)
    for name, draw in ICONS.items():
        if names and name not in names:
            continue
        glyph = Glyph()
        draw(glyph)
        shade(glyph.mask).save(OUT / f"Icon_{name}.png")
        print(f"Icon_{name}.png")
    for name, make in TEXTURES.items():
        if names and name not in names:
            continue
        make().save(OUT / f"UI_{name}.png")
        print(f"UI_{name}.png")


if __name__ == "__main__":
    main(set(sys.argv[1:]))
