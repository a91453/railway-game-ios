#!/usr/bin/env node
// Decision 725: Taipei's temples on the 3D map, their shape from the
// Department of Civil Affairs' "臺北市宗教建築 3D 模型庫" (data.gov.tw 121136,
// Open Government Data License v1.0). Reads each temple's KMZ (unzipped:
// `doc.kml` and the SketchUp COLLADA), drops the ground, the terrain and the
// cut-out trees, sorts every face into a part of the building (roof tile,
// ridge, wall, column, opening, paving) from its slope, height and the
// colour of the photo under it, simplifies with meshoptimizer (pinned in
// tools/glb-to-m3dmodel), lets each new face take the part most of its
// points lie on, and writes it in the game's colours as a `.m3dmodel`. No
// photo, texture or texture colour is kept.
//
//   node tools/tpe-temples/build.mjs <folder of unzipped KMZ> <output folder> [id...]
//
// The folder holds one sub-folder per KMZ, named as the file (`108003/doc.kml`,
// `108003/models/untitled.dae`); fetch.sh downloads and unzips them.
// Output: `<id>.m3dmodel` (native: +x east, +y north, +z up, metres, the
// temple's KML point at the origin, the ground it stands on at z 0) and
// `placements.json` (each temple's point, its size, triangles and error).
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { readCollada, readKml } from './collada.mjs';
import { triangleColour } from './textures.mjs';
import { writeM3dmodel } from './m3dmodel.mjs';
import { recipes, colours } from './recipes.mjs';
import { dedupe, orientOutward } from './orient.mjs';
import { MeshoptSimplifier } from '../glb-to-m3dmodel/node_modules/meshoptimizer/index.js';

const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const cross = (u, v) => [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]];
const normalOf = ([a, b, c]) => cross(sub(b, a), sub(c, a));
const areaOf = t => Math.hypot(...normalOf(t)) / 2;
const centre = ps => [0, 1, 2].map(k => (ps[0][k] + ps[1][k] + ps[2][k]) / 3);

// Hue (degrees), saturation and lightness 0..1.
export function hsl([r, g, b]) {
  r /= 255; g /= 255; b /= 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b), l = (max + min) / 2, d = max - min;
  if (d === 0) return [0, 0, l];
  const s = d / (1 - Math.abs(2 * l - 1));
  const h = max === r ? ((g - b) / d + 6) % 6 : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return [h * 60, s, l];
}

// Metres east and north of `from` to `to` (lat/lon), on the local tangent.
function offset(from, to) {
  const metresPerDegree = 111_320;
  return [(to.longitude - from.longitude) * metresPerDegree * Math.cos(from.latitude * Math.PI / 180),
    (to.latitude - from.latitude) * metresPerDegree];
}

// The part of the building a source face is, before simplification.
export function classify(t, recipe) {
  const n = normalOf(t.points), length = Math.hypot(...n);
  if (length === 0) return null;
  const nz = n[2] / length, z = centre(t.points)[2];
  const [h, s, l] = hsl(t.rgb);
  const red = (h < 22 || h > 340) && s > 0.32 && l > 0.18 && l < 0.7;
  if (nz > 0.3 && z > recipe.eave) {
    // Cut porcelain and painted ridges: bright or strongly coloured.
    if ((s > 0.45 && l > 0.35) || l > 0.72) return 'ridge';
    return 'roof';
  }
  if (nz > 0.7) return 'paving';
  if (nz < -0.3) return 'soffit';
  if (red) return 'column';
  if (l < recipe.dark) return 'opening';
  return recipe.stoneWalls && s < 0.12 ? 'stone' : 'wall';
}

function read(folder, recipe) {
  const origin = readKml(join(folder, recipe.files[0], 'doc.kml'));
  const triangles = [], sources = [];
  for (const file of recipe.files) {
    const kml = readKml(join(folder, file, 'doc.kml'));
    const dae = join(folder, file, 'models', 'untitled.dae');
    sources.push({ file: `${file}.kmz`, dae_sha256: createHash('sha256').update(readFileSync(dae)).digest('hex'),
      latitude: kml.latitude, longitude: kml.longitude, heading: kml.heading });
    const model = readCollada(dae);
    // KML heading turns the model clockwise seen from above.
    const angle = -kml.heading * Math.PI / 180, cos = Math.cos(angle), sin = Math.sin(angle);
    const [east, north] = offset(origin, kml);
    const drop = new Set(recipe.dropMaterials?.[file] ?? []);
    for (const t of model.triangles) {
      if (drop.has(t.material.name)) continue;
      const rgba = triangleColour(t);
      // Cut-out trees, shrubs and lattices: mostly clear in their texture.
      if (rgba[3] < 0.5) continue;
      const points = t.points.map(([x, y, z]) => [x * cos - y * sin + east, x * sin + y * cos + north, z]);
      if (areaOf(points) < 1e-6) continue;
      const mid = centre(points);
      if (recipe.keep && !recipe.keep.some(([x0, y0, x1, y1]) => mid[0] >= x0 && mid[0] <= x1 && mid[1] >= y0 && mid[1] <= y1)) continue;
      if (recipe.dropBelow !== undefined && Math.max(...points.map(p => p[2])) < recipe.dropBelow) continue;
      triangles.push({ points, rgb: rgba.slice(0, 3), file });
    }
  }
  return { origin, triangles, sources };
}

// A grid of points over the source faces, for the face under a point.
function nearestFace(triangles, step) {
  const cells = new Map(), key = (x, y, z) => `${x},${y},${z}`, samples = [];
  triangles.forEach((t, i) => {
    const rows = Math.min(40, Math.max(1, Math.ceil(Math.sqrt(areaOf(t.points) * 8) / step)));
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
      if (best >= 0 && Math.sqrt(distance) <= r * step) return best;
    }
    throw new Error('no face near');
  };
}

async function simplify(triangles, recipe) {
  await MeshoptSimplifier.ready;
  const index = new Map(), positions = [], corners = new Uint32Array(triangles.length * 3);
  triangles.forEach((t, i) => t.points.forEach((p, k) => {
    // Corners within a centimetre are one.
    const key = p.map(v => Math.round(v * 100)).join(',');
    let at = index.get(key);
    if (at === undefined) { at = positions.length / 3; index.set(key, at); positions.push(...p); }
    corners[i * 3 + k] = at;
  }));
  const points = new Float32Array(positions);
  const order = Object.keys(colours);
  const [kept, error] = MeshoptSimplifier.simplify(corners, points, 3, Math.min(recipe.triangles * 3, corners.length), recipe.maxError, ['ErrorAbsolute']);
  const nearest = nearestFace(triangles, 0.5), out = [];
  for (let i = 0; i < kept.length; i += 3) {
    const p = [0, 1, 2].map(k => [0, 1, 2].map(a => points[kept[i + k] * 3 + a]));
    if (areaOf(p) < 1e-6) continue;
    const votes = new Map(), facing = normalOf(p);
    let along = 0;
    for (let a = 0; a < 6; a++) for (let b = 0; b < 6 - a; b++) {
      const w = [(a + 1) / 9, (b + 1) / 9, (7 - a - b) / 9];
      const at = [0, 1, 2].map(k => w[0] * p[0][k] + w[1] * p[1][k] + w[2] * p[2][k]);
      const under = triangles[nearest(at)], n = normalOf(under.points);
      votes.set(under.cls, (votes.get(under.cls) ?? 0) + 1);
      along += Math.sign(n[0] * facing[0] + n[1] * facing[1] + n[2] * facing[2]);
    }
    const cls = [...votes].sort((x, y) => y[1] - x[1] || order.indexOf(x[0]) - order.indexOf(y[0]))[0][0];
    // Wound as the source faces under it face (orientOutward).
    if (along < 0) [p[1], p[2]] = [p[2], p[1]];
    out.push({ points: p, cls });
  }
  return { triangles: out, error };
}

async function build(folder, output, recipe) {
  const { origin, triangles: read_, sources } = read(folder, recipe);
  const triangles = dedupe(read_);
  const turned = orientOutward(triangles);
  for (const t of triangles) t.cls = classify(t, recipe);
  const classed = triangles.filter(t => t.cls !== null);
  // The ground the temple stands on (its lowest kept face) at z 0.
  const ground = recipe.groundZ ?? Math.min(...classed.flatMap(t => t.points.map(p => p[2])));
  for (const t of classed) t.points = t.points.map(([x, y, z]) => [x, y, z - ground]);
  const { triangles: made, error } = await simplify(classed, recipe);
  const tint = c => colours[c][recipe.tint?.[c] ?? 'default'] ?? colours[c].default;
  for (const t of made) t.rgb = tint(t.cls);
  const xs = made.flatMap(t => t.points.map(p => p[0])), ys = made.flatMap(t => t.points.map(p => p[1])), zs = made.flatMap(t => t.points.map(p => p[2]));
  const bounds = { west: Math.min(...xs), east: Math.max(...xs), south: Math.min(...ys), north: Math.max(...ys), top: Math.max(...zs) };
  const record = {
    source: {
      dataset: '臺北市宗教建築 3D 模型庫 (Taipei City Government, Department of Civil Affairs)',
      url: 'https://data.gov.tw/dataset/121136',
      license: 'Open Government Data License, version 1.0 (政府資料開放授權條款－第 1 版)',
      files: sources,
    },
    recipe: { id: recipe.id, triangles: recipe.triangles, max_error_m: recipe.maxError, simplifier: 'meshoptimizer 1.3.0 simplify',
      kept: 'shape only; recoloured in the game palette, no texture' },
  };
  writeFileSync(join(output, `${recipe.id}.m3dmodel`), writeM3dmodel(made, record));
  const counts = {};
  for (const t of made) counts[t.cls] = (counts[t.cls] ?? 0) + 1;
  process.stdout.write(`${recipe.id}: ${triangles.length} -> ${made.length} triangles, error ${error.toFixed(3)} m, ${turned} turned, `
    + `${(bounds.east - bounds.west).toFixed(1)} x ${(bounds.north - bounds.south).toFixed(1)} x ${bounds.top.toFixed(1)} m, ${JSON.stringify(counts)}\n`);
  return { id: recipe.id, latitude: origin.latitude, longitude: origin.longitude, triangles: made.length, error_m: Number(error.toFixed(3)),
    bounds: Object.fromEntries(Object.entries(bounds).map(([k, v]) => [k, Number(v.toFixed(2))])) };
}

const [folder, output, ...only] = process.argv.slice(2);
if (!folder || !output) throw new Error('usage: node tools/tpe-temples/build.mjs <unzipped KMZ folder> <output folder> [id...]');
mkdirSync(output, { recursive: true });
const placed = [];
for (const recipe of recipes) if (!only.length || only.includes(recipe.id)) placed.push(await build(folder, output, recipe));
writeFileSync(join(output, 'placements.json'), JSON.stringify(placed, null, 1) + '\n');
