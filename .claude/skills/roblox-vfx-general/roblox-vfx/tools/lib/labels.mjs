// Labels drawn onto a contact sheet's frames: a frame's number and time, in a small pixel
// font, white on a black box in the frame's top-left corner, so a frame can be named by
// reading it rather than by counting cells.
// Ported from Roqer (https://github.com/S4US/Roqer, apps/desktop/runtime/sheet-labels.ts),
// AGPL-3.0-or-later; see ../LICENSE.

const GLYPHS = {
  "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
  "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
  "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
  "3": ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
  "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
  "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
  "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
  "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
  "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
  "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
  ".": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
  "s": ["00000", "00000", "01110", "10000", "01110", "00001", "11110"],
  "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
  "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
  "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
  " ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
};

const GLYPH_WIDTH = 5;
const GLYPH_HEIGHT = 7;
const SPACING = 1;
const PADDING = 2;

/** A label's box, in pixels, at `scale` pixels to a font pixel. */
export function labelSize(text, scale) {
  const characters = Math.max(1, text.length);
  return {
    width: (characters * GLYPH_WIDTH + (characters - 1) * SPACING + PADDING * 2) * scale,
    height: (GLYPH_HEIGHT + PADDING * 2) * scale,
  };
}

/** The font scale for a tile `tileWidth` pixels wide. */
export function labelScale(tileWidth) {
  return tileWidth >= 400 ? 3 : 2;
}

/** Draws `text` at `left`, `top` into an RGBA bitmap, clipped to it. Unknown characters draw as spaces. */
export function drawLabel(bitmap, width, height, left, top, text, scale) {
  const size = labelSize(text, scale);
  const put = (x, y, value) => {
    if (x < 0 || y < 0 || x >= width || y >= height) return;
    const offset = (y * width + x) * 4;
    bitmap[offset] = value;
    bitmap[offset + 1] = value;
    bitmap[offset + 2] = value;
    bitmap[offset + 3] = 255;
  };
  for (let y = 0; y < size.height; y++) {
    for (let x = 0; x < size.width; x++) put(left + x, top + y, 0);
  }
  [...text].forEach((character, index) => {
    const glyph = GLYPHS[character] ?? GLYPHS[" "];
    const originX = left + (PADDING + index * (GLYPH_WIDTH + SPACING)) * scale;
    const originY = top + PADDING * scale;
    glyph.forEach((row, rowIndex) => {
      for (let column = 0; column < GLYPH_WIDTH; column++) {
        if (row[column] !== "1") continue;
        for (let dy = 0; dy < scale; dy++) {
          for (let dx = 0; dx < scale; dx++) put(originX + column * scale + dx, originY + rowIndex * scale + dy, 255);
        }
      }
    });
  });
}

/** "3 0.25s": a frame's number and its time in seconds. */
export function frameLabel(number, seconds, prefix = "") {
  return `${prefix}${number} ${seconds.toFixed(2)}s`;
}
