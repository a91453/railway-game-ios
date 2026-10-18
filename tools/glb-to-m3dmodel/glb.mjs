import { inflateSync } from 'node:zlib';
import { decodeJpegAverages } from './jpeg.mjs';

export function readGlb(bytes) {
  if (bytes.length < 20 || bytes.toString('ascii', 0, 4) !== 'glTF' || bytes.readUInt32LE(4) !== 2 ||
      bytes.readUInt32LE(8) !== bytes.length) throw new Error('Expected a glTF 2.0 GLB');
  let at = 12, json, binary;
  while (at < bytes.length) {
    if (at + 8 > bytes.length) throw new Error('GLB: truncated chunk');
    const length = bytes.readUInt32LE(at), type = bytes.toString('ascii', at + 4, at + 8);
    at += 8;
    if (at + length > bytes.length) throw new Error('GLB: bad chunk length');
    if (type === 'JSON') json = JSON.parse(bytes.toString('utf8', at, at + length));
    if (type === 'BIN\0') binary = bytes.subarray(at, at + length);
    at += length;
  }
  if (!json || !binary || json.asset?.version !== '2.0') throw new Error('GLB: missing JSON, BIN, or glTF 2.0 asset');
  if (json.extensionsRequired?.length) throw new Error(`GLB: unsupported required extensions: ${json.extensionsRequired.join(', ')}`);
  if (json.buffers?.length !== 1 || json.buffers[0].uri || json.buffers[0].byteLength > binary.length) {
    throw new Error('GLB: expected one embedded binary buffer');
  }
  return { json, binary };
}

const types = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4 };
const components = { 5120: [1, true], 5121: [1, false], 5122: [2, true], 5123: [2, false], 5125: [4, false], 5126: [4, true] };

export function accessor(gltf, index) {
  const { json, binary } = gltf;
  const entry = json.accessors?.[index];
  if (!entry || entry.sparse || entry.bufferView === undefined) throw new Error(`GLB: unsupported accessor ${index}`);
  const view = json.bufferViews?.[entry.bufferView];
  if (!view || view.buffer !== 0) throw new Error(`GLB: bad buffer view in accessor ${index}`);
  const dimensions = types[entry.type], info = components[entry.componentType];
  if (!dimensions || !info) throw new Error(`GLB: unsupported accessor type ${index}`);
  const [size, signed] = info, itemSize = size * dimensions, stride = view.byteStride ?? itemSize;
  const start = (view.byteOffset ?? 0) + (entry.byteOffset ?? 0);
  if (!Number.isSafeInteger(entry.count) || entry.count < 0 || stride < itemSize ||
      start + Math.max(0, entry.count - 1) * stride + itemSize > (view.byteOffset ?? 0) + view.byteLength ||
      start + Math.max(0, entry.count - 1) * stride + itemSize > binary.length) {
    throw new Error(`GLB: accessor ${index} exceeds its buffer view`);
  }
  function read(at) {
    switch (entry.componentType) {
      case 5120: return binary.readInt8(at);
      case 5121: return binary.readUInt8(at);
      case 5122: return binary.readInt16LE(at);
      case 5123: return binary.readUInt16LE(at);
      case 5125: return binary.readUInt32LE(at);
      case 5126: return binary.readFloatLE(at);
      default: throw new Error('GLB: unreachable component type');
    }
  }
  return Array.from({ length: entry.count }, (_, i) => Array.from({ length: dimensions }, (_, j) => {
    const value = read(start + i * stride + j * size);
    if (!entry.normalized || entry.componentType === 5126) return value;
    const bits = size * 8;
    return signed ? Math.max(-1, value / (2 ** (bits - 1) - 1)) : value / (2 ** bits - 1);
  }));
}

export function image(gltf, index) {
  const { json, binary } = gltf;
  const entry = json.images?.[index];
  if (!entry) throw new Error(`GLB: missing image ${index}`);
  let data;
  if (entry.bufferView !== undefined) {
    const view = json.bufferViews?.[entry.bufferView];
    if (!view || view.buffer !== 0 || (view.byteOffset ?? 0) + view.byteLength > binary.length) {
      throw new Error(`GLB: invalid image buffer view ${entry.bufferView}`);
    }
    data = binary.subarray(view.byteOffset ?? 0, (view.byteOffset ?? 0) + view.byteLength);
  } else if (entry.uri?.startsWith('data:')) {
    const match = entry.uri.match(/^data:([^;,]+);base64,(.*)$/);
    if (!match) throw new Error('GLB: unsupported image data URI');
    data = Buffer.from(match[2], 'base64');
  } else throw new Error('GLB: external images are unsupported');
  if (entry.mimeType === 'image/jpeg') return decodeJpegAverages(data);
  if (entry.mimeType === 'image/png') return decodePng(data);
  throw new Error(`GLB: unsupported image type ${entry.mimeType}`);
}

function decodePng(bytes) {
  if (!bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) throw new Error('PNG: bad signature');
  let at = 8, width, height, depth, color, interlace;
  const chunks = [];
  while (at + 12 <= bytes.length) {
    const length = bytes.readUInt32BE(at), type = bytes.toString('ascii', at + 4, at + 8);
    if (at + 12 + length > bytes.length) throw new Error('PNG: truncated chunk');
    const data = bytes.subarray(at + 8, at + 8 + length);
    if (type === 'IHDR') {
      width = data.readUInt32BE(0); height = data.readUInt32BE(4);
      depth = data[8]; color = data[9]; interlace = data[12];
    } else if (type === 'IDAT') chunks.push(data);
    else if (type === 'IEND') break;
    at += length + 12;
  }
  const channels = { 0: 1, 2: 3, 4: 2, 6: 4 }[color];
  if (!width || !height || !channels || depth !== 8 || interlace !== 0) {
    throw new Error('PNG: only non-interlaced 8-bit gray, RGB, and RGBA images are supported');
  }
  const rowSize = width * channels, raw = inflateSync(Buffer.concat(chunks));
  if (raw.length !== height * (rowSize + 1)) throw new Error('PNG: bad data length');
  const pixels = Buffer.alloc(rowSize * height);
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (rowSize + 1)];
    for (let x = 0; x < rowSize; x++) {
      const a = x >= channels ? pixels[y * rowSize + x - channels] : 0;
      const b = y ? pixels[(y - 1) * rowSize + x] : 0;
      const c = x >= channels && y ? pixels[(y - 1) * rowSize + x - channels] : 0;
      let predictor;
      if (filter === 0) predictor = 0;
      else if (filter === 1) predictor = a;
      else if (filter === 2) predictor = b;
      else if (filter === 3) predictor = Math.floor((a + b) / 2);
      else if (filter === 4) {
        const p = a + b - c, da = Math.abs(p - a), db = Math.abs(p - b), dc = Math.abs(p - c);
        predictor = da <= db && da <= dc ? a : db <= dc ? b : c;
      } else throw new Error(`PNG: unsupported filter ${filter}`);
      pixels[y * rowSize + x] = (raw[y * (rowSize + 1) + 1 + x] + predictor) & 255;
    }
  }
  return { width, height, sample(x, y) {
    x = Math.max(0, Math.min(width - 1, Math.floor(x)));
    y = Math.max(0, Math.min(height - 1, Math.floor(y)));
    const i = (y * width + x) * channels;
    if (color === 0) return [pixels[i], pixels[i], pixels[i], 255];
    if (color === 4) return [pixels[i], pixels[i], pixels[i], pixels[i + 1]];
    return [pixels[i], pixels[i + 1], pixels[i + 2], color === 6 ? pixels[i + 3] : 255];
  } };
}

export function scenePrimitives(gltf) {
  const { json } = gltf, scene = json.scenes?.[json.scene ?? 0];
  if (!scene) throw new Error('GLB: no scene');
  const result = [];
  const identity = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
  function multiply(a, b) {
    const out = Array(16).fill(0);
    for (let c = 0; c < 4; c++) for (let r = 0; r < 4; r++) for (let k = 0; k < 4; k++) out[c * 4 + r] += a[k * 4 + r] * b[c * 4 + k];
    return out;
  }
  function transform(node) {
    if (node.matrix) return node.matrix;
    const [x, y, z, w] = node.rotation ?? [0, 0, 0, 1], [sx, sy, sz] = node.scale ?? [1, 1, 1];
    const [tx, ty, tz] = node.translation ?? [0, 0, 0];
    return [(1 - 2 * (y * y + z * z)) * sx, 2 * (x * y + z * w) * sx, 2 * (x * z - y * w) * sx, 0,
      2 * (x * y - z * w) * sy, (1 - 2 * (x * x + z * z)) * sy, 2 * (y * z + x * w) * sy, 0,
      2 * (x * z + y * w) * sz, 2 * (y * z - x * w) * sz, (1 - 2 * (x * x + y * y)) * sz, 0,
      tx, ty, tz, 1];
  }
  function visit(index, parent, stack) {
    if (stack.has(index)) throw new Error('GLB: node cycle');
    const node = json.nodes?.[index];
    if (!node) throw new Error(`GLB: missing node ${index}`);
    const matrix = multiply(parent, transform(node)), next = new Set(stack).add(index);
    if (node.mesh !== undefined) {
      const mesh = json.meshes?.[node.mesh];
      if (!mesh) throw new Error(`GLB: missing mesh ${node.mesh}`);
      for (const primitive of mesh.primitives ?? []) result.push({ primitive, matrix, name: mesh.name ?? node.name ?? '' });
    }
    for (const child of node.children ?? []) visit(child, matrix, next);
  }
  for (const index of scene.nodes ?? []) visit(index, identity, new Set());
  return result;
}

export function applyMatrix(matrix, point) {
  const [x, y, z] = point;
  const w = matrix[3] * x + matrix[7] * y + matrix[11] * z + matrix[15];
  if (!Number.isFinite(w) || w === 0) throw new Error('GLB: invalid node transform');
  return [(matrix[0] * x + matrix[4] * y + matrix[8] * z + matrix[12]) / w,
    (matrix[1] * x + matrix[5] * y + matrix[9] * z + matrix[13]) / w,
    (matrix[2] * x + matrix[6] * y + matrix[10] * z + matrix[14]) / w];
}
