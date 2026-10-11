// Turns a reference model of a train into the handful of numbers the city view's code-drawn stock
// needs. A reference GLB is far too heavy to ship (the owner's EMU3000 is 199,588 triangles; a
// whole 12-car set in the city view is about 3,300), but it is ground truth for shape and colour,
// and reading it beats reading a photograph: it has no perspective, no specular streak mistaken
// for paint, and no hidden far side.
//
//   node .claude/skills/rolling-stock/measure.cjs <reference.glb|.bin|.bin.gz> [--slices 20] [--json]
//
// Two reference formats, both the owner's: a .glb, and the interleaved float32 meshes his rail-3d
// car shed exports (stride 10 — position, normal, colour, gloss; see rail-3d/assets/wenhu-v1/
// wenhu.js). The second carries no materials but a colour per vertex, so its "materials" below are
// the colour regions clustered out of the mesh.
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
const zlib = require('zlib');

const args = process.argv.slice(2);
const file = args.find((a) => !a.startsWith('--'));
const flag = (n, d) => { const i = args.indexOf(`--${n}`); return i >= 0 && args[i + 1] && !args[i + 1].startsWith('--') ? args[i + 1] : d; };
const SLICES = Number(flag('slices', '20'));
const asJson = args.includes('--json');
if (!file) { console.error('usage: measure.cjs <reference.glb> [--slices 20] [--json]'); process.exit(2); }

let buf = fs.readFileSync(file);
if (file.endsWith('.gz')) buf = zlib.gunzipSync(buf);
const isWenhu = buf.readUInt32LE(0) !== 0x46546c67;

// ---- The car shed's interleaved meshes: a triangle soup with a colour on every vertex.
let wenhu = null;
if (isWenhu) {
  const STRIDE = 10;
  if (buf.byteLength % (STRIDE * 4)) { console.error('not a glTF binary, and not a stride-10 float mesh either'); process.exit(2); }
  const f = new Float32Array(buf.buffer, buf.byteOffset, buf.byteLength / 4);
  const count = f.length / STRIDE;
  const points = [], colours = [];
  for (let i = 0; i < count; i++) {
    const o2 = i * STRIDE;
    points.push([f[o2], f[o2 + 1], f[o2 + 2]]);
    colours.push([f[o2 + 6], f[o2 + 7], f[o2 + 8]]);
  }
  wenhu = { points, colours, triangles: count / 3 };
}

// ---- GLB and the glTF node hierarchy (https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html)
if (!isWenhu && buf.readUInt32LE(0) !== 0x46546c67) { console.error('not a glTF binary'); process.exit(2); }
let o = 12, gltf = null, bin = Buffer.alloc(0);
while (!isWenhu && o < buf.length) {
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
for (const [i, n] of (gltf?.nodes ?? []).entries()) for (const c of n.children ?? []) parents.set(c, i);
function worldMatrix(i) {
  let m = trs(gltf.nodes[i]);
  for (let p = parents.get(i); p !== undefined; p = parents.get(p)) m = mul(trs(gltf.nodes[p]), m);
  return m;
}
const byMaterial = new Map();
let vertices = [], triangles = 0;
const faces = [];                                      // every triangle, for sampling the surface
if (wenhu) {
  // Cluster the per-vertex colours into regions, so the rest of this reads a .bin exactly as a GLB.
  const key = (c) => c.map((v) => Math.round(v * 24)).join(',');
  for (let i = 0; i < wenhu.points.length; i++) {
    const k = key(wenhu.colours[i]);
    if (!byMaterial.has(k)) byMaterial.set(k, { material: null, colour: wenhu.colours[i], triangles: 0, points: [] });
    const rec = byMaterial.get(k);
    rec.triangles += 1 / 3;
    rec.points.push(wenhu.points[i]);
  }
  for (const rec of byMaterial.values()) rec.triangles = Math.round(rec.triangles);
  vertices = wenhu.points;
  triangles = wenhu.triangles;
  for (let i = 0; i + 2 < wenhu.points.length; i += 3) faces.push([wenhu.points[i], wenhu.points[i + 1], wenhu.points[i + 2]]);
}
for (const [i, node] of (isWenhu ? [] : gltf.nodes ?? []).entries()) {
  if (node.mesh == null) continue;
  const m = worldMatrix(i);
  for (const prim of gltf.meshes[node.mesh].primitives) {
    const pos = read(prim.attributes.POSITION).map((p) => apply(m, p));
    const idx = prim.indices != null ? read(prim.indices) : pos.map((_, k) => k);
    for (let k = 0; k + 2 < idx.length; k += 3) faces.push([pos[idx[k]], pos[idx[k + 1]], pos[idx[k + 2]]]);
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

const framedPoints = new Map();
const materials = [...byMaterial.entries()].map(([name, rec]) => {
  const ps = rec.points.map(frame), b = bound(ps);
  framedPoints.set(rec.colour ? `colour region ${hex(rec.colour)}` : name, ps);
  const mat = rec.material != null ? gltf.materials[rec.material] : {};
  const pbr = mat.pbrMetallicRoughness ?? {};
  return {
    name: rec.colour ? `colour region ${hex(rec.colour)}` : name,
    colour: hex(rec.colour ?? pbr.baseColorFactor ?? [1, 1, 1, 1]),
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
// Which points make the body: a GLB names its materials, so the biggest one is the shell. A
// vertex-coloured mesh has no materials and its colours vary with baked shading, so the biggest
// colour region is as likely to be the glazing — there, the whole mesh IS the car.
const bodyOnly = isWenhu ? 'the whole mesh' : materials[0].name;
// Sample the SURFACE, not the vertices. A low-poly reference carries a car's side as a handful of
// long quads, so a slice in the middle of one contains no vertex at all and reads as empty — on
// the owner's EMU3000 that made whole metres of body vanish and left only the pantograph.
const step = (LEN / SLICES) / 2;
function surface(tris) {
  const out = [];
  const emit = (a, b, c, depth) => {
    out.push(a, b, c);
    if (depth >= 4) return;
    const zs = [a[2], b[2], c[2]];
    if (Math.max(...zs) - Math.min(...zs) <= step) return;
    const mid = (p, q) => [(p[0] + q[0]) / 2, (p[1] + q[1]) / 2, (p[2] + q[2]) / 2];
    const ab = mid(a, b), bc = mid(b, c), ca = mid(c, a);
    emit(a, ab, ca, depth + 1); emit(ab, b, bc, depth + 1); emit(ca, bc, c, depth + 1); emit(ab, bc, ca, depth + 1);
  };
  for (const t of tris) emit(t[0], t[1], t[2], 0);
  return out;
}
const shell = surface(faces.map((t) => t.map(frame)));
const stations = [];
for (let s = 0; s < SLICES; s++) {
  const z0 = whole.z[0] + (LEN * s) / SLICES, z1 = z0 + LEN / SLICES;
  const slab = shell.filter((p) => p[2] >= z0 && p[2] < z1);
  if (slab.length < 8) continue;
  // A reference carries its bogies and roof kit in the same mesh, and taking the extremes of a
  // slice would read the pantograph as the roof and the bogie as the floor. Width comes from the
  // body's flank alone, and top and bottom from percentiles, which ignore sparse outliers.
  const flank = slab.filter((p) => p[1] >= whole.y[0] + TALL * 0.3 && p[1] <= whole.y[0] + TALL * 0.8);
  const halfWidth = Math.max(...(flank.length ? flank : slab).map((p) => Math.abs(p[0])));
  const pick = (ps, q) => { const v = ps.map((p) => p[1]).sort((a, b) => a - b); return v[Math.min(v.length - 1, Math.max(0, Math.round(q * (v.length - 1))))]; };
  const sides = slab.filter((p) => Math.abs(p[0]) >= halfWidth * 0.6);
  stations.push({
    z: M((z0 + z1) / 2),
    halfWidth: M(halfWidth),
    top: M(pick(slab, 0.97)),
    bottom: M(sides.length > 4 ? pick(sides, 0.03) : pick(slab, 0.03)),
  });
}
// Which end is the nose: the end whose cross-section area is smaller.
const area = (st) => st.halfWidth * (st.top - st.bottom);
const noseAtPlusZ = stations.length > 1 && area(stations.at(-1)) < area(stations[0]);

// A reference model is usually a WHOLE SET, not one car, so its section repeats once per car with a
// neck at each gangway. The city view builds a train from one cab car and one intermediate car, so
// fold the set down to those two. --pitch is the car's coupler pitch in metres (the fleet
// catalogue's pitchM); without it, guess the pitch from where the necks fall.
// A gangway neck is a DEEP local minimum, not any dip: a door recess and a roof box each make a
// shallow one, and counting those once read a single 21 m car as a seven-car set on a 2.9 m pitch.
const MIN_PITCH = 15, MAX_PITCH = 30;                  // no main-line car is coupled outside this
function necks(sts) {
  const areas = sts.map(area).slice().sort((a, b) => a - b);
  const median = areas[areas.length >> 1];
  const out = [];
  for (let i = 1; i < sts.length - 1; i++) {
    const a = area(sts[i]);
    if (a < area(sts[i - 1]) && a <= area(sts[i + 1]) && a < median * 0.92) out.push(sts[i].z);
  }
  return out;
}
const neckZ = necks(stations);
const gaps = neckZ.slice(1).map((z, i) => +((z - neckZ[i]) * ratio).toFixed(2)).filter((g) => g >= MIN_PITCH && g <= MAX_PITCH);
const guessedPitch = gaps.length ? +(gaps.slice().sort((a, b) => a - b)[gaps.length >> 1]).toFixed(2) : null;
const asked = flag('pitch', null) ? Number(flag('pitch')) : null;
const pitch = asked ?? guessedPitch;

function fold(fromZ, toZ) {                            // one car's stations, its own nose end at +Z
  const inside = stations.filter((s) => s.z >= fromZ && s.z <= toZ);
  const mid = (fromZ + toZ) / 2;
  return inside.map((s) => ({ ...s, z: +(s.z - mid).toFixed(3) }));
}
let cabCar = null, midCar = null;
if (pitch && LEN * ratio > pitch * 1.8) {   // only a model holding at least two cars can be folded
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
if (pitch && cabCar) console.log(`\n  the section necks every ${pitch} m${asked ? ' (given)' : ' (measured)'}: that is the coupler pitch, so this model holds about ${Math.round((LEN * ratio) / pitch)} cars.`);
else console.log(`\n  one car: no repeating gangway neck found, so nothing to fold.`);
if (cabCar && midCar) {
  table(`cab car, folded out of the set ("${bodyOnly}", nose at +Z) — the stations of a lofted shell:`, cabCar);
  table('intermediate car, folded out of the middle of the set:', midCar);
} else {
  table(`cross-section of "${bodyOnly}" along the car (the stations of a lofted shell):`, stations);
}
