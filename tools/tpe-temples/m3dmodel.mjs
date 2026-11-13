// `.m3dmodel` version 1 (Map3DModelFile): a header, the provenance JSON,
// then each triangle's flags and three corners (x, y, z, RGBA).
export function writeM3dmodel(triangles, record) {
  const provenance = Buffer.from(JSON.stringify(record), 'utf8');
  const padded = Math.ceil(provenance.length / 4) * 4, out = Buffer.alloc(16 + padded + triangles.length * 52);
  out.write('M3DM', 0, 'ascii');
  out.writeUInt16LE(1, 4);
  out.writeUInt32LE(triangles.length, 8);
  out.writeUInt32LE(provenance.length, 12);
  provenance.copy(out, 16);
  triangles.forEach((t, i) => {
    const at = 16 + padded + i * 52, rgb = t.rgb;
    // Swift's rgb(0xRRGGBB): red in the low byte, alpha 255.
    const colour = ((rgb >> 16) | (rgb & 0xFF00) | ((rgb & 0xFF) << 16) | 0xFF000000) >>> 0;
    t.points.forEach((p, k) => {
      p.forEach((v, a) => out.writeFloatLE(v, at + 4 + k * 16 + a * 4));
      out.writeUInt32LE(colour, at + 4 + k * 16 + 12);
    });
  });
  return out;
}
