#!/usr/bin/env node
// Checks particle flipbook sheets from their pixels. Roblox plays every cell of the grid in
// order, and a frame that runs into its neighbour's cell shows as a sliver of the next frame.
// Sheets are 1024 x 1024: that size was uploaded and seen playing frame by frame in Studio
// (Studio's FlipbookIncompatible message says "must be 1024 by 1024" even for that sheet, so
// it is no check). A `<name>.flipbook.json` beside the sheet (vfxtex.py writes one) says what
// the script meant to make; this reads what it made, so the two can be compared.
//
// Usage: node <skill>/tools/flipbook.mjs <sheet.png> ... [--grid 4] [--oneshot|--loop] [--fps n] [--padding px]
//
// Ported from Roqer (https://github.com/S4US/Roqer, apps/desktop/runtime/flipbook-sheet.ts),
// AGPL-3.0-or-later; see LICENSE. Changes: plain JavaScript and a command line.
import fs from "node:fs";
import path from "node:path";
import { decodePng } from "./lib/png.mjs";

const FLIPBOOK_SIDE = 1024;
const FLIPBOOK_GRIDS = [2, 4, 8];
const MAX_FLIPBOOK_FRAMERATE = 30;
/** A pixel counts as drawn above this: alpha on a transparent sheet, brightness on a black one. */
const CONTENT_THRESHOLD = 8;
/** A pixel is part of the drawing's body, not its faint rim, at or above this. */
const BODY_THRESHOLD = 96;
/**
 * A frame whose body differs from the last one by less than this share is all but held.
 * Studied artists' one-shot sheets change a median 44% from one 4 x 4 frame to the next.
 */
const SLOW_CHANGE = 0.12;

function contentMask(image) {
  const { width, height, rgba } = image;
  const corners = [0, width - 1, (height - 1) * width, height * width - 1];
  const transparent = image.hasAlpha && corners.every((i) => rgba[i * 4 + 3] <= CONTENT_THRESHOLD);
  const black = corners.every((i) => Math.max(rgba[i * 4], rgba[i * 4 + 1], rgba[i * 4 + 2]) <= CONTENT_THRESHOLD);
  const background = transparent ? "transparent" : black ? "black" : "other";
  const mask = new Uint8Array(width * height);
  for (let i = 0; i < width * height; i++) {
    const alpha = rgba[i * 4 + 3];
    const bright = Math.max(rgba[i * 4], rgba[i * 4 + 1], rgba[i * 4 + 2]);
    mask[i] = background === "transparent"
      ? (alpha > CONTENT_THRESHOLD ? 1 : 0)
      : (alpha > CONTENT_THRESHOLD && bright > CONTENT_THRESHOLD ? 1 : 0);
  }
  return { mask, background };
}

/** The stretch where a sheet holds one drawing, if it has one. */
function findHeldStretch(bodies, grid, repeatedCells) {
  const areas = bodies.map((body) => body.reduce((sum, value) => sum + value, 0));
  const largest = Math.max(...areas);
  if (largest === 0) return undefined;
  const from = areas.findIndex((area) => area >= largest / 2);
  let to = areas.length - 1;
  while (to > from && areas[to] <= largest * 0.02) to--;
  const step = grid === 8 ? 4 : 1;
  const repeated = new Set(repeatedCells);
  const changes = [];
  for (let index = from; index + step <= to; index++) {
    let exact = true;
    for (let k = 1; k <= step; k++) exact &&= repeated.has(index + k);
    if (exact) continue;
    const a = bodies[index];
    const b = bodies[index + step];
    let both = 0;
    let either = 0;
    for (let i = 0; i < a.length; i++) {
      both += a[i] & b[i];
      either += a[i] | b[i];
    }
    changes.push(either === 0 ? 0 : 1 - both / either);
  }
  if (changes.length < 3) return undefined;
  const sorted = [...changes].sort((x, y) => x - y);
  const middle = sorted.length / 2;
  const median = sorted.length % 2 === 1 ? sorted[Math.floor(middle)] : (sorted[middle - 1] + sorted[middle]) / 2;
  const slow = changes.filter((change) => change < SLOW_CHANGE).length;
  if (median >= SLOW_CHANGE || slow * 2 < changes.length) return undefined;
  return { from, to, change: Math.round(median * 1000) / 1000 };
}

/** Whether a grid's boundary rows and columns, two pixels each, are free of drawing. */
function gutterClear(mask, side, grid) {
  const cell = side / grid;
  for (let k = 1; k < grid; k++) {
    for (const line of [k * cell - 1, k * cell]) {
      for (let t = 0; t < side; t++) {
        if (mask[line * side + t] || mask[t * side + line]) return false;
      }
    }
  }
  return true;
}

function listCells(cells) {
  const shown = cells.slice(0, 8).map((cell) => `#${cell + 1}`).join(", ");
  return cells.length > 8 ? `${shown} and ${cells.length - 8} more` : shown;
}

/** Checks a sheet against what its maker claims ({ grid, loop, fps, padding }, all optional). */
export function analyzeFlipbook(png, claim = {}) {
  const image = decodePng(png);
  const problems = [];
  const { mask, background } = contentMask(image);
  const base = { width: image.width, height: image.height, background, coverage: [], emptyCells: [], edgeCells: [], repeatedCells: [] };
  if (image.width !== FLIPBOOK_SIDE || image.height !== FLIPBOOK_SIDE) {
    return { ...base, ok: false, problems: [`The sheet is ${image.width} x ${image.height}; make it 1024 x 1024, the size seen playing as a flipbook in Roblox.`] };
  }
  const side = FLIPBOOK_SIDE;
  const detectedGrid = [...FLIPBOOK_GRIDS].reverse().find((grid) => gutterClear(mask, side, grid));
  const claimed = FLIPBOOK_GRIDS.find((grid) => grid === claim.grid);
  if (claim.grid !== undefined && claimed === undefined) problems.push(`The claimed grid is ${claim.grid} x ${claim.grid}; Roblox's layouts are 2 x 2, 4 x 4 and 8 x 8.`);
  if (claimed !== undefined && !gutterClear(mask, side, claimed)) {
    problems.push(`Drawing crosses the cell boundaries of the claimed ${claimed} x ${claimed} grid, so frames run into each other or the sheet is not laid out on that grid.`);
  }
  if (background === "other") problems.push("The sheet's corners are neither transparent nor black, so it has no clear background: use transparency for alpha blending, or black for additive.");
  const grid = claimed ?? detectedGrid;
  if (grid === undefined) {
    problems.push("No 2 x 2, 4 x 4 or 8 x 8 grid fits: drawing crosses the boundaries of every one.");
    return { ...base, ok: false, problems };
  }

  const cell = side / grid;
  const padding = Math.max(0, Math.min(cell / 4, Math.floor(claim.padding ?? 0)));
  const band = padding + 2;
  const coverage = [];
  const emptyCells = [];
  const edgeCells = [];
  const repeatedCells = [];
  const bodies = [];
  let previous;
  for (let row = 0; row < grid; row++) {
    for (let column = 0; column < grid; column++) {
      const index = row * grid + column;
      let drawn = 0;
      let touches = false;
      const bytes = Buffer.alloc(cell * cell * 4);
      const body = new Uint8Array(cell * cell);
      for (let y = 0; y < cell; y++) {
        const sheetRow = row * cell + y;
        image.rgba.copy(bytes, y * cell * 4, (sheetRow * side + column * cell) * 4, (sheetRow * side + column * cell + cell) * 4);
        for (let x = 0; x < cell; x++) {
          const pixel = (y * cell + x) * 4;
          const level = background === "black" ? Math.max(bytes[pixel], bytes[pixel + 1], bytes[pixel + 2]) : bytes[pixel + 3];
          if (level >= BODY_THRESHOLD) body[y * cell + x] = 1;
          if (!mask[sheetRow * side + column * cell + x]) continue;
          drawn++;
          if (x < band || y < band || x >= cell - band || y >= cell - band) touches = true;
        }
      }
      coverage.push(Math.round((drawn / (cell * cell)) * 1000) / 10);
      if (drawn === 0) emptyCells.push(index);
      if (touches) edgeCells.push(index);
      if (previous !== undefined && drawn > 0 && previous.equals(bytes)) repeatedCells.push(index);
      previous = bytes;
      bodies.push(body);
    }
  }
  const heldStretch = findHeldStretch(bodies, grid, repeatedCells);
  const cells = grid * grid;
  // A burst played once may end fully faded: its last cells are empty on purpose.
  let fadedTail = 0;
  if (claim.loop === false) {
    while (fadedTail < emptyCells.length && emptyCells[emptyCells.length - 1 - fadedTail] === cells - 1 - fadedTail) fadedTail++;
  }
  const blinking = emptyCells.slice(0, emptyCells.length - fadedTail);
  if (emptyCells.length === cells) problems.push("Every cell is empty: nothing was drawn, or the subject is outside the camera's view.");
  else if (blinking.length > 0) {
    problems.push(`${blinking.length} of ${cells} cells are empty (${listCells(blinking)}); Roblox plays every cell, so a particle blinks out on each.`);
  }
  if (edgeCells.length > 0) problems.push(`Drawing reaches the edge of ${edgeCells.length} cell${edgeCells.length === 1 ? "" : "s"} (${listCells(edgeCells)}): it is cut off there. Draw it smaller, or frame it smaller with the camera further back.`);
  const notes = [];
  if (repeatedCells.length > 0) notes.push(`${repeatedCells.length} cell${repeatedCells.length === 1 ? " repeats" : "s repeat"} the one before (${listCells(repeatedCells)}): the animation holds there. Fine for a pause; otherwise animate more frames or use a smaller grid.`);
  if (heldStretch !== undefined) {
    const pace = grid === 8 ? " (every fourth cell, the pace of a 4 x 4 sheet)" : "";
    notes.push(`Cells #${heldStretch.from + 1}-#${heldStretch.to + 1} barely change shape: the outline moves a median ${Math.round(heldStretch.change * 100)}% from one frame to the next${pace}, where studied artists' sheets move about 40%. There the sheet plays as one still image that only scales or fades. Fine for a ring, crack or glow that only fades; a burst, fire or smoke should keep changing shape (grow, boil, break apart) in every frame.`);
  }
  const fps = claim.fps !== undefined && claim.fps > 0 ? claim.fps : undefined;
  const lifetime = claim.loop === false && fps !== undefined ? Math.round((cells / fps) * 100) / 100 : undefined;
  const framerate = claim.loop !== false && fps !== undefined ? Math.min(MAX_FLIPBOOK_FRAMERATE, Math.round(fps)) : undefined;
  const settings = {
    FlipbookLayout: `Grid${grid}x${grid}`,
    FlipbookMode: claim.loop === false ? "OneShot" : "Loop",
    LightEmission: background === "black" ? 1 : 0,
    ...(lifetime === undefined ? {} : { lifetime }),
    ...(framerate === undefined ? {} : { framerate }),
  };
  return {
    ...base, ok: problems.length === 0, detectedGrid, grid, coverage, emptyCells, edgeCells, repeatedCells,
    ...(heldStretch === undefined ? {} : { heldStretch }), problems, notes, settings,
  };
}

/** The report as lines of text. */
export function describeFlipbook(name, report) {
  const lines = [`- ${name}: ${report.width} x ${report.height}, ${report.background} background${report.grid === undefined ? "" : `, ${report.grid} x ${report.grid} grid${report.detectedGrid === report.grid ? " (its gutters agree)" : ""}`}.`];
  if (report.coverage.length > 0) {
    lines.push(`  Coverage per cell, in play order (% drawn): ${report.coverage.map((value) => value.toFixed(0)).join(" ")}`);
  }
  for (const problem of report.problems) lines.push(`  Problem: ${problem}`);
  for (const note of report.notes ?? []) lines.push(`  Note: ${note}`);
  if (report.settings !== undefined) {
    const { FlipbookLayout, FlipbookMode, LightEmission, lifetime, framerate } = report.settings;
    lines.push(`  On a ParticleEmitter: FlipbookLayout = ${FlipbookLayout}, FlipbookMode = ${FlipbookMode}, LightEmission = ${LightEmission}${lifetime === undefined ? "" : `, Lifetime = ${lifetime} (OneShot plays the sheet once per lifetime)`}${framerate === undefined ? "" : `, FlipbookFramerate = ${framerate} (the speed it was animated at${framerate === MAX_FLIPBOOK_FRAMERATE ? ", or Roblox's limit of 30" : ""})`}.`);
  }
  return lines;
}

function main(argv) {
  const files = [];
  const flags = {};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--oneshot") flags.loop = false;
    else if (arg === "--loop") flags.loop = true;
    else if (["--grid", "--fps", "--padding"].includes(arg)) flags[arg.slice(2)] = Number(argv[++i]);
    else if (arg.startsWith("--")) throw new Error(`Unknown option ${arg}.`);
    else files.push(arg);
  }
  if (files.length === 0) {
    console.log("Usage: node <skill>/tools/flipbook.mjs <sheet.png> ... [--grid 2|4|8] [--oneshot|--loop] [--fps n] [--padding px]");
    return 1;
  }
  let failed = false;
  for (const file of files) {
    const notePath = file.replace(/\.png$/i, ".json");
    let claim = {};
    if (notePath !== file && fs.existsSync(notePath)) {
      const note = JSON.parse(fs.readFileSync(notePath, "utf8"));
      claim = { grid: note.grid, loop: note.loop, fps: note.fps ?? undefined, padding: note.padding };
    }
    claim = { ...claim, ...flags };
    const report = analyzeFlipbook(fs.readFileSync(file), claim);
    console.log(describeFlipbook(path.basename(file), report).join("\n"));
    if (!report.ok) failed = true;
  }
  return failed ? 2 : 0;
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith("flipbook.mjs")) {
  try {
    process.exitCode = main(process.argv.slice(2));
  } catch (error) {
    console.error(`flipbook.mjs: ${error.message}`);
    process.exitCode = 1;
  }
}
