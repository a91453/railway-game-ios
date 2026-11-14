// Each triangle's colour under its photo texture (decision 725): only to
// tell the parts apart (roof tile, ridge, wall, column, stone), never kept.
// JPEG and PNG through tools/glb-to-m3dmodel's decoders; TGA here.
import { readFileSync } from 'node:fs';
import { decodeJpegAverages } from '../glb-to-m3dmodel/jpeg.mjs';
import { decodePng } from '../glb-to-m3dmodel/glb.mjs';

function decodeTga(bytes) {
  const idLength = bytes[0], type = bytes[2], width = bytes.readUInt16LE(12), height = bytes.readUInt16LE(14);
  const depth = bytes[16], descriptor = bytes[17], channels = depth / 8;
  if (![2, 3, 10, 11].includes(type) || ![1, 3, 4].includes(channels)) throw new Error(`TGA: type ${type}, depth ${depth}`);
  const pixels = Buffer.alloc(width * height * channels);
  let at = 18 + idLength;
  if (type === 2 || type === 3) bytes.copy(pixels, 0, at, at + pixels.length);
  else {
    let out = 0;
    while (out < pixels.length) {
      const head = bytes[at++], count = (head & 127) + 1;
      if (head & 128) { for (let i = 0; i < count; i++) bytes.copy(pixels, out + i * channels, at, at + channels); at += channels; }
      else { bytes.copy(pixels, out, at, at + count * channels); at += count * channels; }
      out += count * channels;
    }
  }
  const top = (descriptor & 32) !== 0;
  return { width, height, sample(x, y) {
    x = Math.max(0, Math.min(width - 1, Math.floor(x)));
    y = Math.max(0, Math.min(height - 1, Math.floor(y)));
    const row = top ? y : height - 1 - y, i = (row * width + x) * channels;
    if (channels === 1) return [pixels[i], pixels[i], pixels[i], 255];
    return [pixels[i + 2], pixels[i + 1], pixels[i], channels === 4 ? pixels[i + 3] : 255];
  } };
}

const cache = new Map();
export function bitmap(path) {
  if (cache.has(path)) return cache.get(path);
  let made = null;
  try {
    const bytes = readFileSync(path);
    if (bytes[0] === 0xff && bytes[1] === 0xd8) made = decodeJpegAverages(bytes);
    else if (bytes[0] === 0x89 && bytes[1] === 0x50) made = decodePng(bytes);
    else made = decodeTga(bytes);
  } catch (error) {
    process.stderr.write(`texture ${path}: ${error.message}; its material's colour is used\n`);
  }
  cache.set(path, made);
  return made;
}

// The triangle's mean colour over 21 points spread on it, 0..255 RGB, and
// its mean opacity 0..1 (a cut-out tree or lattice is mostly clear).
export function triangleColour(triangle) {
  const { material, uvs } = triangle;
  const image = material.image && uvs ? bitmap(material.image) : null;
  if (!image) return [...material.color.slice(0, 3).map(c => Math.round(c * 255)), material.color[3] ?? 1];
  const sum = [0, 0, 0, 0];
  let n = 0;
  for (let i = 0; i < 6; i++) for (let j = 0; j < 6 - i; j++) {
    const w = [(i + 1) / 9, (j + 1) / 9, (7 - i - j) / 9];
    const u = w[0] * uvs[0][0] + w[1] * uvs[1][0] + w[2] * uvs[2][0];
    const v = w[0] * uvs[0][1] + w[1] * uvs[1][1] + w[2] * uvs[2][1];
    const wrap = t => ((t % 1) + 1) % 1;
    // COLLADA's v counts up from the image's bottom row.
    const rgba = image.sample(wrap(u) * (image.width - 1), (1 - wrap(v)) * (image.height - 1));
    for (let k = 0; k < 4; k++) sum[k] += rgba[k];
    n++;
  }
  return [...sum.slice(0, 3).map(s => Math.round(s / n)), sum[3] / n / 255];
}
