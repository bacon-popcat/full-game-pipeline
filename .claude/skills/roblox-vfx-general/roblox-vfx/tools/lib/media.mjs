// Reading video and image files through ffmpeg/ffprobe (which must be on PATH), and tiling
// frames into labelled contact sheets.
// Part of the roblox-vfx skill's tools, which ports Roqer's reference-clip workflow
// (https://github.com/S4US/Roqer, AGPL-3.0-or-later; see ../LICENSE).
import { spawnSync } from "node:child_process";
import { drawLabel, labelScale } from "./labels.mjs";

function run(command, args) {
  const result = spawnSync(command, args, { maxBuffer: 1024 * 1024 * 1024, windowsHide: true });
  if (result.error) {
    if (result.error.code === "ENOENT") throw new Error(`${command} was not found. Install ffmpeg (it includes ffprobe) and put it on PATH.`);
    throw result.error;
  }
  if (result.status !== 0) {
    const stderr = result.stderr.toString().trim().split("\n").slice(-6).join("\n");
    throw new Error(`${command} failed (exit ${result.status}):\n${stderr}`);
  }
  return result.stdout;
}

/** { width, height, duration, fps } of a video or image's first video stream. */
export function probe(file) {
  const out = run("ffprobe", [
    "-v", "error", "-select_streams", "v:0",
    "-show_entries", "stream=width,height,avg_frame_rate,r_frame_rate:format=duration",
    "-of", "json", file,
  ]);
  const info = JSON.parse(out.toString());
  const stream = info.streams?.[0];
  if (!stream) throw new Error(`${file} has no video stream.`);
  const rate = (text) => {
    const [n, d] = String(text ?? "0/1").split("/").map(Number);
    return d ? n / d : n;
  };
  const fps = rate(stream.avg_frame_rate) || rate(stream.r_frame_rate) || 0;
  return { width: stream.width, height: stream.height, duration: Number(info.format?.duration ?? 0), fps };
}

/** Even pixel size for a long side of `edge`, keeping the aspect. */
export function fitSize(width, height, edge) {
  const scale = Math.min(1, edge / Math.max(width, height));
  const even = (value) => Math.max(2, Math.round((value * scale) / 2) * 2);
  return { width: even(width), height: even(height) };
}

/** Writes frames `from`..`to` (seconds in the file) at `fps` as JPEGs `frame-000.jpg`... in `dir`. */
export function extractJpegs(video, { from, to, fps, width, height, dir }) {
  run("ffmpeg", [
    "-v", "error", "-y", "-ss", String(from), "-t", String(to - from), "-i", video,
    "-vf", `fps=${fps},scale=${width}:${height}:flags=lanczos`,
    "-q:v", "3", "-start_number", "0", `${dir}/frame-%03d.jpg`,
  ]);
}

function cropFilter(crop) {
  if (!crop) return [];
  const { x, y, width, height } = crop;
  return [`crop=trunc(iw*${width}/2)*2:trunc(ih*${height}/2)*2:trunc(iw*${x}):trunc(ih*${y})`];
}

/** Decodes one image (any format ffmpeg reads) to { width, height, pixels } RGBA at the given size. */
export function decodeImage(file, width, height, crop) {
  const filters = [...cropFilter(crop), `scale=${width}:${height}:flags=area`].join(",");
  const pixels = run("ffmpeg", ["-v", "error", "-i", file, "-frames:v", "1", "-vf", filters, "-f", "rawvideo", "-pix_fmt", "rgba", "-"]);
  if (pixels.length < width * height * 4) throw new Error(`Could not decode ${file}.`);
  return { width, height, pixels: new Uint8Array(pixels.buffer, pixels.byteOffset, width * height * 4) };
}

/** Decodes a numbered JPEG sequence (`frame-%03d.jpg` in `dir`) to RGBA frames of one size. */
export function decodeSequence(dir, width, height) {
  const raw = run("ffmpeg", [
    "-v", "error", "-framerate", "1", "-start_number", "0", "-i", `${dir}/frame-%03d.jpg`,
    "-vf", `scale=${width}:${height}:flags=area`, "-f", "rawvideo", "-pix_fmt", "rgba", "-",
  ]);
  const size = width * height * 4;
  const frames = [];
  for (let offset = 0; offset + size <= raw.length; offset += size) {
    frames.push(new Uint8Array(raw.buffer, raw.byteOffset + offset, size));
  }
  return frames;
}

/** Frames to a row for `count` frames: square-ish, at most four across. */
export function sheetColumns(count) {
  if (count <= 1) return 1;
  if (count <= 4) return 2;
  if (count <= 9) return 3;
  return 4;
}

const GUTTER = 4;
const BACKGROUND = 24;

/**
 * Tiles `tiles` ({ width, height, pixels, label }) into one RGBA sheet, `columns` to a row,
 * left to right then top to bottom, each with its label drawn in its top-left corner.
 */
export function composeSheet(tiles, columns) {
  const cellWidth = Math.max(...tiles.map((tile) => tile.width));
  const cellHeight = Math.max(...tiles.map((tile) => tile.height));
  const rows = Math.ceil(tiles.length / columns);
  const width = columns * cellWidth + (columns + 1) * GUTTER;
  const height = rows * cellHeight + (rows + 1) * GUTTER;
  const rgba = Buffer.alloc(width * height * 4);
  for (let i = 0; i < width * height; i++) {
    rgba[i * 4] = rgba[i * 4 + 1] = rgba[i * 4 + 2] = BACKGROUND;
    rgba[i * 4 + 3] = 255;
  }
  tiles.forEach((tile, index) => {
    const left = GUTTER + (index % columns) * (cellWidth + GUTTER);
    const top = GUTTER + Math.floor(index / columns) * (cellHeight + GUTTER);
    for (let y = 0; y < tile.height; y++) {
      for (let x = 0; x < tile.width; x++) {
        const from = (y * tile.width + x) * 4;
        const to = ((top + y) * width + left + x) * 4;
        const alpha = tile.pixels[from + 3] / 255;
        for (let c = 0; c < 3; c++) rgba[to + c] = Math.round(tile.pixels[from + c] * alpha + BACKGROUND * (1 - alpha));
      }
    }
    if (tile.label) drawLabel(rgba, width, height, left + 2, top + 2, tile.label, labelScale(tile.width));
  });
  return { width, height, rgba };
}
