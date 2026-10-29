// Decision 458: the 3D map's conifers, bushes and horizontal tank, recombined
// from three Kenney (CC0) models (art-style §7: own trunk, the crown's tiers
// restacked at other counts and proportions; bushes grouped into clumps; the
// tank lengthened on its own pad and middle saddle), written as static GLBs
// for tools/glb-to-m3dmodel/bridge.mjs.
//
// usage: node tools/kenney-props/reshape.mjs OUT_DIR
// Reads source/*.glb (Kenney's models baked to the game's palette by the
// free-assets trial, SOURCE.md); writes OUT_DIR/<id>.glb and
// OUT_DIR/<id>.manifest.json for each model in MODELS. Deterministic.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const out = process.argv[2];
if (!out) throw new Error('usage: reshape.mjs OUT_DIR');
mkdirSync(out, { recursive: true });

// The game's colours (Map3DPalette), sRGB bytes: bridge.mjs multiplies
// COLOR_0 into its byte colour as it stands (the trial's first pitfall).
const trunk = [0x8a, 0x6a, 0x4f], concrete = [0xc9, 0xc8, 0xc2], tankWhite = [0xe4, 0xe2, 0xdc], tankStand = [0x6e, 0x74, 0x7b];

/// A plain GLB's triangles, y up: [{ p: [[x,y,z]×3], c: [r,g,b] }].
function read(name) {
  const bytes = readFileSync(resolve(here, 'source', name));
  const jsonLength = bytes.readUInt32LE(12);
  const json = JSON.parse(bytes.subarray(20, 20 + jsonLength).toString());
  const bin = bytes.subarray(20 + jsonLength + 8);
  const view = index => {
    const a = json.accessors[index], v = json.bufferViews[a.bufferView];
    return new Float32Array(bin.buffer.slice(bin.byteOffset + (v.byteOffset ?? 0), bin.byteOffset + (v.byteOffset ?? 0) + a.count * 12));
  };
  const triangles = [];
  for (const mesh of json.meshes) for (const primitive of mesh.primitives) {
    const p = view(primitive.attributes.POSITION), c = view(primitive.attributes.COLOR_0);
    for (let t = 0; t < p.length / 9; t++) {
      triangles.push({
        p: [0, 1, 2].map(k => [p[(t * 3 + k) * 3], p[(t * 3 + k) * 3 + 1], p[(t * 3 + k) * 3 + 2]]),
        c: [0, 1, 2].map(k => Math.round(c[t * 9 + k] * 255)),
      });
    }
  }
  return triangles;
}

/// `triangles` turned `degrees` about y, scaled (`across` in x and z,
/// `up` in y) about the origin, then moved by `by`.
function place(triangles, { degrees = 0, across = 1, up = 1, by = [0, 0, 0], colour } = {}) {
  const a = degrees * Math.PI / 180, cos = Math.cos(a), sin = Math.sin(a);
  return triangles.map(t => ({
    c: colour ?? t.c,
    p: t.p.map(([x, y, z]) => [(x * cos + z * sin) * across + by[0], y * up + by[1], (-x * sin + z * cos) * across + by[2]]),
  }));
}

/// `triangles` of a convex shape round `centre`, each wound to face out.
function outward(triangles, centre) {
  return triangles.map(t => {
    const [a, b, c] = t.p, u = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], v = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
    const n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]];
    const m = [0, 1, 2].map(k => (a[k] + b[k] + c[k]) / 3 - centre[k]);
    return n[0] * m[0] + n[1] * m[1] + n[2] * m[2] < 0 ? { c: t.c, p: [a, c, b] } : t;
  });
}

/// A closed prism of `sides` from `bottom` to `top` (y), radii `r0`, `r1`.
function prism({ sides, bottom, top, r0, r1, colour, x = 0, z = 0 }) {
  const ring = (y, r) => Array.from({ length: sides }, (_, i) => {
    const a = (i + 0.5) * 2 * Math.PI / sides;
    return [x + Math.cos(a) * r, y, z + Math.sin(a) * r];
  });
  const lo = ring(bottom, r0), hi = ring(top, r1), triangles = [];
  for (let i = 0; i < sides; i++) {
    const j = (i + 1) % sides;
    triangles.push({ c: colour, p: [lo[i], hi[j], lo[j]] }, { c: colour, p: [lo[i], hi[i], hi[j]] });
    if (i > 0 && i < sides - 1) {
      triangles.push({ c: colour, p: [hi[0], hi[i + 1], hi[i]] }, { c: colour, p: [lo[0], lo[i], lo[i + 1]] });
    }
  }
  return outward(triangles, [x, (bottom + top) / 2, z]);
}

/// A box from (x0, y0, z0) to (x1, y1, z1).
function box([x0, y0, z0], [x1, y1, z1], colour) {
  const v = (i) => [i & 1 ? x1 : x0, i & 2 ? y1 : y0, i & 4 ? z1 : z0];
  const faces = [[0, 2, 6, 4], [1, 5, 7, 3], [0, 4, 5, 1], [2, 3, 7, 6], [0, 1, 3, 2], [4, 6, 7, 5]];
  return outward(faces.flatMap(([a, b, c, d]) => [{ c: colour, p: [v(a), v(b), v(c)] }, { c: colour, p: [v(a), v(c), v(d)] }]),
    [(x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2]);
}

// MARK: - Conifers

// Kenney's tree_pineTallA: a four-sided trunk under three ragged tiers,
// each tier the triangles whose lowest corner is at its base (its underside
// ledge and its sides).
const pine = read('tree_pineTallA.glb');
const isCrown = t => t.c[1] > 150;
const tierBases = [4.54, 5.92, 7.62];
const tiers = tierBases.map(base => {
  const own = pine.filter(t => isCrown(t) && Math.abs(Math.min(...t.p.map(p => p[1])) - base) < 0.02);
  const top = Math.max(...own.flatMap(t => t.p.map(p => p[1])));
  return { triangles: place(own, { by: [0, -base, 0] }), height: top - base };
});
if (tiers.reduce((n, t) => n + t.triangles.length, 0) !== pine.filter(isCrown).length) throw new Error('a crown triangle in no tier');

/// A conifer: this project's six-sided trunk to `trunkHeight`, then the
/// tiers `stack` ([tier, across, up, degrees]) each overlapping the one
/// below by 0.2 m.
function conifer(trunkHeight, stack) {
  let y = trunkHeight;
  const crown = stack.flatMap(([tier, across, up, degrees]) => {
    const placed = place(tiers[tier].triangles, { degrees, across, up, by: [0, y, 0] });
    y += tiers[tier].height * up - 0.2;
    return placed;
  });
  return [...prism({ sides: 6, bottom: 0, top: trunkHeight + 0.6, r0: 0.24, r1: 0.15, colour: trunk }), ...crown];
}

// MARK: - Bushes

const bush = read('plant_bushLarge.glb');
const lowest = Math.min(...bush.flatMap(t => t.p.map(p => p[1])));
/// Kenney's bush at `across` its size, turned, its foot 0.1 m under the
/// ground at `x`, `z` (so the clump sits into the soil).
const shrub = (across, degrees, x, z) => place(bush, { degrees, across, up: across, by: [x, -lowest * across - 0.1, z] });

// MARK: - Tank

// Kenney's detail-tank: a cream vessel along x on grey saddles and legs.
// Lengthened: everything past x 0.7 moves 2.4 m out, the vessel's long
// sides stretching; a concrete pad and a third saddle of this project's own.
// Its triangles are wound clockwise (every shell inside out: the game draws
// both sides but lights each by the way it winds, so the vessel read as its
// inside), so each is turned round.
const tank = read('detail-tank.glb').map(t => ({
  c: t.c[0] === 255 || t.c[0] === 217 ? tankWhite : t.c,
  p: [t.p[0], t.p[2], t.p[1]].map(([x, y, z]) => [x > 0.7 ? x + 2.4 : x, y + 0.15, z]),
}));
const tankLow = Math.min(...tank.flatMap(t => t.p.map(p => p[0]))), tankHigh = Math.max(...tank.flatMap(t => t.p.map(p => p[0])));
const middle = (tankLow + tankHigh) / 2;
const tankModel = [
  ...tank,
  ...box([tankLow - 0.5, 0, -2.2], [tankHigh + 0.5, 0.15, 2.2], concrete),
  ...box([middle - 0.25, 0.15, -0.9], [middle + 0.25, 0.7, 0.9], tankStand),
];

export const MODELS = {
  // A slender cedar or fir of the plantations (柳杉, 杉木): five tiers.
  'kenney-pine-tall': conifer(3.2, [[0, 0.95, 1.1, 0], [1, 0.9, 1, 30], [0, 0.75, 1, 60], [1, 0.65, 1, 90], [2, 0.55, 0.95, 120]]),
  // A broader pine (台灣二葉松): three wide tiers, the top cut short.
  'kenney-pine': conifer(2.0, [[0, 1.2, 1, 0], [1, 1.1, 1, 45], [2, 1.0, 0.75, 90]]),
  // A young conifer: two tiers on a short trunk.
  'kenney-pine-young': conifer(0.9, [[1, 0.75, 0.9, 0], [2, 0.65, 0.7, 40]]),
  // Two bushes, and three, as clumps on a plaza's edge or beside the line.
  'kenney-bushes': [...shrub(1, 0, 0, 0), ...shrub(0.7, 70, 1.1, 0.5)],
  'kenney-bushes-large': [...shrub(1.25, 0, 0, 0), ...shrub(0.95, 120, 1.3, 0.6), ...shrub(0.8, 200, -0.6, 1.2)],
  'kenney-tank': tankModel,
};

/// A GLB of `triangles` (POSITION, NORMAL, COLOR_0; flat normals), its one
/// mesh node named `id`.
function glb(id, triangles) {
  const position = new Float32Array(triangles.length * 9), normal = new Float32Array(triangles.length * 9), colour = new Float32Array(triangles.length * 9);
  triangles.forEach((t, i) => {
    const [a, b, c] = t.p, u = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], v = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
    let n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]];
    const length = Math.hypot(...n);
    n = n.map(x => x / length);
    for (let k = 0; k < 3; k++) {
      position.set(t.p[k], i * 9 + k * 3);
      normal.set(n, i * 9 + k * 3);
      colour.set(t.c.map(x => x / 255), i * 9 + k * 3);
    }
  });
  const min = [0, 1, 2].map(k => Math.min(...triangles.flatMap(t => t.p.map(p => p[k]))));
  const max = [0, 1, 2].map(k => Math.max(...triangles.flatMap(t => t.p.map(p => p[k]))));
  const bin = Buffer.concat([position, normal, colour].map(a => Buffer.from(a.buffer)));
  const length = position.byteLength, count = triangles.length * 3;
  const json = {
    asset: { version: '2.0', generator: 'railway-game-ios tools/kenney-props/reshape.mjs', copyright: 'Kenney (www.kenney.nl), CC0 1.0; recombined by this project' },
    scene: 0, scenes: [{ nodes: [0] }], nodes: [{ name: id, mesh: 0 }],
    meshes: [{ name: id, primitives: [{ attributes: { POSITION: 0, NORMAL: 1, COLOR_0: 2 }, material: 0 }] }],
    materials: [{ name: 'vertexColour', pbrMetallicRoughness: { baseColorFactor: [1, 1, 1, 1], metallicFactor: 0, roughnessFactor: 1 } }],
    accessors: [
      { bufferView: 0, componentType: 5126, count, type: 'VEC3', min, max },
      { bufferView: 1, componentType: 5126, count, type: 'VEC3' },
      { bufferView: 2, componentType: 5126, count, type: 'VEC3' },
    ],
    bufferViews: [0, 1, 2].map(i => ({ buffer: 0, byteOffset: i * length, byteLength: length, target: 34962 })),
    buffers: [{ byteLength: bin.length }],
  };
  let text = Buffer.from(JSON.stringify(json));
  text = Buffer.concat([text, Buffer.alloc(-text.length % 4 & 3, 0x20)]);
  const header = Buffer.alloc(12), jsonHead = Buffer.alloc(8), binHead = Buffer.alloc(8);
  header.write('glTF', 0); header.writeUInt32LE(2, 4); header.writeUInt32LE(12 + 8 + text.length + 8 + bin.length, 8);
  jsonHead.writeUInt32LE(text.length, 0); jsonHead.write('JSON', 4);
  binHead.writeUInt32LE(bin.length, 0); binHead.write('BIN\0', 4);
  return Buffer.concat([header, jsonHead, text, binHead, bin]);
}

const sources = { pine: 'tree_pineTallA.glb (Nature Kit 2.1)', bush: 'plant_bushLarge.glb (Nature Kit 2.1)', tank: 'detail-tank.glb (City Kit Industrial 2.0)' };
/// Whether a triangle has some area: one of none has no normal, which
/// glTF-Validator rejects (the stretched tank had two).
const hasArea = ({ p: [a, b, c] }) => {
  const u = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], v = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
  return Math.hypot(u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]) > 1e-9;
};
for (const [id, all] of Object.entries(MODELS)) {
  const triangles = all.filter(hasArea);
  writeFileSync(resolve(out, id + '.glb'), glb(id, triangles));
  const from = id.includes('pine') ? sources.pine : id.includes('bush') ? sources.bush : sources.tank;
  writeFileSync(resolve(out, id + '.manifest.json'), JSON.stringify({
    input: id + '.glb', modelId: id, nodes: [id], front: '+x', units: 'meters', recolorLightPaint: false,
    source: {
      kind: 'non-ai',
      reference: `https://kenney.nl/assets, ${from}, recombined by tools/kenney-props/reshape.mjs`,
      revision: 'Kenney packs downloaded 2026-10-28 (versions and zip SHA-256 in tools/kenney-props/SOURCE.md)',
      license: 'CC0-1.0',
      attribution: 'Kenney (www.kenney.nl); attribution not required',
    },
  }, null, 1) + '\n');
  console.log(id, triangles.length, 'triangles');
}
