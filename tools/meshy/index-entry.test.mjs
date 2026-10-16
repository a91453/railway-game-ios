// node --test tools/meshy/index-entry.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { indexEntry } from './index-entry.mjs';

test('packing a model again keeps what its index line holds besides the file and the way it faces', () => {
  const before = { ao: 'n700st-cab-ao.png', aoChannel: 0, colour: 'n700st-cab.jpg', file: 'old.glb', fit: false, front: '-x' };
  assert.deepEqual(indexEntry(before, 'n700st-cab.glb', '+x'),
    { ao: 'n700st-cab-ao.png', aoChannel: 0, colour: 'n700st-cab.jpg', file: 'n700st-cab.glb', fit: false, front: '+x' });
});

test('a model packed for the first time gets a line of its own', () => {
  assert.deepEqual(indexEntry(undefined, 'emu900-cab.glb', '+x'), { file: 'emu900-cab.glb', front: '+x' });
});
