// Shared triangle audit; vehicle-specific visibility/support/rail probes remain
// separately required. Balanced edges do not prove a Boolean solid or no overlap.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {model, expanded, bounds} from './native.mjs';
import {glbFromNative} from '../station-kit/package.mjs';

export function topology(vertices) {
  assert(vertices.length > 0 && vertices.length % 3 === 0, 'triangle count');
  const edges = new Map(), parent = Array.from({length: vertices.length / 3}, (_, i) => i);
  function find(i) { while (parent[i] !== i) { parent[i] = parent[parent[i]]; i = parent[i]; } return i; }
  const volumes = [];
  for (let i = 0; i < vertices.length; i += 3) {
    const p = vertices.slice(i, i + 3).map(v => v.position);
    assert(p.flat().every(Number.isFinite), 'nonfinite triangle');
    const [a, b, c] = p, u = b.map((x, j) => x - a[j]), v = c.map((x, j) => x - a[j]);
    assert(Math.hypot(u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0]) > 1e-9, 'degenerate triangle');
    const keys = p.map(v => v.map(x => Math.round(x * 1e5)).join(','));
    for (let j = 0; j < 3; j++) {
      const a = keys[j], b = keys[(j + 1) % 3]; assert.notEqual(a, b, 'collapsed edge at audit precision');
      const key = a < b ? a + '|' + b : b + '|' + a;
      const edge = edges.get(key) || {balance: 0, face: i / 3};
      edge.balance += a < b ? 1 : -1;
      parent[find(i / 3)] = find(edge.face); edges.set(key, edge);
    }
    volumes.push((a[0]*(b[1]*c[2]-b[2]*c[1])+a[1]*(b[2]*c[0]-b[0]*c[2])+a[2]*(b[0]*c[1]-b[1]*c[0]))/6);
  }
  for (const e of edges.values()) assert.equal(e.balance, 0, 'open or reversed edge');
  const components = new Map();
  for (let i = 0; i < volumes.length; i++) components.set(find(i), (components.get(find(i)) || 0) + volumes[i]);
  for (const v of components.values()) assert(v > 1e-10, 'inward component');
  return {balanced_edges: edges.size, positive_components: components.size, precision_metres: 1e-5};
}
export function audit(root) {
  const manifest = JSON.parse(readFileSync(resolve(root, 'manifest.json'))), results = [];
  for (const m of manifest.models) {
    const bytes = readFileSync(resolve(root, m.native)), parsed = model(bytes), vs = parsed.vertices;
    assert.equal(vs.length / 3, m.exported_triangles ?? m.triangles, `${m.id}: count`);
    const expected = m.exported_bounds ?? m, actual = bounds(vs);
    for (const key of ['minimum', 'maximum']) for (let i = 0; i < 3; i++) assert(Math.abs(actual[key][i] - expected[key][i]) < 1e-4, `${m.id}: bounds`);
    assert.deepEqual(glbFromNative(parsed), readFileSync(resolve(root, m.glb)), `${m.id}: GLB differs`);
    const row = {id: m.id, ...topology(vs)};
    assert.throws(() => topology(vs.slice(3)), /edge|inward|triangle/);
    assert.throws(() => topology([vs[1], vs[0], vs[2], ...vs.slice(3)]), /edge|inward/);
    if (m.native_kind === 'assembly') {
      const scene = JSON.parse(bytes), changed = structuredClone(scene);
      changed.placements[0].translation[0] += 0.1;
      const original = expanded(bytes), broken = expanded(Buffer.from(JSON.stringify(changed)));
      const payload = b => b.subarray(16 + Math.ceil(b.readUInt32LE(12) / 4) * 4);
      assert.notDeepEqual(payload(original), payload(broken), 'assembly displacement mutation');
      if (m.assembly_payload) assert.deepEqual(payload(original), readFileSync(resolve(root, m.assembly_payload)));
      row.assembly_shift_100mm_detected = true;
    }
    row.missing_and_reversed_face_rejected = true; results.push(row);
  }
  const report = {status: 'VERIFIED', models: results, limits: [
    'GLB is checked against the shared writer; run an independent importer separately.',
    'No vehicle-specific glass visibility, equipment support, tyre/rail or clearance proof.',
    'No exhaustive intersections, engineering precision, appearance acceptance or device performance.',
    'Assembly payload is a JS expansion check; independently compare a Swift formation when available.'
  ]};
  writeFileSync(resolve(root, 'geometry-verification.json'), JSON.stringify(report, null, 2) + '\n');
  return report;
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) console.log(`VERIFIED ${audit(resolve(process.argv[2])).models.length} models; read report limits`);
