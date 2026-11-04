#!/usr/bin/env node
// Reference clips for matching an effect: read a video into stored frames with measurements,
// look closer at a span, compare captures of our effect beside the clip, and check the colour
// of captured frames. Run `node <skill>/tools/clip.mjs help` for usage.
//
// Ported from Roqer's reference_clip and capture_moments tools (https://github.com/S4US/Roqer,
// apps/desktop/runtime/reference-clip.ts, clip-analysis.ts, effect-tone.ts),
// AGPL-3.0-or-later; see LICENSE. Changes: a command-line tool that reads videos with ffmpeg
// instead of Roqer's app, and compares against captures saved as image files.
import fs from "node:fs";
import path from "node:path";
import { analyseClip, describeClipAnalysis, describeEffectTone, measureEffectTone } from "./lib/analysis.mjs";
import { frameLabel } from "./lib/labels.mjs";
import { composeSheet, decodeImage, decodeSequence, extractJpegs, fitSize, probe, sheetColumns } from "./lib/media.mjs";
import { encodePng } from "./lib/png.mjs";

const MAX_SELECTION_SECONDS = 10;
const MAX_FRAMES = 300;

const USAGE = `Usage: node <skill>/tools/clip.mjs <command> ...

  read <video> [--from s] [--to s] [--speed x] [--fps n] [--edge px] [--out dir]
      Store the clip's frames from --from to --to (seconds in the file; default the whole
      file, at most ${MAX_SELECTION_SECONDS} s of it), measure the effect, and write an overview sheet (and a
      close-up of the start when the overview skips frames there).
      --speed: how fast the recording plays relative to the game: 0.25 for a 0.25x slow-motion
               capture. Every time printed or labelled is effect seconds (real game time) from
               --from: (clip time - from) * speed.
      --fps:   frames stored per second of the file (default its own rate, at most 60, lowered
               so at most 300 frames are stored).
      --edge:  stored frames' long side in pixels (default 960).
      --out:   folder for the stored clip (default .vfx-clips/<video name>).

  span <clip dir> --from t --to t [--count n] [--crop full] [--out file.png]
      A sheet of up to 16 stored frames between two effect times, spread evenly, labelled with
      their effect times. Cropped to where the clip changes unless --crop full.

  compare <clip dir> (--at t=image ...) | (--captures dir) [--crop full] [--out file.png]
      Each capture of our effect beside the clip's nearest frame: R (reference) then S (Studio),
      both labelled with the effect time. With --captures, files are named by their effect time
      (0.10.png, 0.10s.png, t0.10.jpg).

  tone <image> ... | --dir folder [--empty image]
      Colour check on captures of our effect from one still camera: the share of its pixels
      that are pale, vivid, deep and blown out, against studied artists' effects. Pass --empty,
      a capture of the same view with no effect, as the background. Without it the background is
      the per-pixel median of the captures, which needs at least 3 and works only when the
      effect covers different places in most of them; a big effect then measures wrong.
`;

const MAX_FPS = 60;
const MAX_SHEET_FRAMES = 16;
const CLOSE_UP_FRAMES = 8;
const ANALYSIS_EDGE = 160;
const SHEET_WIDTH = 1600;

function parseArgs(argv) {
  const positional = [];
  const options = {};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (!arg.startsWith("--")) {
      positional.push(arg);
      continue;
    }
    const key = arg.slice(2);
    const value = argv[i + 1];
    if (value === undefined || value.startsWith("--")) throw new Error(`--${key} needs a value.`);
    i++;
    if (key === "at") (options.at ??= []).push(value);
    else options[key] = value;
  }
  return { positional, options };
}

function number(value, name, fallback) {
  if (value === undefined) return fallback;
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) throw new Error(`--${name} must be a number, got ${value}.`);
  return parsed;
}

const effectTime = (manifest, index) => (manifest.frames[index] - manifest.from) * manifest.speed;

function loadManifest(dir) {
  const file = path.join(dir, "manifest.json");
  if (!fs.existsSync(file)) throw new Error(`${dir} is not a stored clip (no manifest.json). Run \`clip.mjs read\` first.`);
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function framesBetween(manifest, from, to) {
  const indexes = [];
  manifest.frames.forEach((_, index) => {
    const time = effectTime(manifest, index);
    if (time >= from - 0.0005 && time <= to + 0.0005) indexes.push(index);
  });
  return indexes;
}

function spread(indexes, count) {
  if (indexes.length <= count) return [...indexes];
  if (count <= 1) return [indexes[0]];
  const picked = new Set();
  for (let slot = 0; slot < count; slot++) picked.add(indexes[Math.round((slot * (indexes.length - 1)) / (count - 1))]);
  return [...picked];
}

function nearestFrame(manifest, time) {
  let best = 0;
  manifest.frames.forEach((_, index) => {
    if (Math.abs(effectTime(manifest, index) - time) < Math.abs(effectTime(manifest, best) - time)) best = index;
  });
  return best;
}

function tileSize(manifest, crop, tileWidth) {
  const width = manifest.width * (crop?.width ?? 1);
  const height = manifest.height * (crop?.height ?? 1);
  const scale = tileWidth / width;
  const even = (value) => Math.max(2, Math.round(value / 2) * 2);
  return { width: even(width * scale), height: even(height * scale) };
}

function frameFile(dir, index) {
  return path.join(dir, "frames", `frame-${String(index).padStart(3, "0")}.jpg`);
}

/** Writes a labelled sheet of stored frames and returns a line describing it. */
function writeSheet(dir, manifest, indexes, file, cropMode) {
  const crop = cropMode === "full" ? undefined : manifest.analysis.crop;
  const columns = sheetColumns(indexes.length);
  const size = tileSize(manifest, crop, Math.floor(Math.min(480, SHEET_WIDTH / columns) / 2) * 2);
  const tiles = indexes.map((index, position) => ({
    ...decodeImage(frameFile(dir, index), size.width, size.height, crop),
    label: frameLabel(position + 1, effectTime(manifest, index)),
  }));
  const sheet = composeSheet(tiles, columns);
  fs.writeFileSync(file, encodePng(sheet.width, sheet.height, sheet.rgba));
  const first = effectTime(manifest, indexes[0]);
  const last = effectTime(manifest, indexes[indexes.length - 1]);
  const span = framesBetween(manifest, first, last);
  const every = span.length === indexes.length ? "every stored frame there" : `spread evenly over the ${span.length} stored frames there`;
  return `${file}: ${indexes.length} frames at ${first.toFixed(3)}-${last.toFixed(3)} s, ${every}, ${columns} to a row, labelled with number and effect time${crop ? ", cropped to where the clip changes" : ""}.`;
}

function read(positional, options) {
  const video = positional[0];
  if (!video || !fs.existsSync(video)) throw new Error("read needs an existing video file.");
  const info = probe(video);
  const duration = info.duration > 0 ? info.duration : MAX_SELECTION_SECONDS;
  const from = Math.max(0, number(options.from, "from", 0));
  let to = Math.min(duration, number(options.to, "to", duration));
  if (to - from > MAX_SELECTION_SECONDS) {
    to = from + MAX_SELECTION_SECONDS;
    console.log(`Note: only ${MAX_SELECTION_SECONDS} s are stored; pass --from/--to for another stretch.`);
  }
  if (to <= from) throw new Error(`--to (${to}) must be after --from (${from}).`);
  const speed = number(options.speed, "speed", 1);
  if (speed <= 0 || speed > 1) throw new Error("--speed is how fast the recording plays relative to the game: 1 for real time, 0.25 for 0.25x slow motion.");
  let fps = number(options.fps, "fps", Math.min(MAX_FPS, Math.round(info.fps) || 30));
  if ((to - from) * fps > MAX_FRAMES) {
    fps = Math.floor(MAX_FRAMES / (to - from));
    console.log(`Note: storing ${fps} frames a second so the stretch fits in ${MAX_FRAMES} frames; pass a shorter --from/--to for more.`);
  }
  const edge = number(options.edge, "edge", 960);
  const size = fitSize(info.width, info.height, edge);
  const dir = options.out ?? path.join(".vfx-clips", path.parse(video).name);
  fs.rmSync(path.join(dir, "frames"), { recursive: true, force: true });
  fs.mkdirSync(path.join(dir, "frames"), { recursive: true });
  extractJpegs(video, { from, to, fps, width: size.width, height: size.height, dir: path.join(dir, "frames") });
  const stored = fs.readdirSync(path.join(dir, "frames")).filter((name) => /^frame-\d{3}\.jpg$/.test(name)).length;
  if (stored === 0) throw new Error("ffmpeg stored no frames; check --from/--to.");
  const frames = Array.from({ length: stored }, (_, index) => Math.round((from + index / fps) * 10000) / 10000);

  const small = fitSize(size.width, size.height, ANALYSIS_EDGE);
  const pixels = decodeSequence(path.join(dir, "frames"), small.width, small.height);
  const analysis = analyseClip(pixels.map((data, index) => ({ time: (frames[index] - from) * speed, width: small.width, height: small.height, pixels: data })));
  const manifest = { version: 1, source: path.resolve(video), from, to, speed, fps, width: size.width, height: size.height, frames, analysis };
  fs.writeFileSync(path.join(dir, "manifest.json"), JSON.stringify(manifest, null, 2));

  console.log(`Stored ${stored} frames of ${path.basename(video)} (${from.toFixed(2)}-${to.toFixed(2)} s of the file at ${fps} a second${speed !== 1 ? `, recorded at ${speed}x` : ""}) in ${dir}.`);
  console.log(`Effect time runs 0-${((to - from) * speed).toFixed(3)} s; one stored frame is ${(speed / fps * 1000).toFixed(1)} ms of game time.`);
  console.log(describeClipAnalysis(analysis).join("\n"));

  // The overview spreads 16 frames over where the clip changes; the close-up shows the start
  // through the fall to half at the stored rate when the overview steps over it.
  const all = frames.map((_, index) => index);
  let overviewSpan = all;
  if (analysis.active && !analysis.cameraMoves && analysis.onset !== undefined && analysis.end !== undefined) {
    const pad = Math.max((analysis.end - analysis.onset) * 0.1, 0.05);
    const active = framesBetween(manifest, analysis.onset - pad, analysis.end + pad);
    if (active.length >= 2) overviewSpan = active;
  }
  const overview = spread(overviewSpan, MAX_SHEET_FRAMES);
  console.log(`Sheets:\n- ${writeSheet(dir, manifest, overview, path.join(dir, "overview.png"))}`);
  if (analysis.active && !analysis.cameraMoves && analysis.onset !== undefined && analysis.half !== undefined) {
    const attack = framesBetween(manifest, analysis.onset, analysis.half);
    if (attack.filter((index) => !overview.includes(index)).length >= 3) {
      console.log(`- ${writeSheet(dir, manifest, spread(attack, CLOSE_UP_FRAMES), path.join(dir, "closeup.png"))}`);
    }
  }
}

function span(positional, options) {
  const dir = positional[0];
  if (!dir) throw new Error("span needs a stored clip folder.");
  const manifest = loadManifest(dir);
  const from = number(options.from, "from");
  const to = number(options.to, "to");
  if (from === undefined || to === undefined || to < from) throw new Error("span needs --from and --to effect times, --to after --from.");
  const count = Math.max(1, Math.min(MAX_SHEET_FRAMES, number(options.count, "count", 8)));
  const indexes = framesBetween(manifest, from, to);
  if (indexes.length === 0) {
    const last = effectTime(manifest, manifest.frames.length - 1);
    throw new Error(`No stored frames between ${from} and ${to} s; the clip runs 0-${last.toFixed(3)} s of effect time.`);
  }
  const out = options.out ?? path.join(dir, `span-${from.toFixed(3)}-${to.toFixed(3)}.png`);
  console.log(writeSheet(dir, manifest, spread(indexes, count), out, options.crop));
}

function capturesFrom(options) {
  const pairs = [];
  for (const entry of options.at ?? []) {
    const at = entry.indexOf("=");
    if (at < 0) throw new Error(`--at takes time=image, got ${entry}.`);
    pairs.push({ time: number(entry.slice(0, at), "at"), file: entry.slice(at + 1) });
  }
  if (options.captures) {
    for (const name of fs.readdirSync(options.captures)) {
      const match = /^t?(\d+(?:\.\d+)?)s?\.(png|jpe?g|webp|bmp)$/i.exec(name);
      if (match) pairs.push({ time: Number(match[1]), file: path.join(options.captures, name) });
    }
  }
  return pairs.sort((a, b) => a.time - b.time);
}

function compare(positional, options) {
  const dir = positional[0];
  if (!dir) throw new Error("compare needs a stored clip folder.");
  const manifest = loadManifest(dir);
  const captures = capturesFrom(options);
  if (captures.length === 0) throw new Error("compare needs captures: --at <time>=<image> (repeatable) or --captures <folder>.");
  if (captures.length > 8) throw new Error("Compare at most 8 moments at once; pick the 4-6 that matter (start, peak, half, gone).");
  const crop = options.crop === "full" ? undefined : manifest.analysis.crop;
  const reference = tileSize(manifest, crop, 480);
  const tiles = [];
  const lines = [];
  for (const capture of captures) {
    if (!fs.existsSync(capture.file)) throw new Error(`${capture.file} does not exist.`);
    const index = nearestFrame(manifest, capture.time);
    const time = effectTime(manifest, index);
    const info = probe(capture.file);
    const height = reference.height;
    const width = Math.max(2, Math.round((info.width * height) / info.height / 2) * 2);
    tiles.push({ ...decodeImage(frameFile(dir, index), reference.width, reference.height, crop), label: `R ${time.toFixed(2)}s` });
    tiles.push({ ...decodeImage(capture.file, width, height), label: `S ${capture.time.toFixed(2)}s` });
    lines.push(`- ${capture.time.toFixed(3)} s: ${path.basename(capture.file)} beside stored frame ${index} (${time.toFixed(3)} s)`);
  }
  const sheet = composeSheet(tiles, 2);
  const out = options.out ?? path.join(dir, "compare.png");
  fs.writeFileSync(out, encodePng(sheet.width, sheet.height, sheet.rgba));
  console.log(`${out}: each row is the clip (R) then our capture (S) at one effect time.\n${lines.join("\n")}`);
  console.log("Compare when each layer starts, peaks and fades, its size against the frame, its colours and its shape: proportions, not position.");
}

function tone(positional, options) {
  let files = [...positional];
  if (options.dir) {
    files.push(...fs.readdirSync(options.dir).filter((name) => /\.(png|jpe?g|webp|bmp)$/i.test(name)).sort().map((name) => path.join(options.dir, name)));
  }
  if (files.length < (options.empty ? 1 : 3)) throw new Error("tone needs at least 3 captures from one still camera, or 1 with --empty.");
  const info = probe(files[0]);
  const size = fitSize(info.width, info.height, ANALYSIS_EDGE);
  const frames = files.map((file) => decodeImage(file, size.width, size.height));
  const empty = options.empty ? decodeImage(options.empty, size.width, size.height) : undefined;
  console.log(describeEffectTone(measureEffectTone(frames, empty)).join("\n"));
}

const COMMANDS = { read, span, compare, tone };

try {
  const [command, ...rest] = process.argv.slice(2);
  if (!command || command === "help" || command === "--help" || !COMMANDS[command]) {
    console.log(USAGE);
    process.exit(command && !["help", "--help"].includes(command) ? 1 : 0);
  }
  const { positional, options } = parseArgs(rest);
  COMMANDS[command](positional, options);
} catch (error) {
  console.error(`clip.mjs: ${error.message}`);
  process.exit(1);
}
