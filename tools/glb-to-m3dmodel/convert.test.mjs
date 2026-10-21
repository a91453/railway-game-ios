import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { deflateSync } from 'node:zlib';
import { convert } from './convert.mjs';
import { image, readGlb } from './glb.mjs';
import { makeFixture } from './make-fixture.mjs';

const fixture = fileURLToPath(new URL('fixtures/tiny.glb', import.meta.url));
const expected = fileURLToPath(new URL('fixtures/tiny.m3dmodel', import.meta.url));
const bus = fileURLToPath(new URL('../../docs/art/meshy-city-bus-2026-10-18/city-bus.glb', import.meta.url));

function header(bytes) {
  const count = bytes.readUInt32LE(8), length = bytes.readUInt32LE(12), triangles = 16 + Math.ceil(length / 4) * 4;
  return { count, provenance: JSON.parse(bytes.toString('utf8', 16, 16 + length)), triangles };
}

test('own GLB fixture converts to the reader format, including texture, front, glow and provenance', () => {
  const source = readFileSync(fixture);
  assert.deepEqual(source, makeFixture());
  const { output, triangles, colors, glowingTriangles } = convert(source, { modelId: 'fixture', front: '-x', lengthMeters: 12 });
  assert.deepEqual(output, readFileSync(expected));
  assert.equal(triangles, 2); // the third triangle has zero area
  assert.equal(colors, 2);
  assert.equal(glowingTriangles, 1);
  assert.equal(output.toString('ascii', 0, 4), 'M3DM');
  assert.equal(output.readUInt16LE(4), 1);
  assert.equal(output.length, header(output).triangles + triangles * 52);
  const { provenance, triangles: start } = header(output);
  assert.equal(provenance.asset.generator, 'Meshy fixture');
  assert.deepEqual(provenance.extras, { aiGenerated: true });
  assert.equal(output.readFloatLE(start + 4), 6); // input front is -x, output front is +x
  assert.equal(output.readFloatLE(start + 12), 0); // ground is z=0
  assert.equal(output.readUInt32LE(start + 16), 0xffc85a14); // blue PNG
  assert.equal(output.readUInt32LE(start + 52), 1); // named headlight glows
});

test('generated task records replace missing AI identification and retain the raw GLB hash', () => {
  const source = makeFixture({ ai: false }), directory = mkdtempSync(join(tmpdir(), 'm3dmodel-'));
  try {
    const generatedPath = join(directory, 'generated.json');
    writeFileSync(generatedPath, JSON.stringify({ fixture: { credits: 5, tasks: [
      { id: 'task-1', type: 'image-to-3d', ai_model: 'test', credits: 5, finished: '2026-10-18T00:00:00Z' },
    ] } }));
    const { output } = convert(source, { modelId: 'fixture', front: '-x', lengthMeters: 12, generatedPath });
    const record = header(output).provenance;
    assert.equal(record.asset.generator, 'plain fixture');
    assert.equal(record.generated.model, 'fixture');
    assert.equal(record.generated.tasks[0].id, 'task-1');
    assert.equal(record.generated.raw_sha256, createHash('sha256').update(source).digest('hex'));
  } finally { rmSync(directory, { recursive: true, force: true }); }
});

test('actual city bus JPEG converts within the color budget, facing +x at 12 m', () => {
  const source = readFileSync(bus), gltf = readGlb(source);
  const jpg = image(gltf, 0);
  assert.equal(jpg.width, 2048);
  assert.equal(jpg.height, 2048);
  const blue = jpg.sample(100, 60);
  assert.ok(blue[2] > blue[0] + 80, `JPEG blue stripe decoded: ${blue}`);
  const { output, triangles, colors, paintTriangles } = convert(source, { modelId: 'city-bus', front: '-x', lengthMeters: 12 });
  assert.deepEqual(output, readFileSync(new URL('../../docs/art/meshy-city-bus-2026-10-18/city-bus.m3dmodel', import.meta.url)), '#803 output remains byte-identical');
  assert.equal(triangles, 1543); // GLB has 1,545; two zero-area triangles are removed
  assert.ok(colors <= 8);
  assert.ok(paintTriangles > 0);
  const { provenance, triangles: start } = header(output);
  assert.equal(provenance.generated.model, 'city-bus');
  assert.equal(provenance.generated.tasks.length, 2);
  assert.equal(provenance.generated.raw_sha256, createHash('sha256').update(source).digest('hex'));
  const xs = [];
  for (let i = 0; i < triangles; i++) for (let corner = 0; corner < 3; corner++) xs.push(output.readFloatLE(start + i * 52 + 4 + corner * 16));
  assert.equal(Math.min(...xs), -6);
  assert.equal(Math.max(...xs), 6);
});

test('invalid GLB and unsupported front fail without creating a model', () => {
  assert.throws(() => convert(Buffer.from('invalid'), { modelId: 'fixture', front: '-x', lengthMeters: 12 }), /glTF 2.0 GLB/);
  assert.throws(() => convert(readFileSync(fixture), { modelId: 'fixture', front: '-y', lengthMeters: 12 }), /Unknown front/);
});

// A GLB of one triangle whose nodes are `nodes`, scene root node 0.
function glbWithNodes(nodes) {
  const bin = Buffer.alloc(36);
  [[0, 0, 0], [1, 0, 0], [0, 1, 0]].flat().forEach((value, index) => bin.writeFloatLE(value, index * 4));
  const json = {
    asset: { version: '2.0', generator: 'Meshy' }, scene: 0, scenes: [{ nodes: [0] }], nodes,
    meshes: [{ primitives: [{ attributes: { POSITION: 0 } }] }],
    accessors: [{ bufferView: 0, componentType: 5126, count: 3, type: 'VEC3' }],
    bufferViews: [{ buffer: 0, byteLength: 36 }], buffers: [{ byteLength: 36 }],
  };
  let text = Buffer.from(JSON.stringify(json));
  text = Buffer.concat([text, Buffer.alloc((4 - text.length % 4) % 4, 32)]);
  const chunk = (type, data) => {
    const head = Buffer.alloc(8);
    head.writeUInt32LE(data.length);
    head.write(type, 4, 'ascii');
    return Buffer.concat([head, data]);
  };
  const head = Buffer.alloc(12);
  head.write('glTF');
  head.writeUInt32LE(2, 4);
  const glb = Buffer.concat([head, chunk('JSON', text), chunk('BIN\0', bin)]);
  glb.writeUInt32LE(glb.length, 8);
  return glb;
}

test('a node shared by two parents is refused at once, not walked once per path', () => {
  // 40 levels, each listing the next twice: 2^40 paths to the mesh.
  const nodes = [];
  for (let level = 0; level < 40; level++) nodes.push({ children: [level + 1, level + 1] });
  nodes.push({ mesh: 0 });
  const started = Date.now();
  assert.throws(() => convert(glbWithNodes(nodes), { modelId: 'shared', front: '+x', lengthMeters: 1 }), /more than one parent/);
  assert.ok(Date.now() - started < 2_000);
  assert.throws(() => convert(glbWithNodes([{ children: [1] }, { children: [0] }]), { modelId: 'cycle', front: '+x', lengthMeters: 1 }), /node cycle/);
});

test('a PNG is inflated no further than its header says', () => {
  const chunk = (type, data) => {
    const head = Buffer.alloc(8);
    head.writeUInt32BE(data.length);
    head.write(type, 4, 'ascii');
    return Buffer.concat([head, data, Buffer.alloc(4)]);
  };
  const png = (width, height, raw) => {
    const header = Buffer.alloc(13);
    header.writeUInt32BE(width, 0);
    header.writeUInt32BE(height, 4);
    header[8] = 8;
    header[9] = 6;
    return Buffer.concat([
      Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', header), chunk('IDAT', deflateSync(raw)), chunk('IEND', Buffer.alloc(0)),
    ]);
  };
  const wrapped = (bytes) => ({ json: { images: [{ bufferView: 0, mimeType: 'image/png' }], bufferViews: [{ buffer: 0, byteLength: bytes.length }] }, binary: bytes });
  // A 1 × 1 image is 5 bytes unpacked; these 64 MB of zeros pack to about 64 KB.
  const bomb = wrapped(png(1, 1, Buffer.alloc(64 * 1024 * 1024)));
  assert.ok(bomb.binary.length < 1024 * 1024);
  const before = process.memoryUsage().arrayBuffers;
  assert.throws(() => image(bomb, 0), /bad data length/);
  // Unpacked in full, the 64 MB would still be held here, not yet collected.
  assert.ok(process.memoryUsage().arrayBuffers - before < 16 * 1024 * 1024);
  assert.throws(() => image(wrapped(png(65_536, 65_536, Buffer.alloc(1))), 0), /larger than 4096/);
  assert.deepEqual(image(wrapped(png(1, 1, Buffer.from([0, 10, 20, 30, 40]))), 0).sample(0, 0), [10, 20, 30, 40]);
});
