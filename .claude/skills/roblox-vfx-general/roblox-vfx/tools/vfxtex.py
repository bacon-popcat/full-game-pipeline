"""Drawing VFX textures and particle flipbooks with numpy.

Most Roblox VFX textures are drawn 2D shapes: a shape built from coordinates, broken up by
noise, cut with a hard edge, and eaten away over the frames. These helpers draw them and
write PNGs, with no dependency beyond numpy. Run them in Blender's Python (it ships numpy;
use the Blender MCP's execute_blender_code) or any Python that has numpy:

    import sys; sys.path.insert(0, r"<path to the roblox-vfx skill>/tools")
    import importlib, vfxtex; importlib.reload(vfxtex)
    vfxtex.OUTPUT_DIR = r"<your project>/assets/textures"
    vfxtex.draw_flipbook("ClawSlash", claw, grid=4, fps=30)

Then check each sheet with `node <skill>/tools/flipbook.mjs <name>.flipbook.png` and look at
`<name>.preview.png` (the drawing over a dark ground, as it reads when it glows).

Images are float arrays, row 0 at the top. tex_coords runs -1..1 with x to the right and y up.
Shapes (tex_stroke, tex_blob) are fields: positive inside, negative outside. Combine them with
numpy.maximum (union) and numpy.minimum (intersection; subtract one with numpy.minimum(a, -b)),
then cut them with tex_edge.

Ported from Roqer's Blender helpers (https://github.com/S4US/Roqer,
apps/desktop/runtime/blender-worker.ts), AGPL-3.0-or-later; see LICENSE. Changes: a plain
module (no bpy), an OUTPUT_DIR setting, and preview images written beside each texture.
"""
import json
import os
import struct
import zlib

import numpy

OUTPUT_DIR = os.getcwd()

_FLIPBOOK_SIDE = 1024
_FLIPBOOK_GRIDS = (2, 4, 8)
_PREVIEW_GROUND = 0.12


def _write_png(path, rgba):
    """Write rows of 8-bit RGBA, top row first, as a PNG."""
    height, width = rgba.shape[0], rgba.shape[1]

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    rows = numpy.zeros((height, width * 4 + 1), dtype=numpy.uint8)
    rows[:, 1:] = rgba.reshape(height, width * 4)
    with open(path, "wb") as handle:
        handle.write(b"\x89PNG\r\n\x1a\n")
        handle.write(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)))
        handle.write(chunk(b"IDAT", zlib.compress(rows.tobytes(), 9)))
        handle.write(chunk(b"IEND", b""))


def _write_preview(path, rgba, half=False):
    """The texture over a dark ground, as a white texture reads when it glows in the game."""
    image = rgba.astype(numpy.float32) / 255.0
    if half:
        h, w = image.shape[0] // 2, image.shape[1] // 2
        image = image[: h * 2, : w * 2].reshape(h, 2, w, 2, 4).mean(axis=(1, 3))
    alpha = image[..., 3:4]
    rgb = image[..., :3] * alpha + _PREVIEW_GROUND * (1 - alpha)
    out = numpy.concatenate([rgb, numpy.ones_like(alpha)], axis=-1)
    _write_png(path, (numpy.clip(out, 0, 1) * 255 + 0.5).astype(numpy.uint8))


def _check_name(name):
    if not isinstance(name, str) or not name or any(c in name for c in '/\\:*?"<>|.'):
        raise ValueError(f"name must be usable as a file name without dots, got {name!r}")


def _output(name, suffix):
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    return os.path.join(OUTPUT_DIR, name + suffix)


def tex_coords(size=256):
    """Return (x, y): two size x size float arrays running -1..1 across the image, x to the right and y up."""
    size = _texture_size(size)
    steps = (numpy.arange(size, dtype=numpy.float32) + 0.5) / size * 2.0 - 1.0
    return numpy.tile(steps, (size, 1)), numpy.tile(-steps[:, None], (1, size))


def tex_polar(x, y):
    """Return (r, angle) for coordinates x, y: distance from the centre, and the angle in radians from +x, counterclockwise, -pi..pi."""
    return numpy.hypot(x, y), numpy.arctan2(y, x)


def _texture_size(size):
    if not isinstance(size, int) or size < 8 or size > 2048:
        raise ValueError(f"size must be a whole number of pixels from 8 to 2048, got {size!r}")
    return size


def tex_noise(size=256, scale=4, octaves=4, seed=0):
    """Smooth fractal noise in 0..1 that tiles. scale is how many blobs fit across the image at the coarsest octave; each further octave adds detail at twice the frequency and half the strength."""
    size = _texture_size(size)
    if not isinstance(octaves, int) or octaves < 1 or octaves > 8:
        raise ValueError(f"octaves must be a whole number from 1 to 8, got {octaves!r}")
    rng = numpy.random.default_rng(seed)
    total = numpy.zeros((size, size), dtype=numpy.float32)
    weight = 0.0
    for octave in range(octaves):
        frequency = max(1, int(round(scale))) * 2 ** octave
        lattice = rng.random((frequency, frequency), dtype=numpy.float32)
        at = numpy.arange(size, dtype=numpy.float32) * frequency / size
        low = numpy.floor(at).astype(int)
        f = at - low
        f = f * f * (3.0 - 2.0 * f)
        low %= frequency
        high = (low + 1) % frequency
        top = lattice[numpy.ix_(low, low)] * (1 - f)[None, :] + lattice[numpy.ix_(low, high)] * f[None, :]
        bottom = lattice[numpy.ix_(high, low)] * (1 - f)[None, :] + lattice[numpy.ix_(high, high)] * f[None, :]
        amplitude = 0.5 ** octave
        total += (top * (1 - f)[:, None] + bottom * f[:, None]) * amplitude
        weight += amplitude
    return total / weight


def tex_cells(size=256, cells=8, seed=0):
    """Cellular (Voronoi) noise that tiles: cells x cells jittered points. Returns (near, edge): the distance to the nearest point and the gap between the nearest and second-nearest, both in cell widths. edge is 0 on the borders between cells, so tex_edge(edge, 0.05) draws the cracks, and near < radius draws round blobs. Even cells drawn as the whole shape read as floor tiles or a turtle shell: use them for detail inside a shape."""
    size = _texture_size(size)
    if not isinstance(cells, int) or cells < 1 or cells > 64:
        raise ValueError(f"cells must be a whole number from 1 to 64, got {cells!r}")
    rng = numpy.random.default_rng(seed)
    jitter = rng.random((cells, cells, 2), dtype=numpy.float32)
    at = (numpy.arange(size, dtype=numpy.float32) + 0.5) * cells / size
    px, py = numpy.meshgrid(at, at)
    cx, cy = numpy.floor(px).astype(int), numpy.floor(py).astype(int)
    first = numpy.full((size, size), 9.0, dtype=numpy.float32)
    second = numpy.full((size, size), 9.0, dtype=numpy.float32)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            nx, ny = cx + dx, cy + dy
            point = jitter[ny % cells, nx % cells]
            d = numpy.hypot(px - (nx + point[..., 0]), py - (ny + point[..., 1]))
            second = numpy.where(d < first, first, numpy.minimum(second, d))
            first = numpy.minimum(first, d)
    return first, second - first


def tex_sample(image, u, v):
    """Look a 2D image up at u, v (0..1 across and down the image), wrapping and blending between pixels. Scroll, stretch or warp noise per frame with it, as in tex_sample(noise, x * 0.5 + t, y * 0.5)."""
    image = numpy.asarray(image, dtype=numpy.float32)
    height, width = image.shape[:2]
    x = (numpy.asarray(u, dtype=numpy.float32) % 1.0) * width - 0.5
    y = (numpy.asarray(v, dtype=numpy.float32) % 1.0) * height - 0.5
    x0, y0 = numpy.floor(x).astype(int), numpy.floor(y).astype(int)
    fx, fy = x - x0, y - y0
    x0, y0 = x0 % width, y0 % height
    x1, y1 = (x0 + 1) % width, (y0 + 1) % height
    return (image[y0, x0] * (1 - fx) * (1 - fy) + image[y0, x1] * fx * (1 - fy)
            + image[y1, x0] * (1 - fx) * fy + image[y1, x1] * fx * fy)


def tex_edge(value, at=0.0, soft=0.01):
    """0 below at and 1 above it, blended over soft: the hard, cel-shaded edge. Keep soft near 0.006-0.01 for a crisp silhouette; raise it for a glow."""
    soft = max(float(soft), 1e-5)
    t = numpy.clip((numpy.asarray(value, dtype=numpy.float32) - (at - soft)) / (2 * soft), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def tex_ease(t, power=3.0):
    """Ease out: fast at first, then slow, as a burst grows. t is clamped to 0..1."""
    return 1.0 - (1.0 - numpy.clip(t, 0.0, 1.0)) ** power


_WARP_NOISE = {}


def tex_curve(points, samples=64, closed=False):
    """A smooth curve through control points (Catmull-Rom), as an (n, 2) array of x, y in tex_coords units. closed=True joins the last point back to the first. Feed it to tex_stroke."""
    p = numpy.asarray(points, dtype=numpy.float32)
    if p.ndim != 2 or p.shape[1] != 2 or len(p) < 2:
        raise ValueError("points must be at least two (x, y) pairs")
    if not isinstance(samples, int) or samples < 4 or samples > 1024:
        raise ValueError(f"samples must be a whole number from 4 to 1024, got {samples!r}")
    if closed:
        p = numpy.concatenate([p[-1:], p, p[:2]])
    else:
        p = numpy.concatenate([p[:1] * 2 - p[1:2], p, p[-1:] * 2 - p[-2:-1]])
    spans = len(p) - 3
    out = []
    for i in range(spans):
        p0, p1, p2, p3 = p[i], p[i + 1], p[i + 2], p[i + 3]
        t = numpy.linspace(0, 1, max(2, samples // spans), endpoint=(i == spans - 1))[:, None]
        out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t ** 2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    return numpy.concatenate(out)


def tex_stroke(x, y, path, width=0.08, start=0.0, end=1.0):
    """A stroke along a path, the way a brush draws it: positive inside, about the distance to its edge, so tex_edge cuts it.

    path is an (n, 2) array of points in tex_coords units; tex_curve makes a smooth one. width is
    the full width: a number, a list of widths spread evenly from head to tail, or a function of u
    (0 at the head, 1 at the tail). Tapering it gives the thick-to-thin pen pressure of a drawn
    claw, crescent, wisp or crack. Only the part from start to end (0 to 1 along the path) is drawn:
    raise end over the frames to draw the stroke on, and start to erase it from the head.
    """
    path = numpy.asarray(path, dtype=numpy.float32)
    if path.ndim != 2 or path.shape[1] != 2 or len(path) < 2:
        raise ValueError("path must be at least two (x, y) points, as tex_curve returns")
    if len(path) > 2048:
        raise ValueError(f"path has {len(path)} points; use at most 2048 (fewer tex_curve samples)")
    seg = numpy.linalg.norm(numpy.diff(path, axis=0), axis=1)
    along = numpy.concatenate([[0.0], numpy.cumsum(seg)])
    along = along / max(float(along[-1]), 1e-6)
    if callable(width):
        def profile(u):
            return numpy.asarray(width(u), dtype=numpy.float32)
    elif numpy.ndim(width) == 0:
        def profile(u):
            return numpy.full_like(u, float(width))
    else:
        keys = numpy.asarray(width, dtype=numpy.float32)

        def profile(u):
            return numpy.interp(u, numpy.linspace(0, 1, len(keys)), keys).astype(numpy.float32)
    field = numpy.full(numpy.shape(x), -1.0, dtype=numpy.float32)
    for i in range(len(path) - 1):
        a, b = path[i], path[i + 1]
        d = b - a
        length2 = max(float(d @ d), 1e-12)
        t = numpy.clip(((x - a[0]) * d[0] + (y - a[1]) * d[1]) / length2, 0.0, 1.0)
        u = along[i] + (along[i + 1] - along[i]) * t
        inside = profile(u) * 0.5 - numpy.hypot(x - (a[0] + d[0] * t), y - (a[1] + d[1] * t))
        field = numpy.maximum(field, numpy.where((u >= start) & (u <= end), inside, -1.0))
    return field


def tex_warp(x, y, amount=0.1, scale=3, seed=0, t=0.0):
    """x, y pushed around by smooth noise. Shapes drawn with the warped coordinates come out lopsided and organic instead of geometric; t drifts the noise to animate it."""
    key = (int(scale), int(seed))
    if key not in _WARP_NOISE:
        _WARP_NOISE[key] = (tex_noise(256, scale, 3, seed), tex_noise(256, scale, 3, seed + 101))
    nx, ny = _WARP_NOISE[key]
    u, v = x * 0.5 + 0.5 + t, y * 0.5 + 0.5
    return x + (tex_sample(nx, u, v) - 0.5) * 2 * amount, y + (tex_sample(ny, u, v) - 0.5) * 2 * amount


def tex_blob(x, y, radius=0.5, lumps=6, roughness=0.5, seed=0, centre=(0.0, 0.0)):
    """A lumpy, lopsided blob in one piece: a solid body with round lobes bulging from its edge, bigger on one side. It never splits or has holes, so it reads as one puff, not a cluster of circles. About radius from the centre; roughness runs from 0, a plain disc, to 1, the lumpiest. Positive inside; tex_edge cuts it."""
    rng = numpy.random.default_rng(seed)
    roughness = min(max(float(roughness), 0.0), 1.0)
    lean = rng.uniform(0, 2 * numpy.pi)
    body = radius * (0.95 - 0.35 * roughness)
    bx = centre[0] + numpy.cos(lean) * radius * 0.2 * roughness
    by = centre[1] + numpy.sin(lean) * radius * 0.2 * roughness
    field = body - numpy.hypot(x - bx, y - by)
    for _ in range(max(1, int(lumps))):
        # Each lobe is centred inside the body, so the union stays one piece with no holes.
        angle = rng.uniform(0, 2 * numpy.pi)
        reach = body * rng.uniform(0.8, 1.0)
        r = radius * roughness * rng.uniform(0.4, 0.8) * (1 + 0.4 * roughness * numpy.cos(angle - lean))
        cx, cy = bx + numpy.cos(angle) * reach, by + numpy.sin(angle) * reach
        field = numpy.maximum(field, r - numpy.hypot(x - cx, y - cy))
    return field


def _drawn_rgba(result, size, mode, where):
    """A drawing function's result as size x size x 4 bytes: alpha alone, (alpha, value), or RGB / RGBA."""
    if isinstance(result, tuple):
        if len(result) != 2:
            raise ValueError(f"{where} returned a tuple of {len(result)}; return alpha, (alpha, value) or an RGBA array")
        alpha = numpy.asarray(result[0], dtype=numpy.float32)
        value = numpy.broadcast_to(numpy.asarray(result[1], dtype=numpy.float32), (size, size))
        if alpha.shape != (size, size):
            raise ValueError(f"{where} returned alpha shaped {alpha.shape}; it must be {size} x {size}")
        rgba = numpy.stack([value, value, value, alpha], axis=-1)
    else:
        array = numpy.asarray(result, dtype=numpy.float32)
        if array.shape == (size, size):
            rgba = numpy.stack([numpy.ones_like(array)] * 3 + [array], axis=-1)
        elif array.shape == (size, size, 4):
            rgba = array
        elif array.shape == (size, size, 3):
            rgba = numpy.concatenate([array, numpy.ones((size, size, 1), dtype=numpy.float32)], axis=-1)
        else:
            raise ValueError(f"{where} returned an array shaped {array.shape}; it must be {size} x {size} (alpha), or {size} x {size} x 3 or 4")
    rgba = numpy.clip(numpy.nan_to_num(rgba), 0.0, 1.0)
    if mode == "additive":
        rgba = numpy.concatenate([rgba[..., :3] * rgba[..., 3:4], numpy.ones((size, size, 1), dtype=numpy.float32)], axis=-1)
    return (rgba * 255.0 + 0.5).astype(numpy.uint8)


def draw_flipbook(name, frame, grid=4, loop=False, fps=None, mode="alpha", padding=4):
    """Draw a particle flipbook frame by frame and pack it into a 1024 x 1024 sheet.

    frame(t, size) draws one frame size pixels square. t runs from 0 at the first frame to 1 at
    the last (to just under 1 for a loop, whose last frame leads back to the first). It returns
    alpha (a size x size array, 0..1) for a white shape, or (alpha, value) where value is the grey
    level (a number or an array), or an RGB or RGBA array. White shapes are usual: the particle's
    Color tints them, and value lets two tones in one shape take one colour. grid is 2, 4 or 8
    (4, 16 or 64 frames); 4 is what most studied artists' sheets use. fps is the speed the frames
    are meant to play at, used to suggest the Lifetime or framerate. mode "alpha" keeps a
    transparent background (LightEmission 0 or below); "additive" bakes alpha onto black for
    LightEmission 1. padding pixels around each frame stay empty.
    Writes <name>.flipbook.png, <name>.flipbook.json (what flipbook.mjs checks it against) and
    <name>.preview.png (half size, over a dark ground). Returns the sheet's path.
    """
    _check_name(name)
    if not callable(frame):
        raise ValueError("frame must be a function frame(t, size) that returns the frame's alpha, (alpha, value) or an RGBA array")
    if grid not in _FLIPBOOK_GRIDS:
        raise ValueError(f"grid must be 2, 4 or 8 (Roblox's Grid2x2, Grid4x4 and Grid8x8), got {grid!r}")
    if mode not in ("alpha", "additive"):
        raise ValueError(f'mode must be "alpha" or "additive", got {mode!r}')
    cell = _FLIPBOOK_SIDE // grid
    if not isinstance(padding, int) or padding < 0 or padding > cell // 8:
        raise ValueError(f"padding must be a whole number of pixels from 0 to {cell // 8} for a {grid} x {grid} grid, got {padding!r}")
    if fps is not None and (not isinstance(fps, (int, float)) or fps <= 0):
        raise ValueError(f"fps must be a positive number or None, got {fps!r}")
    cells = grid * grid
    inner = cell - 2 * padding
    sheet = numpy.zeros((_FLIPBOOK_SIDE, _FLIPBOOK_SIDE, 4), dtype=numpy.uint8)
    if mode == "additive":
        sheet[:, :, 3] = 255
    for index in range(cells):
        t = index / cells if loop else index / (cells - 1)
        where = f"frame(t={t:.3f}, size={inner})"
        drawn = _drawn_rgba(frame(t, inner), inner, mode, where)
        row, column = divmod(index, grid)
        top, left = row * cell + padding, column * cell + padding
        sheet[top:top + inner, left:left + inner] = drawn
    path = _output(name, ".flipbook.png")
    _write_png(path, sheet)
    _write_preview(_output(name, ".preview.png"), sheet, half=True)
    with open(_output(name, ".flipbook.json"), "w", encoding="utf-8") as handle:
        json.dump({"name": name, "grid": grid, "mode": mode, "padding": padding, "loop": bool(loop),
                   "fps": float(fps) if fps is not None else None, "drawn": True}, handle)
    return path


def render_flipbook(name, grid=4, mode="alpha", start=None, end=None, loop=False, padding=4):
    """Render the Blender scene's animation through its camera into one 1024 x 1024 flipbook sheet.

    Only inside Blender. Use it when a 3D look is the point: a simulation, a lit volume, shaded
    debris, a realistic fireball. grid is 2, 4 or 8. Frames from start to end (the scene's own
    by default) are sampled evenly to fill every cell, because Roblox plays every cell; a
    shorter animation holds some frames for two cells. mode "alpha" renders on a transparent
    film (smoke, dust, LightEmission 0); "additive" renders on black (fire, energy, glows,
    LightEmission 1). Each frame is rendered padding pixels inside its cell. loop says the last
    frame leads back into the first. Eevee or Workbench render a 64-frame sheet in seconds,
    Cycles can take minutes. Colour uses the Standard view transform, so glows stay bright.
    Frame the camera (orthographic is simplest) so the subject stays in view on every frame.
    Writes the same files as draw_flipbook, with the frames and per-frame render times in the note.
    """
    import time
    import bpy

    _check_name(name)
    if grid not in _FLIPBOOK_GRIDS:
        raise ValueError(f"grid must be 2, 4 or 8 (Roblox's Grid2x2, Grid4x4 and Grid8x8), got {grid!r}")
    if mode not in ("alpha", "additive"):
        raise ValueError(f'mode must be "alpha" (transparent film, LightEmission 0) or "additive" (black background, LightEmission 1), got {mode!r}')
    cell = _FLIPBOOK_SIDE // grid
    if not isinstance(padding, int) or padding < 0 or padding > cell // 8:
        raise ValueError(f"padding must be a whole number of pixels from 0 to {cell // 8} for a {grid} x {grid} grid, got {padding!r}")
    scene = bpy.context.scene
    if scene.camera is None:
        raise ValueError("the scene has no camera; add one and set scene.camera, framed so the whole effect stays in view")
    start = scene.frame_start if start is None else int(start)
    end = scene.frame_end if end is None else int(end)
    if end <= start:
        raise ValueError(f"end ({end}) must be after start ({start})")
    cells = grid * grid
    span = end - start + (0 if loop else 1)
    if span < cells:
        print(f"vfxtex.render_flipbook: frames {start} to {end} give {span} distinct frames for {cells} cells, so some "
              f"frames are held for two cells; a longer animation or a smaller grid avoids the holds", flush=True)
    if loop:
        frames = [start + round((end - start) * i / cells) for i in range(cells)]
    else:
        frames = [start + round((end - start) * i / (cells - 1)) for i in range(cells)]

    render = scene.render
    view = scene.view_settings
    saved = {
        "resolution_x": render.resolution_x, "resolution_y": render.resolution_y,
        "resolution_percentage": render.resolution_percentage, "film_transparent": render.film_transparent,
        "filepath": render.filepath, "file_format": render.image_settings.file_format,
        "color_mode": render.image_settings.color_mode, "view_transform": view.view_transform,
        "look": view.look, "world": scene.world, "frame": scene.frame_current,
    }
    inner = cell - 2 * padding
    frames_dir = _output(name, ".frames")
    os.makedirs(frames_dir, exist_ok=True)
    seconds = []
    sheet = numpy.zeros((_FLIPBOOK_SIDE, _FLIPBOOK_SIDE, 4), dtype=numpy.uint8)
    if mode == "additive":
        sheet[:, :, 3] = 255
    black = None
    try:
        render.resolution_x = render.resolution_y = inner
        render.resolution_percentage = 100
        render.image_settings.file_format = "PNG"
        view.view_transform = "Standard"
        view.look = "None"
        if mode == "alpha":
            render.film_transparent = True
            render.image_settings.color_mode = "RGBA"
        else:
            render.film_transparent = False
            render.image_settings.color_mode = "RGB"
            black = bpy.data.worlds.new("VfxFlipbookBlack")
            black.color = (0.0, 0.0, 0.0)
            if black.node_tree is not None:
                for node in black.node_tree.nodes:
                    if node.type == "BACKGROUND":
                        node.inputs["Color"].default_value = (0.0, 0.0, 0.0, 1.0)
                        node.inputs["Strength"].default_value = 0.0
            scene.world = black
        for index, frame in enumerate(frames):
            scene.frame_set(frame)
            path = os.path.join(frames_dir, f"{index:02d}.png")
            render.filepath = path
            began = time.perf_counter()
            bpy.ops.render.render(write_still=True)
            seconds.append(round(time.perf_counter() - began, 3))
            image = bpy.data.images.load(path, check_existing=False)
            try:
                width, height = image.size
                if (width, height) != (inner, inner):
                    raise RuntimeError(f"frame {frame} rendered at {width} x {height}, not {inner} x {inner}")
                pixels = numpy.empty(width * height * 4, dtype=numpy.float32)
                image.pixels.foreach_get(pixels)
            finally:
                bpy.data.images.remove(image)
            # Blender keeps rows bottom first; the sheet is written top first.
            frame_rgba = numpy.flipud((numpy.clip(pixels, 0.0, 1.0) * 255.0 + 0.5).astype(numpy.uint8).reshape(height, width, 4))
            if mode == "additive":
                frame_rgba[:, :, 3] = 255
            row, column = divmod(index, grid)
            top, left = row * cell + padding, column * cell + padding
            sheet[top:top + inner, left:left + inner] = frame_rgba
    finally:
        render.resolution_x, render.resolution_y = saved["resolution_x"], saved["resolution_y"]
        render.resolution_percentage = saved["resolution_percentage"]
        render.film_transparent = saved["film_transparent"]
        render.filepath = saved["filepath"]
        render.image_settings.file_format = saved["file_format"]
        render.image_settings.color_mode = saved["color_mode"]
        view.view_transform, view.look = saved["view_transform"], saved["look"]
        scene.world = saved["world"]
        if black is not None:
            bpy.data.worlds.remove(black)
        scene.frame_set(saved["frame"])

    fps = render.fps / render.fps_base
    played = frames[-1] - frames[0] + (frames[1] - frames[0] if loop else 0)
    path = _output(name, ".flipbook.png")
    _write_png(path, sheet)
    _write_preview(_output(name, ".preview.png"), sheet, half=True)
    with open(_output(name, ".flipbook.json"), "w", encoding="utf-8") as handle:
        json.dump({"name": name, "grid": grid, "mode": mode, "padding": padding, "loop": bool(loop),
                   "fps": round(cells / (played / fps), 3) if played > 0 else None,
                   "frames": frames, "engine": render.engine, "renderSeconds": seconds}, handle)
    return path


def draw_texture(name, image, size=512, mode="alpha"):
    """Draw one texture and write it as <name>.png, plus <name>.preview.png over a dark ground. image is an array, or a function image(size) returning one: alpha, (alpha, value) or RGB / RGBA, as for draw_flipbook. mode "alpha" keeps transparency; "additive" bakes it onto black. Returns the path."""
    _check_name(name)
    size = _texture_size(size)
    if mode not in ("alpha", "additive"):
        raise ValueError(f'mode must be "alpha" or "additive", got {mode!r}')
    drawn = _drawn_rgba(image(size) if callable(image) else image, size, mode, "image")
    path = _output(name, ".png")
    _write_png(path, drawn)
    _write_preview(_output(name, ".preview.png"), drawn, half=size > 512)
    return path
