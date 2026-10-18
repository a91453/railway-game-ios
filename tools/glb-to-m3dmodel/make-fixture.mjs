// A tiny GLB made here, so the converter test owns its geometry, texture,
// node transform, and provenance instead of depending on a generated asset.
import { deflateSync } from 'node:zlib';
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

function crc32(bytes) {
  let crc = -1;
  for (const byte of bytes) {
    crc ^= byte;
    for (let i = 0; i < 8; i++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  return (crc ^ -1) >>> 0;
}

function pngChunk(name, data) {
  const label = Buffer.from(name), length = Buffer.alloc(4), checksum = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  checksum.writeUInt32BE(crc32(Buffer.concat([label, data])));
  return Buffer.concat([length, label, data, checksum]);
}

function bluePng() {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(2, 0); header.writeUInt32BE(2, 4);
  header[8] = 8; header[9] = 2;
  const row = Buffer.from([0, 20, 90, 200, 20, 90, 200]);
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    pngChunk('IHDR', header), pngChunk('IDAT', deflateSync(Buffer.concat([row, row]))), pngChunk('IEND', Buffer.alloc(0))]);
}

export function makeFixture({ ai = true } = {}) {
  const data = [], views = [];
  function add(buffer, target) {
    const offset = data.reduce((sum, part) => sum + part.length, 0);
    const padded = Buffer.alloc(Math.ceil(buffer.length / 4) * 4);
    buffer.copy(padded);
    data.push(padded);
    views.push({ buffer: 0, byteOffset: offset, byteLength: buffer.length, ...(target ? { target } : {}) });
    return views.length - 1;
  }
  function floats(values) {
    const result = Buffer.alloc(values.length * 4);
    values.forEach((value, i) => result.writeFloatLE(value, i * 4));
    return result;
  }
  const position1 = add(floats([-1, 0, 0, 1, 0, 0, 1, 1, 0]), 34962);
  const uv = add(floats([0, 0, 1, 0, 1, 1]), 34962);
  const indices1 = add(Buffer.from([0, 0, 1, 0, 2, 0]), 34963);
  const position2 = add(floats([-1, 0, 1, 1, 0, 1, 1, 1, 1, -1, 0, 0, 0, 0, 0, 1, 0, 0]), 34962);
  const indices2 = add(Buffer.from([0, 0, 1, 0, 2, 0, 3, 0, 4, 0, 5, 0]), 34963);
  const png = add(bluePng());
  const binary = Buffer.concat(data);
  const json = {
    asset: { version: '2.0', generator: ai ? 'Meshy fixture' : 'plain fixture' },
    ...(ai ? { extras: { aiGenerated: true } } : {}),
    buffers: [{ byteLength: binary.length }], bufferViews: views,
    accessors: [
      { bufferView: position1, componentType: 5126, count: 3, type: 'VEC3' },
      { bufferView: uv, componentType: 5126, count: 3, type: 'VEC2' },
      { bufferView: indices1, componentType: 5123, count: 3, type: 'SCALAR' },
      { bufferView: position2, componentType: 5126, count: 6, type: 'VEC3' },
      { bufferView: indices2, componentType: 5123, count: 6, type: 'SCALAR' },
    ],
    images: [{ bufferView: png, mimeType: 'image/png' }], textures: [{ source: 0 }],
    materials: [
      { name: 'painted blue', pbrMetallicRoughness: { baseColorTexture: { index: 0 } } },
      { name: 'headlight', pbrMetallicRoughness: { baseColorFactor: [1, 1, 0, 1] }, emissiveFactor: [1, 1, 0] },
    ],
    meshes: [{ primitives: [
      { attributes: { POSITION: 0, TEXCOORD_0: 1 }, indices: 2, material: 0 },
      { attributes: { POSITION: 3 }, indices: 4, material: 1 },
    ] }],
    nodes: [{ mesh: 0, translation: [2, 0, 0] }], scenes: [{ nodes: [0] }], scene: 0,
  };
  const encoded = Buffer.from(JSON.stringify(json)), jsonPadded = Buffer.alloc(Math.ceil(encoded.length / 4) * 4, 32);
  encoded.copy(jsonPadded);
  const header = Buffer.alloc(12), chunk1 = Buffer.alloc(8), chunk2 = Buffer.alloc(8);
  header.write('glTF'); header.writeUInt32LE(2, 4);
  header.writeUInt32LE(12 + 8 + jsonPadded.length + 8 + binary.length, 8);
  chunk1.writeUInt32LE(jsonPadded.length); chunk1.write('JSON', 4);
  chunk2.writeUInt32LE(binary.length); chunk2.write('BIN\0', 4);
  return Buffer.concat([header, chunk1, jsonPadded, chunk2, binary]);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const output = fileURLToPath(new URL('fixtures/tiny.glb', import.meta.url));
  writeFileSync(output, makeFixture());
  console.log(output);
}
