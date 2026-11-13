// Decision 725: winds the bundled tpe-*.m3dmodel files alike across their
// shared edges (wind.mjs), in place, keeping each triangle's flags and
// colours and the provenance. build.mjs runs the same step last, so a
// rebuild from the KMZ gives these files; this script fixed the files
// built before that step was added without the KMZ (2026-11-13).
//
//   node tools/tpe-temples/rewind.mjs RailwayGameApp/Resources/Models/tpe-*.m3dmodel
import { readFileSync, writeFileSync } from 'node:fs';
import { windConsistently } from './wind.mjs';

for (const file of process.argv.slice(2)) {
  const bytes = readFileSync(file);
  if (bytes.toString('ascii', 0, 4) !== 'M3DM' || bytes.readUInt16LE(4) !== 1) throw new Error(`${file}: not a version 1 .m3dmodel`);
  const count = bytes.readUInt32LE(8), padded = Math.ceil(bytes.readUInt32LE(12) / 4) * 4, body = 16 + padded;
  if (bytes.length !== body + count * 52) throw new Error(`${file}: unexpected length`);
  const triangles = [];
  for (let i = 0; i < count; i++) {
    const at = body + i * 52;
    triangles.push({
      flags: bytes.readUInt32LE(at),
      points: [0, 1, 2].map(k => [0, 1, 2].map(a => bytes.readFloatLE(at + 4 + k * 16 + a * 4))),
      colours: [0, 1, 2].map(k => bytes.readUInt32LE(at + 4 + k * 16 + 12)),
    });
    // Keep each corner's colour with its corner when the corners turn.
    triangles[i].points.forEach((p, k) => { p.colour = triangles[i].colours[k]; });
  }
  const result = windConsistently(triangles);
  const out = Buffer.alloc(body + triangles.length * 52);
  bytes.copy(out, 0, 0, body);
  out.writeUInt32LE(triangles.length, 8);
  triangles.forEach((t, i) => {
    const at = body + i * 52;
    out.writeUInt32LE(t.flags, at);
    t.points.forEach((p, k) => {
      p.forEach((v, a) => out.writeFloatLE(v, at + 4 + k * 16 + a * 4));
      out.writeUInt32LE(p.colour, at + 4 + k * 16 + 12);
    });
  });
  writeFileSync(file, out);
  process.stdout.write(`${file}: ${count} -> ${triangles.length} triangles, ${result.flipped} turned, ${result.twins} drawn from both sides, ${result.pieces} pieces\n`);
}
