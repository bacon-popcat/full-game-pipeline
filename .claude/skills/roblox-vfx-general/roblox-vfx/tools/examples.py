"""Example textures and flipbooks drawn with vfxtex: a claw slash, a cel-shaded puff, heavy
mottled dust, a splinter burst, ground cracks, an impact star that bursts open, a four-point
glint, a crisp star, a fire burst and its burn-out. They show the pattern (draw like an artist,
make it lopsided, cut a hard edge, break it apart over the frames), not a house style: copy one
and change its shapes, counts and curves.

Run all of them (Blender's Python or any Python with numpy):
    python <skill>/tools/examples.py <output folder>
or draw one from Blender after importing this module: examples.draw("ClawSlash").

From Roqer's VFX skill (https://github.com/S4US/Roqer, roblox-animation-vfx references
vfx-textures.md and vfx-explosions.md), AGPL-3.0-or-later; see LICENSE.
"""
import os
import sys

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vfxtex  # noqa: E402

NOISE = vfxtex.tex_noise(256, scale=6, seed=1)

# Claw slash: a fat crescent stroke with a sharp tail that sweeps on, then thins and breaks off from the head.
CLAW = vfxtex.tex_curve([(-0.55, -0.45), (-0.6, 0.2), (-0.1, 0.62), (0.5, 0.45), (0.7, -0.05)])

def claw(t, size):
    x, y = vfxtex.tex_coords(size)
    wx, wy = vfxtex.tex_warp(x, y, amount=0.06, scale=3, seed=2)
    def width(u):                                           # fat near the head, tapering to a point
        return 0.62 * (1 - u) ** 0.8 * numpy.sin(numpy.clip(u * 5, 0, 1) * numpy.pi / 2) * (1 - t * 0.7)
    shape = vfxtex.tex_stroke(wx, wy, CLAW, width,
                             start=numpy.clip((t - 0.45) * 1.6, 0, 1), end=0.15 + 0.85 * vfxtex.tex_ease(t * 3))
    return vfxtex.tex_edge(shape, soft=0.006)

# Cel-shaded puff: a lumpy blob with a lit side and a shadow side, holes that grow until it splits.
def puff(t, size):
    x, y = vfxtex.tex_coords(size)
    wx, wy = vfxtex.tex_warp(x, y, amount=0.08, scale=4, seed=5, t=t * 0.3)
    radius = 0.22 + 0.38 * vfxtex.tex_ease(t * 2.2)
    body = vfxtex.tex_blob(wx, wy, radius=radius, lumps=9, roughness=0.75, seed=4)
    lit = vfxtex.tex_blob(wx + 0.1, wy - 0.1, radius=radius, lumps=9, roughness=0.75, seed=4)   # the same blob, offset toward the light
    holes = vfxtex.tex_sample(NOISE, x * 0.45 + 0.3, y * 0.45 + t * 0.2) - t * 1.25 + 0.62
    alpha = vfxtex.tex_edge(body, soft=0.006) * vfxtex.tex_edge(holes + body * 0.4, soft=0.01)
    return alpha, 0.5 + 0.5 * vfxtex.tex_edge(lit, 0.03, soft=0.006)   # two tones: shadow 0.5, lit 1

# Heavy dust, not cel: a rim broken by small billows, a mottled inside of light and dark, torn apart by ragged holes.
BILLOWS = vfxtex.tex_noise(256, scale=5, octaves=5, seed=7)
GRIT = vfxtex.tex_noise(256, scale=16, octaves=3, seed=9)

def dust(t, size):
    x, y = vfxtex.tex_coords(size)
    wx, wy = vfxtex.tex_warp(x, y, amount=0.1, scale=5, seed=3, t=t * 0.4)
    radius = 0.2 + 0.26 * vfxtex.tex_ease(t * 2) + 0.06 * t                     # keeps swelling after the burst
    body = vfxtex.tex_blob(wx, wy, radius=radius, lumps=11, roughness=0.8, seed=6)
    churn = vfxtex.tex_sample(BILLOWS, x * 0.7 + t * 0.3, y * 0.7 - t * 0.5)     # billows that roll as it grows
    edge = body + (vfxtex.tex_sample(GRIT, x + t * 0.2, y) - 0.5) * 0.28          # small billows and wisps break the rim
    holes = vfxtex.tex_sample(NOISE, x * 0.5 + 0.2, y * 0.5 + t * 0.3) - t * 1.4 + 0.55
    alpha = vfxtex.tex_edge(edge, soft=0.01) * vfxtex.tex_edge(holes + body * 0.3, soft=0.05)
    shade = 0.5 + (churn - 0.5) * 1.9 + 0.15 * numpy.clip(y / radius, -1, 1)      # strong light and dark, lighter on top
    return alpha, numpy.clip(shade, 0.12, 0.95)

# Splinter burst: uneven tapered strokes flung out at irregular angles and lengths, then erased from the centre.
RNG = numpy.random.default_rng(11)
SPLINTERS = [(RNG.uniform(0, 2 * numpy.pi), RNG.uniform(0.25, 0.85), RNG.uniform(0, 0.25), RNG.uniform(-0.15, 0.15), RNG.uniform(0.07, 0.16)) for _ in range(9)]

def splinters(t, size):
    x, y = vfxtex.tex_coords(size)
    field = numpy.full_like(x, -1.0)
    reach = vfxtex.tex_ease(t * 2.5)
    for angle, length, inner, bend, width in SPLINTERS:
        a = (numpy.cos(angle) * inner * reach, numpy.sin(angle) * inner * reach)
        b = (numpy.cos(angle) * length * reach, numpy.sin(angle) * length * reach)
        middle = ((a[0] + b[0]) / 2 - numpy.sin(angle) * bend, (a[1] + b[1]) / 2 + numpy.cos(angle) * bend)
        w = width * (1 - t)
        path = vfxtex.tex_curve([a, middle, b], 16)
        field = numpy.maximum(field, vfxtex.tex_stroke(x, y, path, [w * 0.4, w, 0.0], start=numpy.clip(t * 1.4 - 0.3, 0, 1)))
    return vfxtex.tex_edge(field, soft=0.005)


# Ground cracks: a few jagged strokes from the centre, each forking once, thick at the root and tapering out.
def cracks(size):
    x, y = vfxtex.tex_coords(size)
    rng = numpy.random.default_rng(4)
    field = numpy.full_like(x, -1.0)
    for i in range(6):
        angle = i / 6 * 2 * numpy.pi + rng.uniform(-0.4, 0.4)
        steps = numpy.linspace(0.04, rng.uniform(0.55, 0.92), 7)
        wander = numpy.cumsum(rng.uniform(-0.35, 0.35, 7)) * 0.25        # the crack drifts off its line
        points = numpy.stack([numpy.cos(angle + wander) * steps, numpy.sin(angle + wander) * steps], 1)
        root = rng.uniform(0.05, 0.08)
        field = numpy.maximum(field, vfxtex.tex_stroke(x, y, points, [root, root * 0.6, 0.0]))
        fork = points[rng.integers(2, 4)]                                 # one branch splits off part way
        turn = angle + rng.choice([-1, 1]) * rng.uniform(0.5, 0.9)
        tip = fork + numpy.array([numpy.cos(turn), numpy.sin(turn)]) * rng.uniform(0.15, 0.3)
        kink = (fork + tip) / 2 + rng.uniform(-0.04, 0.04, 2)
        field = numpy.maximum(field, vfxtex.tex_stroke(x, y, numpy.stack([fork, kink, tip]), [root * 0.5, 0.0]))
    return vfxtex.tex_edge(field, soft=0.004)


# Impact star: shards burst from a lumpy heart and their inner ends chase their tips, so the centre
# empties into a ring that is gone by about 75%. Each frame is jittered anew, so it thrashes.
RNG = numpy.random.default_rng(21)
SHARDS = [((i + RNG.uniform(-0.5, 0.5)) / 11 * 2 * numpy.pi, RNG.uniform(0.35, 1.0), RNG.uniform(0.05, 0.14)) for i in range(11)]   # uneven

def impact_star(t, size):
    x, y = vfxtex.tex_coords(size)
    flick = numpy.random.default_rng(int(t * 1000))                       # a different jitter every frame
    out = vfxtex.tex_ease(min(1.0, t * 2.2))                               # the shards fly out by about half way
    field = vfxtex.tex_blob(x, y, radius=0.3 * (1 - t * 3.5), lumps=7, roughness=0.6, seed=int(t * 1000))   # the heart, first frames only
    for angle, length, width in SHARDS:
        a = angle + flick.uniform(-0.08, 0.08)
        tip = 0.9 * length * (0.3 + 0.7 * out) * flick.uniform(0.9, 1.1)
        inner = tip * min(0.95, t * 1.9)                                  # the inner end chases the tip
        path = numpy.array([(numpy.cos(a) * r, numpy.sin(a) * r) for r in (inner, (inner + tip) / 2, tip)])
        w = width * max(0.0, 1 - t * 1.35) * flick.uniform(0.7, 1.3)   # gone by about 75%
        if w <= 0:
            continue
        field = numpy.maximum(field, vfxtex.tex_stroke(x, y, path, [w * 0.3, w, 0.0]))   # a shard: thin, fat, then a point
    return vfxtex.tex_edge(field, soft=0.006)


# Four-point glint: four equal straight arms, mirrored on both axes, that thin and fade toward
# their tips from one smooth hot core, with a faint halo.
def glint(size):
    x, y = vfxtex.tex_coords(size)
    r = numpy.hypot(x, y)
    def arm(along, across, length, width):
        fade = numpy.clip(1 - numpy.abs(along) / length, 0, 1)
        return numpy.exp(-(across / (width * fade + 1e-4)) ** 2) * fade ** 1.5
    rays = numpy.maximum(arm(y, x, 0.95, 0.035), arm(x, y, 0.95, 0.035))
    core = numpy.exp(-(r / 0.07) ** 2)
    halo = 0.3 * numpy.exp(-(r / 0.3) ** 2)
    return numpy.clip(rays + core + halo, 0, 1)

# Crisp four-point star: the same symmetry as a solid shape with smooth concave sides
# (|x|^p + |y|^p below 1; a lower p gives thinner points), cut with a hard edge.
def star(size):
    x, y = vfxtex.tex_coords(size)
    p = 0.4
    return vfxtex.tex_edge(0.9 - (numpy.abs(x) ** p + numpy.abs(y) ** p) ** (1 / p), soft=0.006)


NOISE = vfxtex.tex_noise(256, scale=6, seed=1)

# Fire burst: a lopsided body ringed with flickering tongues. Value: a hot heart (1) in a body
# (0.55) that chars (0.05) while edges glow (0.35).
RNG = numpy.random.default_rng(3)
TONGUES = [(RNG.uniform(-0.6, 0.6) + (numpy.pi / 2 if i % 3 else RNG.uniform(0, 2 * numpy.pi)),   # most lick upward
            RNG.uniform(0.15, 0.4), RNG.uniform(0.07, 0.13), RNG.choice([-1, 1])) for i in range(11)]
CHURN = vfxtex.tex_noise(256, scale=5, octaves=4, seed=8)
RAG = vfxtex.tex_noise(256, scale=12, octaves=3, seed=4)

def fire_burst(t, size):
    x, y = vfxtex.tex_coords(size)
    wx, wy = vfxtex.tex_warp(x, y, amount=0.1, scale=4, seed=2, t=t * 1.6)   # drifts fast: boils
    grow = vfxtex.tex_ease(t * 3)   # full size by a third
    radius = 0.16 + 0.22 * grow
    body = vfxtex.tex_blob(wx, wy, radius=radius, lumps=9, roughness=0.75, seed=5)
    for n, (angle, reach, width, curl) in enumerate(TONGUES):   # uneven tongues that flicker
        base = (numpy.cos(angle) * radius * 0.7, numpy.sin(angle) * radius * 0.7)
        lick = reach * grow * (0.7 + 0.3 * numpy.sin(t * 19 + n * 2.3))
        tip = (base[0] + numpy.cos(angle) * lick, base[1] + numpy.sin(angle) * lick + 0.05 * t)
        bend = ((base[0] + tip[0]) / 2 - numpy.sin(angle) * 0.06 * curl, (base[1] + tip[1]) / 2 + numpy.cos(angle) * 0.06 * curl)
        path = vfxtex.tex_curve([base, bend, tip], 16)
        body = numpy.maximum(body, vfxtex.tex_stroke(wx, wy, path, [width * (1 - 0.5 * t), 0.0]))
    body = body + (vfxtex.tex_sample(RAG, wx * 0.5 + t * 0.2, wy * 0.5 - t * 0.5) - 0.5) * 0.08   # ragged rim
    burn = vfxtex.tex_sample(CHURN, x * 0.6 + 0.3, y * 0.6 - t * 0.4) - max(0.0, t - 0.2) * 1.4 + 0.1 + body * 0.6   # holes from 20%
    cool = min(max((t - 0.2) / 0.4, 0.0), 1.0)   # hot to 20%, charred by 60%
    alpha = vfxtex.tex_edge(body, soft=0.008 + 0.03 * cool) * vfxtex.tex_edge(burn, soft=0.02 + 0.06 * cool)
    mottle = vfxtex.tex_sample(RAG, wx * 0.4 - t * 0.2, wy * 0.4 + t * 0.3) - 0.5
    rim = (1 - vfxtex.tex_edge(numpy.minimum(body, burn / 3), 0.035 + mottle * 0.06, soft=0.015)) * vfxtex.tex_edge(mottle, -0.1, soft=0.1)
    heat = vfxtex.tex_sample(CHURN, wx * 0.5 - t * 0.3, wy * 0.5 + t * 0.6) + body * 2.5 - 0.05 - t * 1.5   # shrinking heart
    core = (0.55 + mottle * 0.3) * (1 - 0.9 * cool)
    value = core + (0.7 - 0.35 * cool - core) * rim * cool   # edges glow, in places
    return alpha * (1 - 0.3 * cool * (1 - rim)), numpy.maximum(value, vfxtex.tex_edge(heat, 0.5, soft=0.06))

# Burn-out: charcoal (value about 0.15) with thin cracks (1). Under a warm Color at Brightness
# 2-3: charcoal with embers.
RIDGES = vfxtex.tex_noise(256, scale=7, octaves=4, seed=12)
MOTTLE = vfxtex.tex_noise(256, scale=8, octaves=4, seed=13)

def burn_out(t, size):
    x, y = vfxtex.tex_coords(size)
    wx, wy = vfxtex.tex_warp(x, y, amount=0.16, scale=4, seed=6, t=t * 2.2)   # churns as it rises
    body = vfxtex.tex_blob(wx, wy - 0.15 * t, radius=0.3 + 0.25 * vfxtex.tex_ease(t * 1.5), lumps=10, roughness=0.8, seed=7)   # swells and lifts
    holes = vfxtex.tex_sample(NOISE, x * 0.5 + 0.1, y * 0.5 + t * 0.6) - t * 1.4 + 0.45
    alpha = vfxtex.tex_edge(body, soft=0.04) * vfxtex.tex_edge(holes + body * 0.3, soft=0.08) * (0.9 - 0.4 * t)
    ridge = 1 - numpy.abs(vfxtex.tex_sample(RIDGES, wx * 0.5 + 0.5, wy * 0.5 + 0.5) * 2 - 1)   # wandering lines
    patches = vfxtex.tex_edge(vfxtex.tex_sample(MOTTLE, x * 0.25 + 0.4, y * 0.25), 0.5, soft=0.05)   # only in places
    crack = vfxtex.tex_edge(ridge, 0.95 + 0.03 * t, soft=0.01) * patches * vfxtex.tex_edge(body, 0.08, soft=0.04) * (1 - t) ** 1.5
    smoke = 0.1 + 0.12 * vfxtex.tex_sample(MOTTLE, wx * 0.5 + t * 0.1, wy * 0.5 - t * 0.2)
    return alpha, smoke + (1 - smoke) * crack

DRAWINGS = {
    "ClawSlash": lambda: vfxtex.draw_flipbook("ClawSlash", claw, grid=4, fps=30),
    "SmokePuff": lambda: vfxtex.draw_flipbook("SmokePuff", puff, grid=4, fps=16),
    "HeavyDust": lambda: vfxtex.draw_flipbook("HeavyDust", dust, grid=4, fps=16),
    "Splinters": lambda: vfxtex.draw_flipbook("Splinters", splinters, grid=4, fps=30),
    "GroundCracks": lambda: vfxtex.draw_texture("GroundCracks", cracks, size=1024),
    "ImpactStar": lambda: vfxtex.draw_flipbook("ImpactStar", impact_star, grid=4, fps=60),
    "Glint": lambda: vfxtex.draw_texture("Glint", glint, size=512),
    "CrispStar": lambda: vfxtex.draw_texture("CrispStar", star, size=1024),
    "FireBurst": lambda: vfxtex.draw_flipbook("FireBurst", fire_burst, grid=4, fps=30),
    "BurnOut": lambda: vfxtex.draw_flipbook("BurnOut", burn_out, grid=4, fps=16),
}


def draw(name):
    """Draw one example into vfxtex.OUTPUT_DIR and return its path."""
    return DRAWINGS[name]()


if __name__ == "__main__":
    if len(sys.argv) > 1:
        vfxtex.OUTPUT_DIR = sys.argv[1]
    for name in DRAWINGS:
        print(draw(name))
