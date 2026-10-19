import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
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
