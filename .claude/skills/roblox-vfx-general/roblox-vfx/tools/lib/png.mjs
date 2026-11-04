// PNG decoding and encoding, with no dependencies.
// Ported from Roqer (https://github.com/S4US/Roqer, apps/desktop/runtime/flipbook-sheet.ts),
// AGPL-3.0-or-later; see ../LICENSE. Changes: plain JavaScript, plus an encoder.
import { deflateSync, inflateSync } from "node:zlib";

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const CHANNELS = { 0: 1, 2: 3, 4: 2, 6: 4 };
const MAX_PIXELS = 4096 * 4096;

/**
 * Decodes greyscale, grey-alpha, RGB or RGBA PNGs at 8 or 16 bits, not interlaced.
 * Returns { width, height, rgba, hasAlpha } with rgba as 8-bit RGBA rows, top row first.
 */
export function decodePng(bytes) {
  if (bytes.length < 8 || !bytes.subarray(0, 8).equals(PNG_SIGNATURE)) throw new Error("Not a PNG file.");
  let offset = 8;
  let width = 0;
  let height = 0;
  let depth = 0;
  let colorType = -1;
  const data = [];
  while (offset + 8 <= bytes.length) {
    const length = bytes.readUInt32BE(offset);
    const type = bytes.toString("latin1", offset + 4, offset + 8);
    const start = offset + 8;
    if (start + length + 4 > bytes.length) throw new Error("The PNG is truncated.");
    const chunk = bytes.subarray(start, start + length);
    if (type === "IHDR") {
      width = chunk.readUInt32BE(0);
      height = chunk.readUInt32BE(4);
      depth = chunk[8];
      colorType = chunk[9];
      if (chunk[12] !== 0) throw new Error("The PNG is interlaced; save it without interlacing.");
      if (colorType === 3) throw new Error("The PNG uses a colour palette; save it as RGBA.");
      if (CHANNELS[colorType] === undefined || (depth !== 8 && depth !== 16)) {
        throw new Error(`The PNG has colour type ${colorType} at ${depth} bits; save it as 8-bit RGBA.`);
      }
      if (width < 1 || height < 1 || width * height > MAX_PIXELS) throw new Error(`The PNG is ${width} x ${height}, too large to read.`);
    } else if (type === "IDAT") {
      data.push(chunk);
    } else if (type === "IEND") {
      break;
    }
    offset = start + length + 4;
  }
  if (colorType < 0) throw new Error("The PNG has no header.");
  const channels = CHANNELS[colorType];
  const bytesPerPixel = channels * (depth / 8);
  const stride = width * bytesPerPixel;
  const raw = inflateSync(Buffer.concat(data), { maxOutputLength: (stride + 1) * height + 1 });
  if (raw.length < (stride + 1) * height) throw new Error("The PNG's image data is shorter than its size says.");
  const pixels = Buffer.alloc(stride * height);
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    const line = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    const out = pixels.subarray(y * stride, (y + 1) * stride);
    const above = y > 0 ? pixels.subarray((y - 1) * stride, y * stride) : undefined;
    for (let x = 0; x < stride; x++) {
      const left = x >= bytesPerPixel ? out[x - bytesPerPixel] : 0;
      const up = above ? above[x] : 0;
      const corner = above && x >= bytesPerPixel ? above[x - bytesPerPixel] : 0;
      let value = line[x];
      if (filter === 1) value += left;
      else if (filter === 2) value += up;
      else if (filter === 3) value += (left + up) >> 1;
      else if (filter === 4) {
        const p = left + up - corner;
        const pa = Math.abs(p - left);
        const pb = Math.abs(p - up);
        const pc = Math.abs(p - corner);
        value += pa <= pb && pa <= pc ? left : pb <= pc ? up : corner;
      } else if (filter !== 0) throw new Error(`The PNG uses an unknown filter (${filter}).`);
      out[x] = value & 0xff;
    }
  }
  const rgba = Buffer.alloc(width * height * 4);
  const step = depth / 8;
  for (let i = 0; i < width * height; i++) {
    const at = (channel) => pixels[i * bytesPerPixel + channel * step];
    const grey = channels <= 2;
    rgba[i * 4] = at(0);
    rgba[i * 4 + 1] = grey ? at(0) : at(1);
    rgba[i * 4 + 2] = grey ? at(0) : at(2);
    rgba[i * 4 + 3] = channels === 2 ? at(1) : channels === 4 ? at(3) : 255;
  }
  return { width, height, rgba, hasAlpha: channels === 2 || channels === 4 };
}

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  return table;
})();

function crc32(buffer) {
  let c = 0xffffffff;
  for (const byte of buffer) c = CRC_TABLE[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const head = Buffer.alloc(8);
  head.writeUInt32BE(data.length, 0);
  head.write(type, 4, "latin1");
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([head.subarray(4), data])), 0);
  return Buffer.concat([head, data, crc]);
}

/** Encodes 8-bit RGBA rows, top row first, as a PNG. */
export function encodePng(width, height, rgba) {
  const stride = width * 4;
  const rows = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y++) {
    rows[y * (stride + 1)] = 0;
    rgba.copy(rows, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
  }
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = 6;
  return Buffer.concat([PNG_SIGNATURE, chunk("IHDR", header), chunk("IDAT", deflateSync(rows, { level: 6 })), chunk("IEND", Buffer.alloc(0))]);
}
