// Decision 467: the first of the owner's Meshy street props in the 3D map.
// Reads the high-quality GLBs of `meshy-batch-2026-10/glb-hq/` (in
// a91453/railway-assets-private), bakes each triangle's texture colour
// (tools/glb-to-m3dmodel's sampler), sorts it into the game's colours,
// simplifies the welded mesh with meshoptimizer (MIT, pinned by
// tools/glb-to-m3dmodel/package.json) within a distance limit, colours each
// new triangle by what the original triangles under it were, and writes
// `.m3dmodel` files whose header keeps the Meshy task record (Meshy's terms
// §2.4). Same inputs, same bytes.
//
// usage (repository root, Node 22, tools/glb-to-m3dmodel's npm ci done):
//   node tools/meshy-props/build.mjs <meshy-batch-2026-10 folder> <output folder>
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { accessor, applyMatrix, readGlb, scenePrimitives } from '../glb-to-m3dmodel/glb.mjs';
import { area, directions, triangleColor } from '../glb-to-m3dmodel/convert.mjs';
import { MeshoptSimplifier } from '../glb-to-m3dmodel/node_modules/meshoptimizer/index.js';

const root = fileURLToPath(new URL('../..', import.meta.url));
const generated = JSON.parse(readFileSync(resolve(root, 'tools/meshy/generated.json'), 'utf8'));

// The game's colours (Map3DPalette, StationKitBuilder; RGB as written in
// Swift). The app passes them through Map3DLook.colour when it reads them.
const colours = {
  postGreen: 0x2E8B4E, postRed: 0xC8382E, slot: 0x1E5A34, slotRed: 0x82261F, foot: 0x4A4F57, door: 0x8C9298,
  signWhite: 0xF2F3F1, signFrame: 0x3F6FA8, steel: 0x9AA0A8,
};

function hsl([r, g, b]) {
  const max = Math.max(r, g, b) / 255, min = Math.min(r, g, b) / 255, light = (max + min) / 2;
  const sat = max === min ? 0 : (max - min) / (1 - Math.abs(2 * light - 1));
  return { light, sat, chroma: max - min, green: g > r + 20 && g > b + 10, blue: b > r + 40 };
}

// Each prop: its source, how it stands, its size, budget and limit, and
// which game colour each baked colour becomes.
const recipes = [
  {
    // Taiwan's post boxes stand in pairs, red (prompt mail) and green
    // (ordinary mail), one shape: the green one's pillar, twice.
    id: 'meshy-post-boxes', source: 'mailbox-green', height: 1.15, triangles: 520, maxError: 0.006,
    face: 'slot', pair: { gap: 0.18, recolour: { postGreen: 'postRed', slot: 'slotRed' } }, edge: { slot: true },
    // The batch's box: green all over, a dark grey slot and door on one
    // side (z 0.4–0.68 of its height), a dark foot; the dark ring under
    // its dome is the body's.
    classify(c, z) {
      const { light, sat, green } = hsl(c);
      if (z < 0.1 && light < 0.4) return 'foot';
      if (sat < 0.2 && light < 0.4) return z >= 0.4 && z <= 0.68 ? 'slot' : 'postGreen';
      if (sat < 0.15 && light > 0.4) return 'door';
      return green || sat >= 0.2 ? 'postGreen' : 'foot';
    },
  },
  {
    // A stop's sign on its own pole, where the pavement has no room for a
    // shelter: a tall board on a short post, its light grey face (white in
    // the game) in a blue frame, across the pavement, its face along the
    // street.
    id: 'meshy-bus-stop-pole', source: 'bus-stop-pole', height: 2.8, triangles: 300, maxError: 0.01,
    face: 'thin-x',
    classify(c, z) {
      // A pale face's saturation runs high; its chroma does not.
      const { light, sat, chroma, blue } = hsl(c);
      if (light > 0.7 && chroma < 0.2) return 'signWhite';
      if (blue && sat > 0.35 && z > 0.15) return 'signFrame';
      return 'steel';
    },
  },
];

function bake(bytes) {
  const gltf = readGlb(bytes), images = new Map(), out = [];
  for (const { primitive, matrix } of scenePrimitives(gltf)) {
    if ((primitive.mode ?? 4) !== 4) throw new Error('only triangles');
    const positions = accessor(gltf, primitive.attributes.POSITION), uvs = accessor(gltf, primitive.attributes.TEXCOORD_0);
    const indices = accessor(gltf, primitive.indices), material = gltf.json.materials?.[primitive.material];
    for (let i = 0; i < indices.length; i += 3) {
      const ids = [indices[i][0], indices[i + 1][0], indices[i + 2][0]];
      const points = ids.map(k => directions('+x', applyMatrix(matrix, positions[k])));
      if (area(points) < 1e-14) continue;
      out.push({ points, color: triangleColor(gltf, material, ids.map(k => uvs[k]), null, images) });
    }
  }
  return { gltf, triangles: out };
}

const centre = t => [0, 1, 2].map(a => (t[0][a] + t[1][a] + t[2][a]) / 3);

// Turn about z so the prop faces as its recipe says: the post box's slot
// toward +y (the road), the sign's thin side along x.
function facing(recipe, triangles) {
  let angle;
  if (recipe.face === 'slot') {
    const slots = triangles.filter(t => t.cls === 'slot');
    if (slots.length === 0) throw new Error(`${recipe.id}: no slot to face the road with`);
    const [x, y] = [0, 1].map(a => slots.reduce((s, t) => s + t.mid[a], 0) / slots.length);
    angle = Math.PI / 2 - Math.atan2(y, x);
    // The batch's texture is mottled: dark patches round the back are
    // the body's, the slot and door only the ones on the front.
    const front = Math.atan2(y, x);
    for (const t of slots) {
      const off = Math.abs(Math.atan2(Math.sin(Math.atan2(t.mid[1], t.mid[0]) - front), Math.cos(Math.atan2(t.mid[1], t.mid[0]) - front)));
      if (off > Math.PI * 7 / 18) t.cls = 'postGreen';
    }
  } else {
    const boards = triangles.filter(t => t.cls === 'signWhite');
    if (boards.length === 0) throw new Error(`${recipe.id}: no board to face the street with`);
    const spread = a => Math.max(...boards.map(t => t.mid[a])) - Math.min(...boards.map(t => t.mid[a]));
    angle = spread(0) < spread(1) ? 0 : Math.PI / 2;
  }
  const c = Math.cos(angle), s = Math.sin(angle);
  for (const t of triangles) {
    t.points = t.points.map(([x, y, z]) => [x * c - y * s, x * s + y * c, z]);
    t.mid = centre(t.points);
  }
}

function standUp(triangles, height) {
  const all = triangles.flatMap(t => t.points);
  const low = [0, 1, 2].map(a => all.reduce((m, p) => Math.min(m, p[a]), Infinity));
  const high = [0, 1, 2].map(a => all.reduce((m, p) => Math.max(m, p[a]), -Infinity));
  const scale = height / (high[2] - low[2]), mx = (low[0] + high[0]) / 2, my = (low[1] + high[1]) / 2;
  for (const t of triangles) {
    t.points = t.points.map(([x, y, z]) => [(x - mx) * scale, (y - my) * scale, (z - low[2]) * scale]);
    t.mid = centre(t.points);
  }
}

// Points spread over the original triangles (one at a small one's middle,
// a barycentric grid over a large one, about one per quarter cell), in
// cells, for the triangle nearest a point: a large flat face's middle can
// be farther than a small frame's, but its points are not.
function grid(triangles, step) {
  const cells = new Map(), key = (x, y, z) => `${x},${y},${z}`, samples = [];
  triangles.forEach((t, i) => {
    const rows = Math.min(40, Math.max(1, Math.ceil(Math.sqrt(area(t.points) * 8) / step)));
    for (let a = 0; a < rows; a++) for (let b = 0; b < rows - a; b++) {
      const w = [(3 * a + 1) / (3 * rows), (3 * b + 1) / (3 * rows)];
      w.push(1 - w[0] - w[1]);
      const at = [0, 1, 2].map(k => w[0] * t.points[0][k] + w[1] * t.points[1][k] + w[2] * t.points[2][k]);
      const k = key(...at.map(v => Math.floor(v / step)));
      if (!cells.has(k)) cells.set(k, []);
      cells.get(k).push(samples.length);
      samples.push({ at, i });
    }
  });
  return point => {
    const home = point.map(v => Math.floor(v / step));
    for (let r = 1; r < 64; r++) {
      let best = -1, distance = Infinity;
      for (let dx = -r; dx <= r; dx++) for (let dy = -r; dy <= r; dy++) for (let dz = -r; dz <= r; dz++) {
        for (const s of cells.get(key(home[0] + dx, home[1] + dy, home[2] + dz)) ?? []) {
          const m = samples[s].at, d = (m[0] - point[0]) ** 2 + (m[1] - point[1]) ** 2 + (m[2] - point[2]) ** 2;
          if (d < distance || (d === distance && samples[s].i < best)) { distance = d; best = samples[s].i; }
        }
      }
      // A point within r cells' side is the nearest of all: the cube
      // searched holds every point that near.
      if (best >= 0 && Math.sqrt(distance) <= r * step) return best;
    }
    throw new Error('no triangle near');
  };
}

async function simplify(triangles, recipe) {
  await MeshoptSimplifier.ready;
  const index = new Map(), positions = [], corners = new Uint32Array(triangles.length * 3);
  triangles.forEach((t, i) => t.points.forEach((p, k) => {
    const key = p.map(v => Math.round(v * 1e5)).join(',');
    let at = index.get(key);
    if (at === undefined) { at = positions.length / 3; index.set(key, at); positions.push(...p); }
    corners[i * 3 + k] = at;
  }));
  const points = new Float32Array(positions);
  const [kept, error] = MeshoptSimplifier.simplify(corners, points, 3, recipe.triangles * 3, recipe.maxError, ['ErrorAbsolute']);
  const nearest = grid(triangles, recipe.height / 24), order = Object.keys(colours);
  const out = [];
  for (let i = 0; i < kept.length; i += 3) {
    const p = [0, 1, 2].map(k => [0, 1, 2].map(a => points[kept[i + k] * 3 + a]));
    if (area(p) < 1e-10) continue;
    // Points spread evenly over it (triangleColor's 21) vote for the
    // colour under them, so a long sliver takes its middle's colour, not
    // its ends'.
    const votes = new Map();
    for (let i = 0; i < 6; i++) for (let j = 0; j < 6 - i; j++) {
      const w = [(i + 1) / 9, (j + 1) / 9, (7 - i - j) / 9];
      const at = [0, 1, 2].map(a => w[0] * p[0][a] + w[1] * p[1][a] + w[2] * p[2][a]);
      const cls = triangles[nearest(at)].cls;
      votes.set(cls, (votes.get(cls) ?? 0) + 1);
    }
    let cls = [...votes].sort((a, b) => b[1] - a[1] || order.indexOf(a[0]) - order.indexOf(b[0]))[0][0];
    // A dark part (the slot and door, a deeper shade of the body: a
    // recess, not a hole) only where two thirds of the points are on it,
    // so a sliver half across it does not draw a spike.
    if (recipe.edge?.[cls] && votes.get(cls) < 14) {
      cls = [...votes].filter(([c]) => c !== cls).sort((a, b) => b[1] - a[1] || order.indexOf(a[0]) - order.indexOf(b[0]))[0]?.[0] ?? cls;
    }
    out.push({ points: p, cls });
  }
  return { triangles: out, error };
}

function write(recipe, triangles, record) {
  const provenance = Buffer.from(JSON.stringify(record), 'utf8');
  const padded = Math.ceil(provenance.length / 4) * 4, out = Buffer.alloc(16 + padded + triangles.length * 52);
  out.write('M3DM', 0, 'ascii');
  out.writeUInt16LE(1, 4);
  out.writeUInt32LE(triangles.length, 8);
  out.writeUInt32LE(provenance.length, 12);
  provenance.copy(out, 16);
  triangles.forEach((t, i) => {
    const at = 16 + padded + i * 52, rgb = colours[t.cls];
    // Swift's rgb(0xRRGGBB): red in the low byte, alpha 255.
    const colour = ((rgb >> 16) | (rgb & 0xFF00) | ((rgb & 0xFF) << 16) | 0xFF000000) >>> 0;
    t.points.forEach((p, k) => {
      p.forEach((v, a) => out.writeFloatLE(v, at + 4 + k * 16 + a * 4));
      out.writeUInt32LE(colour, at + 4 + k * 16 + 12);
    });
  });
  return out;
}

async function build(batch, folder, recipe) {
  const bytes = readFileSync(join(batch, 'glb-hq', `${recipe.source}.glb`));
  const { gltf, triangles } = bake(bytes);
  // Sort by the raw height (Meshy's -1..1) before standing it up.
  const all = triangles.flatMap(t => t.points);
  const bottom = all.reduce((m, p) => Math.min(m, p[2]), Infinity), top = all.reduce((m, p) => Math.max(m, p[2]), -Infinity);
  for (const t of triangles) {
    t.mid = centre(t.points);
    t.cls = recipe.classify(t.color, (t.mid[2] - bottom) / (top - bottom));
  }
  standUp(triangles, recipe.height);
  facing(recipe, triangles);
  standUp(triangles, recipe.height);
  const { triangles: made, error } = await simplify(triangles, recipe);
  let result = made;
  if (recipe.pair) {
    const xs = made.flatMap(t => t.points.map(p => p[0])), width = Math.max(...xs) - Math.min(...xs);
    const shift = (width + recipe.pair.gap) / 2;
    result = [
      ...made.map(t => ({ points: t.points.map(([x, y, z]) => [x - shift, y, z]), cls: recipe.pair.recolour[t.cls] ?? t.cls })),
      ...made.map(t => ({ points: t.points.map(([x, y, z]) => [x + shift, y, z]), cls: t.cls })),
    ];
  }
  const source = generated[recipe.source];
  if (!source?.tasks?.length) throw new Error(`tools/meshy/generated.json has no tasks for ${recipe.source}`);
  const record = {
    asset: gltf.json.asset,
    ai_generated: 'Meshy text-to-3D (meshy-7.1), the owner\'s account; simplified and recoloured for the game',
    generated: { model: recipe.source, tasks: source.tasks, credits: source.credits,
      raw_sha256: createHash('sha256').update(bytes).digest('hex') },
    recipe: { id: recipe.id, height_m: recipe.height, triangles: recipe.triangles, max_error_m: recipe.maxError,
      simplifier: 'meshoptimizer 1.3.0 simplify', pair: recipe.pair ?? null },
  };
  const file = write(recipe, result, record);
  writeFileSync(join(folder, `${recipe.id}.m3dmodel`), file);
  const counts = {};
  for (const t of result) counts[t.cls] = (counts[t.cls] ?? 0) + 1;
  process.stdout.write(`${recipe.id}: ${triangles.length} -> ${result.length} triangles, error ${error.toFixed(4)} m, ${JSON.stringify(counts)}\n`);
}

const [batch, folder] = process.argv.slice(2);
if (!batch || !folder) throw new Error('usage: node tools/meshy-props/build.mjs <meshy-batch-2026-10> <output folder>');
mkdirSync(folder, { recursive: true });
for (const recipe of recipes) await build(batch, folder, recipe);
