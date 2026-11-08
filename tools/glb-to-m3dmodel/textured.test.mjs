// Decision 653: the textured (version 2) writer, on GLBs made here only.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { convertTextured, maximumTextureBytes, textureKind } from './textured.mjs';
import { makeFixture } from './make-fixture.mjs';

const tinyTextured = fileURLToPath(new URL('fixtures/tiny-textured.m3dmodel', import.meta.url));
const png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
const ktx = Buffer.from([0xab, 0x4b, 0x54, 0x58, 0x20, 0x31, 0x31, 0xbb, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3, 4]);

function read(output) {
  const count = output.readUInt32LE(8), recordLength = output.readUInt32LE(12);
  const kind = output.readUInt32LE(16), textureLength = output.readUInt32LE(20);
  const pad = n => Math.ceil(n / 4) * 4, textureAt = 24 + pad(recordLength), body = textureAt + pad(textureLength);
  assert.equal(output.length, body + count * 112);
  const triangles = Array.from({ length: count }, (_, i) => {
    const at = body + i * 112;
    return { flags: output.readUInt32LE(at), corners: [0, 1, 2].map(k => {
      const values = Array.from({ length: 8 }, (_, j) => output.readFloatLE(at + 4 + k * 36 + j * 4));
      return { point: values.slice(0, 3), normal: values.slice(3, 6), uv: values.slice(6, 8), colour: output.readUInt32LE(at + 4 + k * 36 + 32) };
    }) };
  });
  return { version: output.readUInt16LE(4), kind, texture: output.subarray(textureAt, textureAt + textureLength),
    provenance: JSON.parse(output.toString('utf8', 24, 24 + recordLength)), triangles };
}

// A GLB of one square, its normals and u, v its own, under a node that
// stretches it and, optionally, mirrors it.
function square({ scale = [1, 1, 1], wrap, uvs = [0, 0, 1, 0, 1, 1, 0, 1], images = 1 } = {}) {
  const parts = [], views = [];
  const add = buffer => {
    const offset = parts.reduce((sum, part) => sum + part.length, 0), padded = Buffer.alloc(Math.ceil(buffer.length / 4) * 4);
    buffer.copy(padded); parts.push(padded); views.push({ buffer: 0, byteOffset: offset, byteLength: buffer.length });
    return views.length - 1;
  };
  const floats = values => { const b = Buffer.alloc(values.length * 4); values.forEach((v, i) => b.writeFloatLE(v, i * 4)); return b; };
  const position = add(floats([0, 0, 0, 2, 0, 0, 2, 1, 0, 0, 1, 0]));
  const s = Math.SQRT1_2;
  const normal = add(floats([0, s, s, 0, s, s, 0, 0, 1, 0, 0, 1]));
  const uv = add(floats(uvs));
  const index = add(Buffer.from(new Uint16Array([0, 1, 2, 0, 2, 3]).buffer));
  const image = add(Buffer.from([...png, 0, 0, 0, 13]));
  const binary = Buffer.concat(parts);
  const json = {
    asset: { version: '2.0', generator: 'textured test' }, buffers: [{ byteLength: binary.length }], bufferViews: views,
    accessors: [
      { bufferView: position, componentType: 5126, count: 4, type: 'VEC3' },
      { bufferView: normal, componentType: 5126, count: 4, type: 'VEC3' },
      { bufferView: uv, componentType: 5126, count: 4, type: 'VEC2' },
      { bufferView: index, componentType: 5123, count: 6, type: 'SCALAR' },
    ],
    images: Array.from({ length: images }, () => ({ bufferView: image, mimeType: 'image/png' })),
    samplers: wrap ? [{ wrapS: wrap, wrapT: wrap }] : [],
    textures: Array.from({ length: images }, (_, i) => ({ source: i, ...(wrap ? { sampler: 0 } : {}) })),
    materials: Array.from({ length: images }, (_, i) => ({ name: `paint ${i}`, pbrMetallicRoughness: { baseColorTexture: { index: i }, baseColorFactor: [1, 0.5, 0.25, 1] } })),
    meshes: [{ primitives: Array.from({ length: images }, (_, i) => ({ attributes: { POSITION: 0, NORMAL: 1, TEXCOORD_0: 2 }, indices: 3, material: i })) }],
    nodes: [{ mesh: 0, scale }], scenes: [{ nodes: [0] }], scene: 0,
  };
  const text = Buffer.from(JSON.stringify(json)), jsonPadded = Buffer.alloc(Math.ceil(text.length / 4) * 4, 32);
  text.copy(jsonPadded);
  const header = Buffer.alloc(12), chunk1 = Buffer.alloc(8), chunk2 = Buffer.alloc(8);
  header.write('glTF'); header.writeUInt32LE(2, 4); header.writeUInt32LE(28 + jsonPadded.length + binary.length, 8);
  chunk1.writeUInt32LE(jsonPadded.length); chunk1.write('JSON', 4);
  chunk2.writeUInt32LE(binary.length); chunk2.write('BIN\0', 4);
  return Buffer.concat([header, chunk1, jsonPadded, chunk2, binary]);
}

const options = { modelId: 'square', front: '+x', units: 'meters', sourceRecord: { kind: 'test', reference: 'made in textured.test.mjs' } };

test('the tiny fixture converts to version 2, its PNG kept and its headlight untextured but lit', () => {
  const result = convertTextured(makeFixture(), { modelId: 'fixture', front: '-x', lengthMeters: 12 });
  assert.deepEqual(result.output, readFileSync(tinyTextured));
  const file = read(result.output);
  assert.equal(file.version, 2);
  assert.equal(file.kind, 1);
  assert.deepEqual([...file.texture.subarray(0, 8)], png);
  assert.equal(file.provenance.asset.generator, 'Meshy fixture');
  assert.deepEqual(file.triangles.map(t => t.flags), [8, 1]);
  assert.deepEqual(file.triangles[0].corners.map(c => c.uv), [[0, 0], [1, 0], [1, 1]]);
  assert.equal(file.triangles[0].corners[0].colour, 0xffffffff, 'a texture with no factor is tinted white');
  assert.equal(file.triangles[1].corners[0].colour, 0xff00ffff, 'the headlight keeps its yellow factor');
  assert.equal(file.triangles[0].corners[0].point[0], 6, '-x GLB front becomes +x');
});

test('normals turn with the front and stay at right angles to a stretched surface', () => {
  const file = read(convertTextured(square({ scale: [1, 1, 3] }), options).output);
  assert.equal(file.triangles.length, 2);
  assert.ok(file.triangles.every(t => t.flags === 8));
  // glTF (0, √½, √½) under scale z ×3 is (0, 3, 1)/√10 by the inverse transpose; '+x' turns (x, y, z) to (x, -z, y).
  const [nx, ny, nz] = file.triangles[0].corners[0].normal;
  assert.ok(Math.abs(nx) < 1e-6 && Math.abs(ny + 1 / Math.sqrt(10)) < 1e-6 && Math.abs(nz - 3 / Math.sqrt(10)) < 1e-6, `${nx} ${ny} ${nz}`);
  assert.deepEqual(file.triangles[0].corners[2].normal.map(v => Math.round(v * 1e6) / 1e6), [0, -1, 0]);
  assert.equal(file.triangles[0].corners[0].colour, 0xff4080ff, 'the base color factor tints the texture');
});

test('a mirroring node keeps the faces turned outwards', () => {
  const plain = read(convertTextured(square(), options).output), mirrored = read(convertTextured(square({ scale: [-1, 1, 1] }), options).output);
  const facing = t => {
    const [a, b, c] = t.corners.map(k => k.point);
    const u = b.map((v, i) => v - a[i]), w = c.map((v, i) => v - a[i]);
    const n = [u[1] * w[2] - u[2] * w[1], u[2] * w[0] - u[0] * w[2], u[0] * w[1] - u[1] * w[0]];
    return n[0] * t.corners[0].normal[0] + n[1] * t.corners[0].normal[1] + n[2] * t.corners[0].normal[2];
  };
  assert.ok(plain.triangles.every(t => facing(t) > 0));
  assert.ok(mirrored.triangles.every(t => facing(t) > 0), 'winding swapped back with the mirror');
  assert.deepEqual(mirrored.triangles[0].corners[1].uv, plain.triangles[0].corners[2].uv, 'u, v swapped with their corners');
});

test('a KTX given in place of the image is kept, signed as KTX', () => {
  const file = read(convertTextured(square(), { ...options, texture: ktx }).output);
  assert.equal(file.kind, 3);
  assert.deepEqual(file.texture, ktx);
  assert.equal(textureKind(ktx), 3);
});

test('what a textured model cannot draw the same is refused', () => {
  assert.throws(() => convertTextured(square({ images: 2 }), options), /more than one base color image/);
  assert.throws(() => convertTextured(square({ wrap: 33071, uvs: [0, 0, 2, 0, 2, 1, 0, 1] }), options), /clamped or mirrored/);
  assert.doesNotThrow(() => convertTextured(square({ wrap: 33071 }), options), 'clamped within 0…1 draws the same');
  assert.throws(() => convertTextured(square(), { ...options, texture: Buffer.from('not an image') }), /not a PNG, JPEG or KTX/);
  assert.throws(() => convertTextured(square(), { ...options, texture: Buffer.concat([ktx, Buffer.alloc(maximumTextureBytes)]) }), /at most/);
  assert.throws(() => convertTextured(square(), { ...options, front: 'up' }), /Unknown front/);
});
