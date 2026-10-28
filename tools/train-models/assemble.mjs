// node assemble.mjs RUN SPEC.json
// SPEC = {assemblies:[{id, placements:[{unit,translation:[x,y,z],rotation_degrees:0|180}]}]}
import {readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {expanded, model, bounds} from './native.mjs';
export function assemble(root, spec) {
  const path = resolve(root, 'manifest.json'), manifest = JSON.parse(readFileSync(path));
  if (!Array.isArray(spec.assemblies) || !spec.assemblies.length) throw Error('No assemblies in spec');
  const byId = new Map(manifest.models.map(m => [m.id, m]));
  const pending = [];
  for (const item of spec.assemblies) {
    if (!/^[a-zA-Z0-9_-]+$/.test(item.id) || byId.has(item.id)) throw Error('Duplicate or invalid assembly ID');
    if (!Array.isArray(item.placements) || !item.placements.length) throw Error('Empty assembly');
    const units = {};
    for (const p of item.placements) {
      const source = byId.get(p.unit);
      if (!source || source.native_kind === 'assembly') throw Error('Export the referenced independent unit first');
      units[p.unit] = readFileSync(resolve(root, source.native)).toString('base64');
    }
    const bytes = Buffer.from(JSON.stringify({format: 'M3DAssembly', version: 1, units, placements: item.placements}, null, 2) + '\n');
    const decoded = expanded(bytes), parsed = model(bytes);
    const native = `models/${item.id}.m3dscene.json`;
    // No self-generated "independent expected" claim: this is a JS expansion
    // digest. Compare an independently produced Swift formation separately.
    const record = {id: item.id, native, native_kind: 'assembly', category: 'formation',
      triangles: parsed.vertices.length / 3, ...bounds(parsed.vertices),
      assembly_payload: `models/${item.id}.triangles.bin`};
    pending.push({bytes, decoded, record}); byId.set(item.id, record);
  }
  for (const {bytes, decoded, record} of pending) {
    writeFileSync(resolve(root, record.native), bytes);
    const start = 16 + Math.ceil(decoded.readUInt32LE(12) / 4) * 4;
    writeFileSync(resolve(root, record.assembly_payload), decoded.subarray(start));
    manifest.models.push(record);
  }
  manifest.model_count = manifest.models.length;
  writeFileSync(path, JSON.stringify(manifest, null, 2) + '\n');
  return pending.length;
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  console.log(`assembled ${assemble(resolve(process.argv[2]), JSON.parse(readFileSync(process.argv[3])))} formation(s)`);
}
