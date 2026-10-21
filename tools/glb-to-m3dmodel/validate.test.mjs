import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { validateGlb } from './validate.mjs';

const bus = fileURLToPath(new URL('../../docs/art/meshy-city-bus-2026-10-18/city-bus.glb', import.meta.url));
const busModel = fileURLToPath(new URL('../../docs/art/meshy-city-bus-2026-10-18/city-bus.m3dmodel', import.meta.url));
const tiny = fileURLToPath(new URL('fixtures/tiny.glb', import.meta.url));
const convertScript = fileURLToPath(new URL('convert.mjs', import.meta.url));

test('the Meshy bus passes glTF-Validator with no errors', async () => {
  const result = await validateGlb(readFileSync(bus), 'city-bus.glb');
  assert.equal(result.warnings, 0);
});

test('a GLB that breaks the glTF spec is refused, naming the errors', async () => {
  // The converter's own fixture leaves out the POSITION accessor's bounds,
  // which the spec requires.
  await assert.rejects(validateGlb(readFileSync(tiny), 'tiny.glb'),
    /glTF-Validator: 2 errors in tiny\.glb: MESH_PRIMITIVE_POSITION_ACCESSOR_WITHOUT_BOUNDS/);
  const broken = readFileSync(tiny);
  broken[30] = 0x7b; // the JSON chunk no longer parses
  await assert.rejects(validateGlb(broken, 'broken.glb'), /INVALID_JSON/);
});

test('the command line checks the GLB first and converts the bus to the committed model', () => {
  const dir = mkdtempSync(join(tmpdir(), 'm3dmodel-'));
  try {
    const output = join(dir, 'city-bus.m3dmodel');
    const printed = execFileSync(process.execPath, [convertScript, '--input', bus, '--output', output, '--id', 'city-bus'], { encoding: 'utf8' });
    assert.match(printed, /^glTF-Validator: no errors, 0 warnings, 1 infos\ncity-bus: 1543 triangles, 8 colors/);
    assert.deepEqual(readFileSync(output), readFileSync(busModel));
    assert.throws(() => execFileSync(process.execPath, [convertScript, '--input', tiny, '--output', join(dir, 'tiny.m3dmodel'), '--id', 'city-bus'],
      { stdio: 'pipe' }), /MESH_PRIMITIVE_POSITION_ACCESSOR_WITHOUT_BOUNDS/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
