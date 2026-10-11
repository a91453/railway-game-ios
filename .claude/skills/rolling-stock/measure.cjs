// Turns a reference model of a train into the handful of numbers the city view's code-drawn stock
// needs. A reference GLB is far too heavy to ship (the owner's EMU3000 is 199,588 triangles; a
// whole 12-car set in the city view is about 3,300), but it is ground truth for shape and colour,
// and reading it beats reading a photograph: it has no perspective, no specular streak mistaken
// for paint, and no hidden far side.
//
//   node .claude/skills/rolling-stock/measure.cjs <reference.glb> [--slices 20] [--json]
//
// Prints, in the city view's own frame (+Z the running direction, +Y up, y = 0 the rail):
//   * overall length, width and height, and where the body sits above the rail
//   * every material: its colour as the city view would write it, how much of the model it covers,
//     and the height band it occupies — which is what a livery band's rows are read from
//   * the cross-section along the car (half-width, top, bottom) — the stations of a lofted shell
//   * the longitudinal positions of the door and glass materials — pitch and placement
//
// Reference models arrive in whatever frame their author used. --axis says which model axis runs
// along the car; the default guesses it from the longest dimension, which is right for a vehicle.
const fs = require('fs');

const args = process.argv.slice(2);
const file = args.find((a) => !a.startsWith('--'));
const flag = (n, d) => { const i = args.indexOf(`--${n}`); return i >= 0 && args[i + 1] && !args[i + 1].startsWith('--') ? args[i + 1] : d; };
const SLICES = Number(flag('slices', '20'));
const asJson = args.includes('--json');
if (!file) { console.error('usage: measure.cjs <reference.glb> [--slices 20] [--json]'); process.exit(2); }

// ---- GLB and the glTF node hierarchy (https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html)
const buf = fs.readFileSync(file);
if (buf.readUInt32LE(0) !== 0x46546c67) { console.error('not a glTF binary'); process.exit(2); }
let o = 12, gltf = null, bin = Buffer.alloc(0);
while (o < buf.length) {
  const len = buf.readUInt32LE(o), type = buf.readUInt32LE(o + 4), data = buf.subarray(o + 8, o + 8 + len);
  if (type === 0x4e4f534a) gltf = JSON.parse(data.toString('utf8'));
  else if (type === 0x004e4942) bin = data;
  o += 8 + len;
}

const ident = () => [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
function mul(a, b) {                                   // column-major, as glTF stores them
  const r = new Array(16).fill(0);
  for (let c = 0; c < 4; c++) for (let d = 0; d < 4; d++) for (let k = 0; k < 4; k++) r[c * 4 + d] += a[k * 4 + d] * b[c * 4 + k];
  return r;
}
function trs(node) {
  if (node.matrix) return node.matrix.slice();
  const [tx, ty, tz] = node.translation ?? [0, 0, 0];
  const [qx, qy, qz, qw] = node.rotation ?? [0, 0, 0, 1];
  const [sx, sy, sz] = node.scale ?? [1, 1, 1];
  const x2 = qx + qx, y2 = qy + qy, z2 = qz + qz;
  const xx = qx * x2, xy = qx * y2, xz = qx * z2, yy = qy * y2, yz = qy * z2, zz = qz * z2;
  const wx = qw * x2, wy = qw * y2, wz = qw * z2;
  return [
    (1 - (yy + zz)) * sx, (xy + wz) * sx, (xz - wy) * sx, 0,
    (xy - wz) * sy, (1 - (xx + zz)) * sy, (yz + wx) * sy, 0,
    (xz + wy) * sz, (yz - wx) * sz, (1 - (xx + yy)) * sz, 0,
    tx, ty, tz, 1,
  ];
}
const apply = (m, p) => [
  m[0] * p[0] + m[4] * p[1] + m[8] * p[2] + m[12],
  m[1] * p[0] + m[5] * p[1] + m[9] * p[2] + m[13],
  m[2] * p[0] + m[6] * p[1] + m[10] * p[2] + m[14],
];

const READERS = { 5120: 'getInt8', 5121: 'getUint8', 5122: 'getInt16', 5123: 'getUint16', 5125: 'getUint32', 5126: 'getFloat32' };
const SIZES = { 5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4 };
const COUNTS = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4 };
function read(index) {
  const acc = gltf.accessors[index], view = gltf.bufferViews[acc.bufferView];
  const comps = COUNTS[acc.type], size = SIZES[acc.componentType];
  const stride = view.byteStride || comps * size;
  const start = (view.byteOffset || 0) + (acc.byteOffset || 0);
  const dv = new DataView(bin.buffer, bin.byteOffset, bin.byteLength);
  const out = new Array(acc.count);
  for (let i = 0; i < acc.count; i++) {
    const v = new Array(comps);
    for (let c = 0; c < comps; c++) v[c] = dv[READERS[acc.componentType]](start + i * stride + c * size, true);
    out[i] = comps === 1 ? v[0] : v;
  }
  return out;
}

// Gather every triangle in world space, tagged with the material it belongs to.
const parents = new Map();
for (const [i, n] of (gltf.nodes ?? []).entries()) for (const c of n.children ?? []) parents.set(c, i);
function worldMatrix(i) {
  let m = trs(gltf.nodes[i]);
  for (let p = parents.get(i); p !== undefined; p = parents.get(p)) m = mul(trs(gltf.nodes[p]), m);
  return m;
}
const byMaterial = new Map();
let vertices = [], triangles = 0;
for (const [i, node] of (gltf.nodes ?? []).entries()) {
  if (node.mesh == null) continue;
  const m = worldMatrix(i);
  for (const prim of gltf.meshes[node.mesh].primitives) {
    const pos = read(prim.attributes.POSITION).map((p) => apply(m, p));
    const n = prim.indices != null ? read(prim.indices).length / 3 : pos.length / 3;
    triangles += n;
    const name = prim.material != null ? (gltf.materials[prim.material].name ?? `material ${prim.material}`) : 'untextured';
    if (!byMaterial.has(name)) byMaterial.set(name, { material: prim.material, triangles: 0, points: [] });
    const rec = byMaterial.get(name);
    rec.triangles += n;
    rec.points.push(...pos);
    vertices.push(...pos);
  }
}
if (!vertices.length) { console.error('the model has no geometry'); process.exit(2); }

// ---- Put it in the city view's frame: +Z along the car, +Y up, y = 0 at the rail.
const span = [0, 1, 2].map((a) => Math.max(...vertices.map((p) => p[a])) - Math.min(...vertices.map((p) => p[a])));
const along = Number(flag('axis', String(span.indexOf(Math.max(...span)))));   // the car runs along its longest axis
const rest = [0, 1, 2].filter((a) => a !== along);
// Of the two remaining axes, up is the one the model is taller in: a car is taller than it is wide.
const up = span[rest[0]] >= span[rest[1]] ? rest[0] : rest[1];
const side = rest.find((a) => a !== up);
const put = (p) => [p[side], p[up], p[along]];
const all = vertices.map(put);
const floorY = Math.min(...all.map((p) => p[1]));
const midZ = (Math.max(...all.map((p) => p[2])) + Math.min(...all.map((p) => p[2]))) / 2;
const frame = (p) => { const q = put(p); return [q[0], q[1] - floorY, q[2] - midZ]; };

const pts = vertices.map(frame);
const bound = (ps) => ({
  x: [Math.min(...ps.map((p) => p[0])), Math.max(...ps.map((p) => p[0]))],
  y: [Math.min(...ps.map((p) => p[1])), Math.max(...ps.map((p) => p[1]))],
  z: [Math.min(...ps.map((p) => p[2])), Math.max(...ps.map((p) => p[2]))],
});
const whole = bound(pts);
const LEN = whole.z[1] - whole.z[0], WIDE = whole.x[1] - whole.x[0], TALL = whole.y[1] - whole.y[0];

// Reference models are often authored at a convenient scale rather than in metres. Say so loudly
// rather than quietly reporting a 0.5 m train: every number below is only as good as this.
const ratio = flag('metres', null) ? Number(flag('metres', '0')) / LEN : 1;
const M = (v) => +(v * ratio).toFixed(3);

const srgb = (v) => Math.round(Math.min(1, Math.max(0, v)) ** (1 / 2.2) * 255);
const hex = (c) => '#' + c.slice(0, 3).map((v) => srgb(v).toString(16).padStart(2, '0')).join('');

const materials = [...byMaterial.entries()].map(([name, rec]) => {
  const ps = rec.points.map(frame), b = bound(ps);
  const mat = rec.material != null ? gltf.materials[rec.material] : {};
  const pbr = mat.pbrMetallicRoughness ?? {};
  return {
    name,
    colour: hex(pbr.baseColorFactor ?? [1, 1, 1, 1]),
    metalness: +(pbr.metallicFactor ?? 1).toFixed(2),
    roughness: +(pbr.roughnessFactor ?? 1).toFixed(2),
    triangles: rec.triangles,
    share: +(rec.triangles / triangles).toFixed(3),
    // where it sits up the body, 0 the rail and 1 the roof: a livery band's rows come from this
    heightBand: [+((b.y[0] - whole.y[0]) / TALL).toFixed(3), +((b.y[1] - whole.y[0]) / TALL).toFixed(3)],
    lengthBand: [+((b.z[0] - whole.z[0]) / LEN).toFixed(3), +((b.z[1] - whole.z[0]) / LEN).toFixed(3)],
    metres: { height: [M(b.y[0]), M(b.y[1])], halfWidth: M(Math.max(Math.abs(b.x[0]), Math.abs(b.x[1]))) },
  };
}).sort((a, b) => b.triangles - a.triangles);

// ---- The cross-section along the car: the stations a lofted shell is built from.
const bodyOnly = materials[0].name;                    // the biggest material is the body shell
const shell = byMaterial.get(bodyOnly).points.map(frame);
const stations = [];
for (let s = 0; s < SLICES; s++) {
  const z0 = whole.z[0] + (LEN * s) / SLICES, z1 = z0 + LEN / SLICES;
  const slab = shell.filter((p) => p[2] >= z0 && p[2] < z1);
  if (slab.length < 8) continue;
  stations.push({
    z: M((z0 + z1) / 2),
    halfWidth: M(Math.max(...slab.map((p) => Math.abs(p[0])))),
    top: M(Math.max(...slab.map((p) => p[1]))),
    bottom: M(Math.min(...slab.map((p) => p[1]))),
  });
}
// Which end is the nose: the end whose cross-section area is smaller.
const area = (st) => st.halfWidth * (st.top - st.bottom);
const noseAtPlusZ = stations.length > 1 && area(stations.at(-1)) < area(stations[0]);

// A reference model is usually a WHOLE SET, not one car, so its section repeats once per car with a
// neck at each gangway. The city view builds a train from one cab car and one intermediate car, so
// fold the set down to those two. --pitch is the car's coupler pitch in metres (the fleet
// catalogue's pitchM); without it, guess the pitch from where the necks fall.
function necks(sts) {                                  // local minima of cross-section area
  const out = [];
  for (let i = 1; i < sts.length - 1; i++) {
    if (area(sts[i]) < area(sts[i - 1]) && area(sts[i]) <= area(sts[i + 1])) out.push(sts[i].z);
  }
  return out;
}
const neckZ = necks(stations);
const gaps = neckZ.slice(1).map((z, i) => +(z - neckZ[i]).toFixed(2));
const guessedPitch = gaps.length ? +(gaps.slice().sort((a, b) => a - b)[gaps.length >> 1]).toFixed(2) : null;
const pitch = flag('pitch', null) ? Number(flag('pitch')) : guessedPitch;

function fold(fromZ, toZ) {                            // one car's stations, its own nose end at +Z
  const inside = stations.filter((s) => s.z >= fromZ && s.z <= toZ);
  const mid = (fromZ + toZ) / 2;
  return inside.map((s) => ({ ...s, z: +(s.z - mid).toFixed(3) }));
}
let cabCar = null, midCar = null;
if (pitch && LEN * ratio > pitch * 1.5) {
  const half = pitch / 2, endZ = (whole.z[1] - whole.z[0]) * ratio / 2;
  const noseEnd = noseAtPlusZ ? endZ : -endZ;
  cabCar = noseAtPlusZ ? fold(noseEnd - pitch, noseEnd) : fold(noseEnd, noseEnd + pitch);
  if (!noseAtPlusZ) cabCar = cabCar.map((s) => ({ ...s, z: -s.z })).reverse();   // turn it to face +Z
  midCar = fold(-half, half);
}

const result = {
  file, triangles, axisAlongCar: 'xyz'[along], scaleApplied: ratio,
  size: { length: M(LEN), width: M(WIDE), height: M(TALL) },
  noseAtPlusZ, guessedPitch, pitch, materials, stations, cabCar, midCar,
};

if (asJson) { console.log(JSON.stringify(result, null, 2)); process.exit(0); }

console.log(`${file}`);
console.log(`  ${triangles} triangles; runs along model ${'xyz'[along]}`);
console.log(`  ${M(LEN)} long x ${M(WIDE)} wide x ${M(TALL)} tall${ratio !== 1 ? ' (scaled)' : ''}`);
if (ratio === 1 && LEN < 10) console.log('  NOTE: under 10 units long — this model is probably not in metres. Re-run with --metres <real length> to scale.');
console.log(`  the nose is at ${noseAtPlusZ ? '+Z (as the city view wants it)' : '-Z (turn it round)'}`);
console.log('\n  material                        colour    metal rough   share  height band   along car');
for (const m of materials) {
  console.log(`  ${m.name.padEnd(30).slice(0, 30)}  ${m.colour}  ${String(m.metalness).padEnd(5)} ${String(m.roughness).padEnd(5)}  ${String(m.share).padEnd(6)} ${String(m.heightBand[0]).padStart(5)}..${String(m.heightBand[1]).padEnd(5)} ${String(m.lengthBand[0]).padStart(5)}..${m.lengthBand[1]}`);
}
const table = (label, sts) => {
  console.log(`\n  ${label}`);
  console.log('    z        halfWidth  top     bottom');
  for (const s of sts) console.log(`    ${String(s.z).padStart(7)}  ${String(s.halfWidth).padStart(9)}  ${String(s.top).padStart(6)}  ${String(s.bottom).padStart(6)}`);
};
if (guessedPitch) console.log(`\n  the section necks every ${guessedPitch} m: that is the coupler pitch, so this model is a whole set of about ${Math.round((LEN * ratio) / guessedPitch)} cars.`);
if (cabCar && midCar) {
  table(`cab car, folded out of the set ("${bodyOnly}", nose at +Z) — the stations of a lofted shell:`, cabCar);
  table('intermediate car, folded out of the middle of the set:', midCar);
} else {
  table(`cross-section of "${bodyOnly}" along the car (the stations of a lofted shell):`, stations);
}
