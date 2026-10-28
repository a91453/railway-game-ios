// Shared validation around the existing M3DM / M3DAssembly contract.
// Expanded assemblies are preview buffers, never loadable single-unit files.
import {assemblyNative} from '../emu900-native/scene.js';
import {readNative as decode} from '../station-kit/package.mjs';

export const maximumUnitTriangles = 15000;
export const arrayBuffer = b => b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength);
export function unit(bytes, {enforceLimit = true} = {}) {
  if (bytes.length < 16 || bytes.toString('ascii', 0, 4) !== 'M3DM'
      || bytes.readUInt16LE(4) !== 1 || bytes.readUInt16LE(6) !== 0) throw Error('Invalid M3DM v1 header');
  const count = bytes.readUInt32LE(8);
  if (!count || (enforceLimit && count > maximumUnitTriangles)) throw Error('M3DM unit triangle limit');
  const model = decode(bytes);
  if (model.vertices.some(v => [...v.position, ...v.normal].some(x => !Number.isFinite(x)))) throw Error('Nonfinite native geometry');
  return model;
}
export function expanded(bytes) {
  if (bytes[0] !== 123) { unit(bytes); return bytes; }
  const scene = JSON.parse(bytes);
  if (scene.format !== 'M3DAssembly' || scene.version !== 1 || !scene.units
      || !Array.isArray(scene.placements) || !scene.placements.length) throw Error('Invalid M3DAssembly');
  const used = new Set();
  for (const p of scene.placements) {
    if (!Object.hasOwn(scene.units, p.unit)) throw Error('Missing assembly unit');
    used.add(p.unit);
    if (!Array.isArray(p.translation) || p.translation.length !== 3 || !p.translation.every(Number.isFinite)
        || ![0, 180].includes(p.rotation_degrees ?? 0) || (p.scale_x !== undefined && p.scale_x !== 1)) throw Error('Invalid assembly placement (metres, 0/180 degrees, no scaling)');
  }
  if (used.size !== Object.keys(scene.units).length) throw Error('Unused embedded assembly unit');
  for (const b64 of Object.values(scene.units)) {
    if (typeof b64 !== 'string' || Buffer.from(b64, 'base64').toString('base64') !== b64) throw Error('Invalid embedded base64');
    unit(Buffer.from(b64, 'base64'));
  }
  const buffer = Buffer.from(assemblyNative(arrayBuffer(bytes)));
  unit(buffer, {enforceLimit: false});
  return buffer;
}
export function model(bytes) { return unit(expanded(bytes), {enforceLimit: false}); }
export function bounds(vertices) {
  return Object.fromEntries([['minimum', Math.min, Infinity], ['maximum', Math.max, -Infinity]].map(([key, op, initial]) =>
    [key, [0, 1, 2].map(axis => vertices.reduce((v, p) => op(v, p.position[axis]), initial))]));
}
