// Calls the repository's convert() unchanged. A scratch "generated" record stands in for the
// Meshy task log, because convert() requires one for a GLB without AI identification.
import { readFileSync, writeFileSync } from 'node:fs';
import { convert } from '../../../../tools/glb-to-m3dmodel/convert.mjs';
const [input, output, id, front, len, gen] = process.argv.slice(2);
const t0 = performance.now();
try {
  const r = convert(readFileSync(input), { modelId: id, front, lengthMeters: +len, generatedPath: gen });
  writeFileSync(output, r.output);
  console.log(JSON.stringify({ id, ok: true, bytes: r.output.length, triangles: r.triangles, colors: r.colors, paint: r.paintTriangles, glow: r.glowingTriangles, ms: Math.round(performance.now() - t0) }));
} catch (e) { console.log(JSON.stringify({ id, ok: false, error: e.message })); }
