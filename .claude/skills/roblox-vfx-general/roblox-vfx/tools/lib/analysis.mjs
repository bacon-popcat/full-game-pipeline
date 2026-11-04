// Measurements taken from the pixels of a clip's frames: when an effect starts, peaks, falls
// to half and is gone, how bright and how big it gets, and its colours by phase (analyseClip);
// and how an effect's colour reads in captured frames: pale, vivid, deep or blown out
// (measureEffectTone).
//
// Everything is measured against the frames' own background: the per-pixel median of a few
// quiet frames. A pixel has changed when one of its channels moved more than CHANGE_THRESHOLD
// from it. A moving camera changes the whole frame, and is reported as such rather than
// measured as an effect.
//
// Ported from Roqer (https://github.com/S4US/Roqer, apps/desktop/runtime/clip-analysis.ts and
// effect-tone.ts), AGPL-3.0-or-later; see ../LICENSE. Changes: plain JavaScript, RGBA pixels only.

/** How far, out of 255, one channel must move from the background for a pixel to count as changed. */
export const CHANGE_THRESHOLD = 32;
const EDGE_SHARE = 0.15;
const MIN_ACTIVITY = 0.002;
const MIN_VISIBLE_AREA = 0.001;
const WHOLE_FRAME = 0.6;
const CAMERA_FRAMES = 0.4;
const MAX_CROP_AREA = 0.6;
const COLOR_SAMPLES = 6000;
const MAX_COLORS = 3;
const MIN_COLOR_SHARE = 0.1;

const luma = (r, g, b) => 0.299 * r + 0.587 * g + 0.114 * b;

/** The per-pixel median of a few frames ({ width, height, pixels } RGBA), RGB, as the background. */
export function medianBackground(frames) {
  const count = frames[0].width * frames[0].height;
  const background = new Float32Array(count * 3);
  const values = [];
  for (let pixel = 0; pixel < count; pixel++) {
    for (let channel = 0; channel < 3; channel++) {
      values.length = 0;
      for (const frame of frames) values.push(frame.pixels[pixel * 4 + channel]);
      values.sort((a, b) => a - b);
      const middle = values.length >> 1;
      background[pixel * 3 + channel] = values.length % 2 === 1 ? values[middle] : (values[middle - 1] + values[middle]) / 2;
    }
  }
  return background;
}

function groupMotion(frames) {
  let total = 0;
  let pairs = 0;
  for (let index = 1; index < frames.length; index++) {
    const a = frames[index - 1].pixels;
    const b = frames[index].pixels;
    let sum = 0;
    for (let byte = 0; byte < a.length; byte++) if ((byte & 3) !== 3) sum += Math.abs(a[byte] - b[byte]);
    total += sum / (a.length * 0.75);
    pairs++;
  }
  return pairs === 0 ? 0 : total / pairs;
}

function smooth(values) {
  return values.map((_, index) => {
    const window = values.slice(Math.max(0, index - 1), Math.min(values.length, index + 2));
    return window.reduce((sum, value) => sum + value, 0) / window.length;
  });
}

function hex(r, g, b) {
  return `#${[r, g, b].map((value) => Math.round(Math.max(0, Math.min(255, value))).toString(16).padStart(2, "0")).join("").toUpperCase()}`;
}

/** The main colours among packed RGB samples (median cut), as { hex, share }, most first. */
export function dominantColors(samples, boxes = 4) {
  if (samples.length === 0) return [];
  const component = (value, channel) => (value >> (16 - channel * 8)) & 255;
  let groups = [[...samples]];
  while (groups.length < boxes) {
    let widest = -1;
    let widestChannel = 0;
    let widestRange = 0;
    groups.forEach((group, index) => {
      if (group.length < 2) return;
      for (let channel = 0; channel < 3; channel++) {
        let low = 255;
        let high = 0;
        for (const value of group) {
          const part = component(value, channel);
          if (part < low) low = part;
          if (part > high) high = part;
        }
        if (high - low > widestRange) {
          widestRange = high - low;
          widest = index;
          widestChannel = channel;
        }
      }
    });
    if (widest < 0 || widestRange < 8) break;
    const group = groups[widest];
    const parts = group.map((value) => component(value, widestChannel));
    let low = 255;
    let high = 0;
    for (const part of parts) {
      if (part < low) low = part;
      if (part > high) high = part;
    }
    const middle = (low + high) / 2;
    const below = group.filter((_, index) => parts[index] < middle);
    const above = group.filter((_, index) => parts[index] >= middle);
    groups = [...groups.slice(0, widest), below, above, ...groups.slice(widest + 1)];
  }
  return groups
    .map((group) => {
      const mean = [0, 1, 2].map((channel) => group.reduce((sum, value) => sum + component(value, channel), 0) / group.length);
      return { hex: hex(mean[0], mean[1], mean[2]), share: group.length / samples.length };
    })
    .sort((a, b) => b.share - a.share);
}

function distinctColors(colors) {
  const merged = new Map();
  for (const color of colors) merged.set(color.hex, (merged.get(color.hex) ?? 0) + color.share);
  return [...merged].map(([hexValue, share]) => ({ hex: hexValue, share })).sort((a, b) => b.share - a.share);
}

/**
 * Measures a clip from its frames ({ time, width, height, pixels } RGBA), in time order, all
 * one size. Times are whatever the caller uses (effect seconds).
 */
export function analyseClip(frames) {
  const inactive = { active: false, cameraMoves: false, phases: [] };
  if (frames.length < 2) return inactive;
  const { width, height } = frames[0];
  const count = width * height;
  if (count === 0 || frames.some((frame) => frame.width !== width || frame.height !== height || frame.pixels.length !== count * 4)) {
    throw new Error("Every frame measured must be the same size, with four bytes a pixel.");
  }

  // The background: the quieter end of the clip, which is usually its start.
  const edge = Math.min(6, Math.max(2, Math.ceil(frames.length * 0.1)));
  const first = frames.slice(0, edge);
  const last = frames.slice(-edge);
  const reference = frames.length >= edge * 2 && groupMotion(first) > groupMotion(last) * 2 ? last : first;
  const background = medianBackground(reference);
  let backgroundLevel = 0;
  for (let pixel = 0; pixel < count; pixel++) {
    backgroundLevel += luma(background[pixel * 3], background[pixel * 3 + 1], background[pixel * 3 + 2]);
  }
  backgroundLevel /= count * 255;

  const activity = [];
  const areas = [];
  const levels = [];
  const masks = [];
  for (const frame of frames) {
    const mask = new Uint8Array(count);
    let change = 0;
    let changed = 0;
    let level = 0;
    for (let pixel = 0; pixel < count; pixel++) {
      const r = frame.pixels[pixel * 4];
      const g = frame.pixels[pixel * 4 + 1];
      const b = frame.pixels[pixel * 4 + 2];
      level += luma(r, g, b);
      const difference = Math.max(
        Math.abs(r - background[pixel * 3]),
        Math.abs(g - background[pixel * 3 + 1]),
        Math.abs(b - background[pixel * 3 + 2]),
      );
      if (difference > CHANGE_THRESHOLD) {
        mask[pixel] = 1;
        changed++;
        change += difference;
      }
    }
    masks.push(mask);
    activity.push(change / (count * 255));
    areas.push(changed / count);
    levels.push(level / (count * 255));
  }

  const cameraMoves = areas.filter((area) => area > WHOLE_FRAME).length >= frames.length * CAMERA_FRAMES;
  const brightest = levels.reduce((best, level, index) => (level > levels[best] ? index : best), 0);
  const brightness = levels[brightest] - backgroundLevel >= 0.03
    ? { time: frames[brightest].time, level: levels[brightest], before: backgroundLevel }
    : undefined;

  const curve = smooth(activity);
  const peakIndex = curve.reduce((best, value, index) => (value > curve[best] ? index : best), 0);
  const peakValue = curve[peakIndex];
  if (peakValue < MIN_ACTIVITY) return { ...inactive, ...(brightness === undefined ? {} : { brightness }) };
  if (cameraMoves) return { active: true, cameraMoves, phases: [], ...(brightness === undefined ? {} : { brightness }) };

  // The stretch above a share of the peak is the effect; its edges then walk out along the
  // rise and the fall for as long as something is still visible.
  const threshold = peakValue * EDGE_SHARE;
  let onsetIndex = curve.findIndex((value) => value >= threshold);
  let endIndex = onsetIndex;
  curve.forEach((value, index) => { if (value >= threshold) endIndex = index; });
  while (onsetIndex > 0 && curve[onsetIndex - 1] < curve[onsetIndex] && areas[onsetIndex - 1] >= MIN_VISIBLE_AREA) onsetIndex--;
  while (endIndex < frames.length - 1 && curve[endIndex + 1] < curve[endIndex] && areas[endIndex + 1] >= MIN_VISIBLE_AREA) endIndex++;
  let halfIndex = curve.findIndex((value, index) => index > peakIndex && value < peakValue * 0.5);
  if (halfIndex < 0) halfIndex = endIndex;

  const largestIndex = areas.reduce((best, area, index) => (index >= onsetIndex && index <= endIndex && area > areas[best] ? index : best), onsetIndex);
  const area = { largest: areas[largestIndex], time: frames[largestIndex].time, atOnset: areas[onsetIndex] };

  // Where it changes: pixels that changed in at least two active frames, boxed and padded.
  const activeFrames = endIndex - onsetIndex + 1;
  const hits = new Uint16Array(count);
  for (let index = onsetIndex; index <= endIndex; index++) {
    const mask = masks[index];
    for (let pixel = 0; pixel < count; pixel++) hits[pixel] += mask[pixel];
  }
  const needed = Math.max(2, Math.ceil(activeFrames * 0.05));
  let left = width;
  let top = height;
  let right = -1;
  let bottom = -1;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      if (hits[y * width + x] < needed) continue;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  let crop;
  if (right >= left && bottom >= top) {
    let boxWidth = right - left + 1;
    let boxHeight = bottom - top + 1;
    const padX = Math.max(boxWidth * 0.1, width * 0.04);
    const padY = Math.max(boxHeight * 0.1, height * 0.04);
    let x0 = left - padX;
    let y0 = top - padY;
    boxWidth += padX * 2;
    boxHeight += padY * 2;
    const grow = (size, minimum) => Math.max(size, minimum);
    const widened = grow(grow(boxWidth, width * 0.15), boxHeight / 2.5);
    const heightened = grow(grow(boxHeight, height * 0.15), boxWidth / 2.5);
    x0 -= (widened - boxWidth) / 2;
    y0 -= (heightened - boxHeight) / 2;
    boxWidth = Math.min(width, widened);
    boxHeight = Math.min(height, heightened);
    x0 = Math.max(0, Math.min(width - boxWidth, x0));
    y0 = Math.max(0, Math.min(height - boxHeight, y0));
    if ((boxWidth * boxHeight) / count < MAX_CROP_AREA) {
      const round = (value) => Math.round(value * 1000) / 1000;
      crop = { x: round(x0 / width), y: round(y0 / height), width: round(boxWidth / width), height: round(boxHeight / height) };
    }
  }

  // Colours of what changed, by phase: the build-up, the peak until it falls to half, the fade.
  const spans = [];
  if (peakIndex > onsetIndex) spans.push({ name: "build-up", from: onsetIndex, to: peakIndex - 1 });
  spans.push({ name: "peak", from: peakIndex, to: Math.max(peakIndex, halfIndex - 1) });
  if (endIndex >= halfIndex && halfIndex > peakIndex) spans.push({ name: "fade", from: halfIndex, to: endIndex });
  const phases = spans.map((span) => {
    let changedPixels = 0;
    for (let index = span.from; index <= span.to; index++) changedPixels += areas[index] * count;
    const step = Math.max(1, Math.floor(changedPixels / COLOR_SAMPLES));
    const samples = [];
    let seen = 0;
    for (let index = span.from; index <= span.to; index++) {
      const { pixels } = frames[index];
      const mask = masks[index];
      for (let pixel = 0; pixel < count; pixel++) {
        if (mask[pixel] === 0) continue;
        if (seen++ % step !== 0) continue;
        samples.push((pixels[pixel * 4] << 16) | (pixels[pixel * 4 + 1] << 8) | pixels[pixel * 4 + 2]);
      }
    }
    const colors = distinctColors(dominantColors(samples)).filter((color) => color.share >= MIN_COLOR_SHARE).slice(0, MAX_COLORS);
    return { name: span.name, from: frames[span.from].time, to: frames[span.to].time, colors };
  });

  return {
    active: true,
    onset: frames[onsetIndex].time,
    peak: frames[peakIndex].time,
    half: frames[halfIndex].time,
    end: frames[endIndex].time,
    ...(brightness === undefined ? {} : { brightness }),
    area,
    ...(crop === undefined ? {} : { crop }),
    cameraMoves,
    phases,
  };
}

const seconds = (value) => `${value.toFixed(2)} s`;
const percent = (value) => `${Math.round(value * 100)}%`;

/** The measurements as lines of text. Times are effect seconds. */
export function describeClipAnalysis(analysis) {
  const lines = ["Measured from the frames (approximate: compression, bloom and the background all shift these):"];
  if (analysis.brightness !== undefined) {
    const { time, level, before } = analysis.brightness;
    lines.push(`- Brightness: brightest at ${seconds(time)}, ${percent(level)} of white on average across the frame, from ${percent(before)} before the effect.`);
  }
  if (!analysis.active) {
    lines.push("- Change: none measurable between the frames; the clip may be still, or the effect too faint to measure. Read the frames instead.");
    return lines;
  }
  if (analysis.cameraMoves) {
    lines.push("- Change: the whole frame changes for much of the selection (a moving camera or a cut), so the effect was not timed or cropped; read its timing from the frames instead.");
    return lines;
  }
  const { onset, peak, half, end, area, crop } = analysis;
  if (onset !== undefined && peak !== undefined && half !== undefined && end !== undefined) {
    lines.push(`- Timing (how much of the frame differs from the background, and by how much): starts at ${seconds(onset)}, peaks at ${seconds(peak)}, falls to half by ${seconds(half)} and is gone by ${seconds(end)}.`);
  }
  if (area !== undefined) {
    const start = area.atOnset < 0.01 ? "growing from almost nothing" : `${percent(area.atOnset)} as it starts`;
    lines.push(`- Size: covers up to ${percent(area.largest)} of the frame, at ${seconds(area.time)} (${start}).`);
  }
  const colored = analysis.phases.filter((phase) => phase.colors.length > 0);
  if (colored.length > 0) {
    const parts = colored.map((phase) => `${phase.name} (${seconds(phase.from)}-${seconds(phase.to)}) ${phase.colors.map((color) => `${color.hex} ${percent(color.share)}`).join(", ")}`);
    lines.push(`- Colours of what changed, most first: ${parts.join("; ")}.`);
  }
  if (crop !== undefined) {
    lines.push(`- Framing: sheets are cropped to where the clip changes, ${percent(crop.width)} of the frame's width and ${percent(crop.height)} of its height, ${crop.x + crop.width / 2 < 0.4 ? "left of" : crop.x + crop.width / 2 > 0.6 ? "right of" : "around"} the middle.`);
  }
  return lines;
}

// ---------------------------------------------------------------------------------------------
// Colour check on captured frames.

const TONE_MIN_AREA = 0.003;
const TONE_MIN_FRAMES = 3;
/** Pale share above which an effect reads washed out: studied artists' videos reach 21%. */
export const WASHED_OUT = 0.4;
/** Blown-out share above which white is a blob rather than a highlight: studied videos reach 9%. */
export const BLOWN_OUT = 0.12;

function median(values) {
  const sorted = [...values].sort((a, b) => a - b);
  const middle = sorted.length >> 1;
  return sorted.length % 2 === 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

/**
 * The effect's colour across captured frames (same size, same still camera, the effect at
 * different moments): { frames, pale, vivid, deep, blown } shares; { gap, frames } when no
 * frame shows an effect on a still camera; undefined when there are too few frames.
 * The background is `empty` (a frame of the same view without the effect) when given, else the
 * per-pixel median of the frames, which only works when most frames show little of the effect.
 */
export function measureEffectTone(frames, empty) {
  if (frames.length < (empty ? 1 : TONE_MIN_FRAMES)) return undefined;
  const { width, height } = frames[0];
  if (width < 8 || height < 8 || [...frames, ...(empty ? [empty] : [])].some((frame) => frame.width !== width || frame.height !== height || frame.pixels.length < width * height * 4)) return undefined;
  const background = medianBackground(empty ? [empty] : frames);
  const count = width * height;
  const measured = [];
  let moved = 0;
  for (const frame of frames) {
    let effect = 0, pale = 0, vivid = 0, deep = 0, blown = 0;
    for (let pixel = 0; pixel < count; pixel++) {
      const r = frame.pixels[pixel * 4], g = frame.pixels[pixel * 4 + 1], b = frame.pixels[pixel * 4 + 2];
      const change = Math.max(Math.abs(r - background[pixel * 3]), Math.abs(g - background[pixel * 3 + 1]), Math.abs(b - background[pixel * 3 + 2]));
      if (change <= CHANGE_THRESHOLD) continue;
      effect++;
      const high = Math.max(r, g, b) / 255;
      const low = Math.min(r, g, b) / 255;
      const saturation = high > 0 ? (high - low) / high : 0;
      if (high > 0.6 && saturation < 0.35) pale++;
      if (high > 0.5 && saturation >= 0.5) vivid++;
      if (high <= 0.5 && saturation >= 0.4) deep++;
      if (low > 0.9) blown++;
    }
    const area = effect / count;
    if (area > WHOLE_FRAME) moved++;
    if (area < TONE_MIN_AREA || area > WHOLE_FRAME) continue;
    measured.push({ area, pale: pale / effect, vivid: vivid / effect, deep: deep / effect, blown: blown / effect });
  }
  if (measured.length === 0) return { gap: moved > 0 ? "camera-moved" : "nothing-showed", frames: frames.length };
  // The frames where the effect is largest carry its look; a fading tail would only dilute it.
  const busiest = [...measured].sort((a, b) => b.area - a.area).slice(0, Math.max(Math.min(3, measured.length), Math.ceil(measured.length / 3)));
  return {
    frames: busiest.length,
    pale: median(busiest.map((frame) => frame.pale)),
    vivid: median(busiest.map((frame) => frame.vivid)),
    deep: median(busiest.map((frame) => frame.deep)),
    blown: median(busiest.map((frame) => frame.blown)),
  };
}

/** The colour check as lines of text. */
export function describeEffectTone(tone) {
  if (tone === undefined) return ["Colour check: not measured. It needs at least 3 frames of the same size from one still camera, or 1 with --empty."];
  if ("gap" in tone) {
    if (tone.gap === "camera-moved") {
      return [`Colour check: not measured. The camera moved across these ${tone.frames} frames (they differ almost everywhere), so the effect cannot be told from the scene. Hold the camera still across the moments.`];
    }
    return [`Colour check: not measured. Across these ${tone.frames} frames nothing changes over even ${(TONE_MIN_AREA * 100).toFixed(1)}% of the picture: the effect is not on screen, too small from this camera, or the same in every frame. Find out why before judging the frames.`];
  }
  const lines = [
    `Colour check (the ${tone.frames === 1 ? "frame" : `${tone.frames} frames`} where the effect is largest, against the background): of the effect's pixels, ${percent(tone.pale)} are pale (white or pastel), ${percent(tone.vivid)} vivid colour, ${percent(tone.deep)} deep colour and ${percent(tone.blown)} blown out to pure white. Studied artists' effects run 2-21% pale, 35-90% vivid or deep and 0-9% blown out.`,
  ];
  if (tone.pale > WASHED_OUT) {
    lines.push("Unless it is meant to be pale (wind, mist, a white holy light), it is washed out, and that reads as cheap. Additive layers (LightEmission 1) only lighten what is behind them, so over a bright sky a colour turns pastel and then white. Carry the colour on solid layers (LightEmission 0, or below 0 for a dark rim) at Brightness 1-5, keep additive for thin highlights and small glows, and keep soft glows dim: Brightness about 1, Transparency 0.6 or more.");
  }
  if (tone.blown > BLOWN_OUT) {
    lines.push("Too much is pure white: a white highlight is a thin shape (a ring, sparks, a star's arms) at Brightness 1-2, not a soft ball or stacked glows. Overlapping additive layers add up to white; bring them down until the coloured shapes show.");
  }
  return lines;
}
