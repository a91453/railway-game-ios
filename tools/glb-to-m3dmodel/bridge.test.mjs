import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { convertStatic } from './bridge.mjs';
import { readGlb } from './glb.mjs';
import { manifest, makeStaticFixture } from './make-static-fixtures.mjs';

const fixtures = fileURLToPath(new URL('fixtures/', import.meta.url));
const bridge = fileURLToPath(new URL('bridge.mjs', import.meta.url));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
function header(bytes) {
  const length = bytes.readUInt32LE(12);
  return JSON.parse(bytes.toString('utf8', 16, 16 + length));
}
function payload(bytes) { return bytes.subarray(16 + Math.ceil(bytes.readUInt32LE(12) / 4) * 4); }
async function sandbox(fn) {
  const dir = mkdtempSync(join(tmpdir(), 'static-gltf-'));
  try { await fn(dir); } finally { rmSync(dir, { recursive: true, force: true }); }
}
async function run(dir, patch = {}) {
  const path = join(dir, 'manifest.json');
  writeFileSync(path, JSON.stringify({ ...manifest, input: join(fixtures, 'static-meshopt.glb'), ...patch }));
  return convertStatic(path);
}

test('authored compressed/quantized GLB, plain GLB and external glTF produce identical triangle bytes', async () => {
  assert.deepEqual(await makeStaticFixture(), readFileSync(join(fixtures, 'static-plain.glb')));
  const compressed = await makeStaticFixture({ compressed: true, quantized: true });
  assert.deepEqual(compressed, readFileSync(join(fixtures, 'static-meshopt.glb')));
  const jsonLength = compressed.readUInt32LE(12);
  const original = JSON.parse(compressed.toString('utf8', 20, 20 + jsonLength));
  assert.deepEqual(original.extensionsRequired, ['EXT_meshopt_compression', 'KHR_mesh_quantization']);
  await sandbox(async dir => {
    const results = [];
    for (const input of ['static-meshopt.glb', 'static-plain.glb', 'static.gltf']) {
      const result = await run(dir, { input: join(fixtures, input) });
      assert.equal(result.triangles, 2); assert.equal(result.colors, 2);
      assert.equal(result.paintTriangles, 0); assert.equal(result.glowingTriangles, 1);
      results.push(result);
    }
    for (const result of results.slice(1)) assert.deepEqual(payload(result.output), payload(results[0].output));
    const json = readGlb(results[0].plainGlb).json;
    assert.equal(json.extensionsRequired, undefined);
    assert.equal(json.meshes.length, 2);
    assert.equal(json.materials.length, 2);
    assert.ok(json.nodes.some(node => node.name === 'parent' && node.scale[2] === -1));
    assert.ok(json.accessors.filter(a => a.type !== 'SCALAR').every(a => a.componentType === 5126));
    const p = payload(results[0].output);
    const points = Array.from({ length: 6 }, (_, i) => [0, 1, 2].map(axis =>
      p.readFloatLE(Math.floor(i / 3) * 52 + 4 + i % 3 * 16 + axis * 4)));
    assert.deepEqual(points, [[0.5, 0, 0], [0.5, 2, 0], [-0.5, 0, 3], [0.5, -2, 3], [0.5, 0, 3], [-0.5, -2, 6]]);
    assert.equal(p.readUInt32LE(16), 0xffcccccc);
    const source = header(results[2].output).source;
    assert.equal(source.kind, 'non-ai'); assert.equal(source.license, manifest.source.license);
    assert.equal(source.files[1].sha256, hash(readFileSync(join(fixtures, 'buffer.bin'))));
    assert.equal(source.files[0].sha256, hash(readFileSync(join(fixtures, 'static.gltf'))));
    assert.equal(header(results[2].output).generated, undefined);
    assert.ok(!results[2].output.includes(Buffer.from('aiGenerated')));
  });
  const committed = await convertStatic(join(fixtures, 'static.manifest.json'));
  assert.deepEqual(committed.output, readFileSync(join(fixtures, 'static.m3dmodel')));
});

test('paint switch, length strategy, front direction and exact node whitelist are explicit', async () => sandbox(async dir => {
  const colored = await run(dir), paint = await run(dir, { recolorLightPaint: true });
  assert.equal(colored.paintTriangles, 0); assert.equal(paint.paintTriangles, 1);
  const scaled = await run(dir, { units: undefined, lengthMeters: 4, front: '-x' });
  assert.equal(payload(scaled.output).readFloatLE(4), -2);
  const only = await run(dir, { nodes: ['body'] });
  assert.equal(only.triangles, 1); assert.equal(only.glowingTriangles, 0);
  await assert.rejects(run(dir, { nodes: ['missing'] }), /match exactly one mesh node/);
  await assert.rejects(run(dir, { nodes: ['parent'] }), /match exactly one mesh node/);
  await assert.rejects(run(dir, { nodes: ['body', 'body'] }), /unique/);
  await assert.rejects(run(dir, { units: 'meters', lengthMeters: 12 }), /choose units/);
  await assert.rejects(run(dir, { recolorLightPaint: undefined }), /explicitly/);
  await assert.rejects(run(dir, { source: undefined }), /source requires/);
}));

test('meshopt alone, quantization alone, compressed external glTF and multiple .bin buffers agree', async () => sandbox(async dir => {
  const expected = payload((await run(dir)).output);
  for (const options of [{ compressed: true }, { quantized: true }, { compressed: true, quantized: true, format: 'gltf' }]) {
    const fixture = await makeStaticFixture(options);
    if (options.format === 'gltf') {
      writeFileSync(join(dir, 'input.gltf'), JSON.stringify(fixture.json));
      for (const [uri, bytes] of Object.entries(fixture.resources)) writeFileSync(join(dir, uri), bytes);
    } else writeFileSync(join(dir, 'input.glb'), fixture);
    const converted = await run(dir, { input: options.format === 'gltf' ? 'input.gltf' : 'input.glb' });
    assert.deepEqual(payload(converted.output), expected);
  }
  const json = JSON.parse(readFileSync(join(fixtures, 'static.gltf'), 'utf8'));
  const binary = readFileSync(join(fixtures, 'buffer.bin'));
  json.buffers = [{ uri: 'vertices.bin', byteLength: 48 }, { uri: 'indices.bin', byteLength: 8 }];
  json.bufferViews[1].buffer = 1; json.bufferViews[1].byteOffset = 0;
  writeFileSync(join(dir, 'vertices.bin'), binary.subarray(0, 48));
  writeFileSync(join(dir, 'indices.bin'), binary.subarray(48));
  writeFileSync(join(dir, 'input.gltf'), JSON.stringify(json));
  const multiple = await run(dir, { input: 'input.gltf' });
  assert.deepEqual(payload(multiple.output), expected);
  assert.equal(header(multiple.output).source.files.length, 3);
}));

test('static boundary rejects unsupported content before loading resources or writing output', async () => sandbox(async dir => {
  const cases = [
    [j => { j.images = [{ uri: 'https://invalid.example/never-read.png' }]; }, /images/],
    [j => { j.textures = [{}]; }, /textures/],
    [j => { j.materials[0].normalTexture = { index: 0 }; }, /texture material/],
    [j => { j.skins = [{}]; }, /skins/],
    [j => { j.nodes[0].skin = 0; }, /skin/],
    [j => { j.animations = [{}]; }, /animations/],
    [j => { j.meshes[0].primitives[0].targets = [{ POSITION: 0 }]; }, /morph/],
    [j => { j.nodes[0].weights = [0]; }, /morph/],
    [j => { j.meshes[0].primitives[0].mode = 1; }, /triangle/],
    [j => { j.accessors[0].sparse = {}; }, /sparse/],
    [j => { j.extensionsRequired = ['KHR_draco_mesh_compression']; }, /KHR_draco/],
    [j => { j.extensionsRequired = ['KHR_texture_basisu']; }, /KHR_texture_basisu/],
    [j => { j.extensionsRequired = ['VENDOR_unknown']; }, /VENDOR_unknown/],
    [j => { j.materials[0].extensions = { KHR_materials_transmission: {} }; }, /KHR_materials_transmission/],
    [j => { j.buffers[0].uri = 'https://invalid.example/model.bin'; }, /local relative/],
    [j => { j.buffers[0].uri = 'missing.bin'; }, /ENOENT/],
    [j => { j.buffers[0].byteLength = 99999; }, /truncated/],
    [j => { j.nodes[1].name = 'body'; }, /exactly one/],
    [j => { j.asset.generator = 'Meshy'; }, /AI identification conflicts/],
  ];
  writeFileSync(join(dir, 'buffer.bin'), readFileSync(join(fixtures, 'buffer.bin')));
  for (const [mutate, expected] of cases) {
    const json = JSON.parse(readFileSync(join(fixtures, 'static.gltf'), 'utf8'));
    mutate(json); writeFileSync(join(dir, 'input.gltf'), JSON.stringify(json));
    await assert.rejects(run(dir, { input: 'input.gltf' }), expected);
    const output = join(dir, 'refused.m3dmodel');
    const cli = spawnSync(process.execPath, [bridge, '--manifest', join(dir, 'manifest.json'), '--output', output]);
    assert.equal(cli.status, 1, cli.stderr.toString());
    assert.equal(existsSync(output), false);
  }
}));

test('CLI exports a readable plain GLB, atomically preserves existing output on refusal, and records original metadata', async () => sandbox(async dir => {
  const json = JSON.parse(readFileSync(join(fixtures, 'static.gltf'), 'utf8'));
  json.asset.generator = 'Original project fixture'; json.extras = { note: 'source metadata' };
  writeFileSync(join(dir, 'input.gltf'), JSON.stringify(json));
  writeFileSync(join(dir, 'buffer.bin'), readFileSync(join(fixtures, 'buffer.bin')));
  await run(dir, { input: 'input.gltf' });
  const output = join(dir, 'output.m3dmodel'), decoded = join(dir, 'decoded.glb');
  const cli = spawnSync(process.execPath, [bridge, '--manifest', join(dir, 'manifest.json'), '--output', output, '--decoded-output', decoded]);
  assert.equal(cli.status, 0, cli.stderr.toString());
  assert.equal(header(readFileSync(output)).asset.generator, 'Original project fixture');
  assert.deepEqual(header(readFileSync(output)).extras, json.extras);
  assert.deepEqual(readGlb(readFileSync(decoded)).json.asset, json.asset);
  const good = readFileSync(output);
  json.skins = [{}]; writeFileSync(join(dir, 'input.gltf'), JSON.stringify(json));
  const refused = spawnSync(process.execPath, [bridge, '--manifest', join(dir, 'manifest.json'), '--output', output]);
  assert.equal(refused.status, 1); assert.deepEqual(readFileSync(output), good);
}));
