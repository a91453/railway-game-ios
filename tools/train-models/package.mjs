// Convert the final native units / assemblies with the existing GLB writer.
import {readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {model, bounds} from './native.mjs';
import {glbFromNative} from '../station-kit/package.mjs';
const root = resolve(process.argv[2]), path = resolve(root, 'manifest.json');
const manifest = JSON.parse(readFileSync(path));
const sha = b => createHash('sha256').update(b).digest('hex');
for (const m of manifest.models) {
  const bytes = readFileSync(resolve(root, m.native)), parsed = model(bytes);
  const actual = bounds(parsed.vertices);
  if (m.native_kind !== 'assembly' && m.triangles !== parsed.vertices.length / 3 && !manifest.night_lights) throw Error(`${m.id}: native triangle count differs`);
  const glb = glbFromNative(parsed);
  m.glb = `models/${m.id}.glb`; writeFileSync(resolve(root, m.glb), glb);
  // Pack hash/count describe the recipe, rendered count includes runtime lights.
  m.exported_triangles = parsed.vertices.length / 3;
  m.exported_bounds = actual;
  m.native_sha256 = sha(bytes); m.glb_sha256 = sha(glb);
}
writeFileSync(path, JSON.stringify(manifest, null, 2) + '\n');
console.log(`packaged ${manifest.models.length} native / GLB models`);
