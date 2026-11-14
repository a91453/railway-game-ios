#!/usr/bin/env node
// Decision 725: Taipei's temples on the 3D map, their shape from the
// Department of Civil Affairs' "臺北市宗教建築 3D 模型庫" (data.gov.tw 121136,
// Open Government Data License v1.0). Reads each temple's KMZ (unzipped:
// `doc.kml` and the SketchUp COLLADA), drops the ground, the terrain and the
// nearly clear cut-outs, sorts every face into a part of the building (roof tile,
// ridge, wall, column, opening, paving) from its slope and height (and,
// for columns and openings, the colour of the photo under it), simplifies with meshoptimizer (pinned in
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
import { pathToFileURL } from 'node:url';
import { readCollada, readKml } from './collada.mjs';
import { triangleColour } from './textures.mjs';
import { writeM3dmodel } from './m3dmodel.mjs';
import { recipes, colours, soften } from './recipes.mjs';
import { dedupe, orientConsistent } from './orient.mjs';
import { windConsistently } from './wind.mjs';
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

// The part of the building a source face is, before simplification, from
// its shape first: an upward face above the eaves is roof, and the narrow
// band along the top of each roof (within 0.4 m of the highest roof within
// 2 m) is its ridge, with the cut-out ornaments that stand on it; a downward
// face is the eaves' underside; an upward face below the eaves is paving.
// Of the rest (walls), a strongly red one is a column and one much darker
// than this temple's own walls is an opening (a door, a window).
export function classifier(triangles, recipe, rgbOf = i => triangles[i].rgb) {
  const cell = 1, top = new Map(), key = (x, y) => `${x},${y}`;
  const facts = triangles.map((t, i) => {
    const n = normalOf(t.points), length = Math.hypot(...n);
    if (length === 0) return null;
    const z = centre(t.points)[2];
    return { nz: n[2] / length, z, low: Math.min(...t.points.map(p => p[2])), hsl: hsl(rgbOf(i)) };
  });
  // The highest roof over each metre of ground.
  triangles.forEach((t, i) => {
    const f = facts[i];
    if (!f || f.nz <= 0.3 || f.z <= recipe.eave) return;
    const xs = t.points.map(p => Math.floor(p[0] / cell)), ys = t.points.map(p => Math.floor(p[1] / cell));
    const high = Math.max(...t.points.map(p => p[2]));
    for (let x = Math.min(...xs); x <= Math.max(...xs); x++) for (let y = Math.min(...ys); y <= Math.max(...ys); y++) {
      top.set(key(x, y), Math.max(top.get(key(x, y)) ?? -Infinity, high));
    }
  });
  const roofTop = point => {
    const x0 = Math.floor(point[0] / cell), y0 = Math.floor(point[1] / cell);
    let best = -Infinity;
    for (let dx = -2; dx <= 2; dx++) for (let dy = -2; dy <= 2; dy++) best = Math.max(best, top.get(key(x0 + dx, y0 + dy)) ?? -Infinity);
    return best;
  };
  const isRed = ([h, s, l]) => (h < 22 || h > 340) && s > 0.32 && l > 0.18 && l < 0.7;
  // This temple's wall lightness: the area-weighted median of its upright faces.
  const walls = triangles.map((t, i) => [facts[i], areaOf(t.points)])
    .filter(([f]) => f && Math.abs(f.nz) <= 0.3 && !isRed(f.hsl)).map(([f, a]) => [f.hsl[2], a]).sort((a, b) => a[0] - b[0]);
  const total = walls.reduce((s, [, a]) => s + a, 0);
  let median = 0.5;
  for (let sum = 0, i = 0; i < walls.length; i++) { sum += walls[i][1]; if (sum >= total / 2) { median = walls[i][0]; break; } }
  const dark = Math.min(recipe.dark ?? 0.3, median * 0.45);
  return (t, i) => {
    const f = facts[i];
    if (!f) return null;
    const mid = centre(t.points), above = roofTop(mid);
    // A ridge is narrow: a face more than 2.5 m across is a roof's slope
    // or a flat roof, however near the top it lies.
    const across = Math.max(...[0, 1, 2].map(k => Math.hypot(t.points[k][0] - t.points[(k + 1) % 3][0], t.points[k][1] - t.points[(k + 1) % 3][1])));
    const onRidge = above > recipe.eave && across <= 2.5 && f.low >= above - 1.2 && f.z >= above - 0.4 - (f.nz > 0.3 ? 0 : 0.6);
    if (t.cutout) return f.z > recipe.eave && onRidge ? 'ridge' : null;
    if (f.nz > 0.3 && f.z > recipe.eave) return onRidge ? 'ridge' : 'roof';
    if (f.nz > 0.7) return 'paving';
    if (f.nz < -0.3) return 'soffit';
    if (f.z > recipe.eave && onRidge) return 'ridge';
    if (isRed(f.hsl)) return 'column';
    if (f.hsl[2] < dark) return 'opening';
    return 'wall';
  };
}

// The game colour of a part nearest a photo's colour (CIE L*a*b*), or the
// recipe's tint for that part.
const lab = rgb => {
  const lin = v => (v /= 255) <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  const [r, g, b] = rgb.map(lin);
  const f = t => t > 216 / 24389 ? Math.cbrt(t) : (24389 / 27 * t + 16) / 116;
  const x = f((0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047), y = f(0.2126 * r + 0.7152 * g + 0.0722 * b), z = f((0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883);
  return [116 * y - 16, 500 * (x - y), 200 * (y - z)];
};
const hex = v => [v >> 16 & 255, v >> 8 & 255, v & 255];
const fromLab = ([L, a, b]) => {
  const fy = (L + 16) / 116, fx = fy + a / 500, fz = fy - b / 200;
  const g = t => t ** 3 > 216 / 24389 ? t ** 3 : (116 * t - 16) / (24389 / 27);
  const x = g(fx) * 0.95047, y = g(fy), z = g(fz) * 1.08883;
  const lin = [3.2406 * x - 1.5372 * y - 0.4986 * z, -0.9689 * x + 1.8758 * y + 0.0415 * z, 0.0557 * x - 0.2040 * y + 1.0570 * z];
  const [r, gr, bl] = lin.map(v => Math.round(255 * Math.min(1, Math.max(0, v <= 0.0031308 ? 12.92 * v : 1.055 * v ** (1 / 2.4) - 0.055))));
  return r << 16 | gr << 8 | bl;
};
export function paint(cls, target, recipe) {
  if (recipe.tint?.[cls]) return colours[cls][recipe.tint[cls]];
  let best, distance = Infinity;
  for (const value of Object.values(colours[cls])) {
    const d = lab(hex(value)).reduce((s, v, k) => s + (v - target[k]) ** 2, 0);
    if (d < distance) { distance = d; best = value; }
  }
  return best;
}

// Decision 720's pale map (方案 C), lightened but not greyed: the colour's
// lightness (L*) taken `share` of the way toward the paving's, its colour
// (a*, b*) kept at 90%.
export function pale(value, share) {
  const [L, a, b] = lab(hex(value)), [G] = lab(hex(soften.toward));
  return fromLab([L + (G - L) * share, a * soften.chroma, b * soften.chroma]);
}
export const shareOf = cls => (cls === 'opening' ? soften.share / 2 : soften.share);

// Every colour a temple can be drawn in (Map3DTaipeiTemplesTests.palette).
export const palette = () => [...new Set(Object.entries(colours).flatMap(([cls, shades]) => Object.values(shades).map(v => pale(v, shareOf(cls)))))].sort((x, y) => x - y);

// Whether any of `triangles` lies above (or, `down`, below) a point (a
// vertical ray), through a grid of their footprints, 2 m.
function coverTest(triangles, cell = 2) {
  const cells = new Map(), key = (x, y) => `${x},${y}`;
  triangles.forEach((t, i) => {
    const xs = t.points.map(p => p[0]), ys = t.points.map(p => p[1]);
    for (let x = Math.floor(Math.min(...xs) / cell); x <= Math.floor(Math.max(...xs) / cell); x++)
      for (let y = Math.floor(Math.min(...ys) / cell); y <= Math.floor(Math.max(...ys) / cell); y++) {
        if (!cells.has(key(x, y))) cells.set(key(x, y), []);
        cells.get(key(x, y)).push(i);
      }
  });
  const side = (p, q, r) => (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0]);
  return (o, down = false) => (cells.get(key(Math.floor(o[0] / cell), Math.floor(o[1] / cell))) ?? []).some(i => {
    const [a, b, c] = triangles[i].points, whole = side(a, b, c);
    if (Math.abs(whole) < 1e-9) return false;
    const u = side(b, c, o) / whole, v = side(c, a, o) / whole, w = 1 - u - v;
    const z = u * a[2] + v * b[2] + w * c[2];
    return u >= 0 && v >= 0 && w >= 0 && (down ? z < o[2] - 0.05 : z > o[2] + 0.05);
  });
}

// Groups of faces (union–find).
function groups(count) {
  const up = Int32Array.from({ length: count }, (_, i) => i);
  const find = i => { while (up[i] !== i) { up[i] = up[up[i]]; i = up[i]; } return i; };
  return { find, join: (i, j) => { i = find(i); j = find(j); if (i !== j) up[Math.max(i, j)] = Math.min(i, j); } };
}

// The faces that share each edge, corners within a centimetre one.
const cornerKey = p => p.map(v => Math.round(v * 100)).join(',');
function sharedEdges(triangles) {
  const edges = new Map();
  triangles.forEach((t, f) => {
    const c = t.points.map(cornerKey);
    for (let k = 0; k < 3; k++) {
      const x = c[k], y = c[(k + 1) % 3];
      if (x === y) continue;
      const key = x < y ? `${x}|${y}` : `${y}|${x}`;
      if (!edges.has(key)) edges.set(key, { faces: [], length: Math.hypot(...sub(t.points[k], t.points[(k + 1) % 3])) });
      edges.get(key).faces.push(f);
    }
  });
  return [...edges.values()].filter(e => e.faces.length > 1);
}

// A face's flat piece: the faces it shares edges with in the same material
// and the same plane (normals within about 8°), as SketchUp drew it before
// the export cut it into triangles. Its colour is the piece's mean (by
// area), so one face of a wall is never a column and the next a wall.
function flatPieceColours(triangles, edges) {
  const unit = triangles.map(t => { const n = normalOf(t.points), l = Math.hypot(...n) || 1; return n.map(v => v / l); });
  const g = groups(triangles.length);
  for (const { faces } of edges) for (const f of faces) for (const h of faces) {
    if (f < h && triangles[f].material === triangles[h].material && Math.abs(unit[f].reduce((s, v, k) => s + v * unit[h][k], 0)) > 0.99) g.join(f, h);
  }
  const sums = new Map();
  triangles.forEach((t, f) => {
    const a = areaOf(t.points), s = sums.get(g.find(f)) ?? [0, 0, 0, 0];
    sums.set(g.find(f), [s[0] + t.rgb[0] * a, s[1] + t.rgb[1] * a, s[2] + t.rgb[2] * a, s[3] + a]);
  });
  return f => { const s = sums.get(g.find(f)); return s[3] > 0 ? s.slice(0, 3).map(v => v / s[3]) : triangles[f].rgb; };
}

// One colour a block: the faces of one part that share edges (for walls,
// columns and openings also one material, the modeller's own division of
// a front) take the game colour nearest the mean of the photo under the
// whole block (L*a*b*, by area), lightened for decision 720's map (pale).
// A block under `small` m² other than a door or window takes the colour of
// the bigger block it shares the most edge with, whatever its part, so a
// stray sliver never stands out of its roof or wall.
const upright = new Set(['wall', 'column', 'opening']);
function blockColours(triangles, edges, recipe, small = 2) {
  const g = groups(triangles.length);
  for (const { faces } of edges) for (const f of faces) for (const h of faces) {
    const a = triangles[f], b = triangles[h];
    if (f < h && a.cls === b.cls && (!upright.has(a.cls) || a.material === b.material)) g.join(f, h);
  }
  const blocks = new Map();
  triangles.forEach((t, f) => {
    const a = areaOf(t.points), key = g.find(f), b = blocks.get(key) ?? { cls: t.cls, area: 0, lab: [0, 0, 0], borders: new Map() };
    b.area += a; lab(t.rgb).forEach((v, k) => { b.lab[k] += v * a; });
    blocks.set(key, b);
  });
  for (const b of blocks.values()) b.rgb = pale(paint(b.cls, b.lab.map(v => v / (b.area || 1)), recipe), shareOf(b.cls));
  for (const { faces, length } of edges) for (const f of faces) for (const h of faces) {
    const x = g.find(f), y = g.find(h);
    if (x !== y) blocks.get(x).borders.set(y, (blocks.get(x).borders.get(y) ?? 0) + length);
  }
  for (const b of blocks.values()) {
    if (b.area >= small || b.cls === 'opening') continue;
    const bigger = [...b.borders].filter(([y]) => blocks.get(y).area >= small).sort((x, y) => y[1] - x[1] || x[0] - y[0]);
    if (bigger.length) b.rgb = blocks.get(bigger[0][0]).rgb;
  }
  return f => blocks.get(g.find(f)).rgb;
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
      // A face mostly clear in its texture is a cut-out: a ridge's dragons
      // and flowers, a lattice, a tree. Nearly clear ones go; the others are
      // kept only on a ridge (classifier).
      if (rgba[3] < 0.25) continue;
      const points = t.points.map(([x, y, z]) => [x * cos - y * sin + east, x * sin + y * cos + north, z]);
      if (areaOf(points) < 1e-6) continue;
      const mid = centre(points);
      if (recipe.keep && !recipe.keep.some(([x0, y0, x1, y1]) => mid[0] >= x0 && mid[0] <= x1 && mid[1] >= y0 && mid[1] <= y1)) continue;
      if (recipe.dropBelow !== undefined && Math.max(...points.map(p => p[2])) < recipe.dropBelow) continue;
      triangles.push({ points, rgb: rgba.slice(0, 3), cutout: rgba[3] < 0.5, file, material: `${file}/${t.material.name}` });
    }
  }
  return { origin, triangles, sources };
}

// Simplifies with meshoptimizer. A corner on the border of two colours is
// written once for each, at the same place, so the simplifier keeps the
// border as a seam (it moves along it, never across), and every new face
// is still one block's colour.
async function simplify(triangles, recipe) {
  await MeshoptSimplifier.ready;
  const place = new Map(), index = new Map(), positions = [], kinds = [], corners = new Uint32Array(triangles.length * 3);
  triangles.forEach((t, i) => t.points.forEach((p, k) => {
    const where = cornerKey(p);
    if (!place.has(where)) place.set(where, p);
    const key = `${where}/${t.rgb}`;
    let at = index.get(key);
    if (at === undefined) { at = positions.length / 3; index.set(key, at); positions.push(...place.get(where)); kinds.push(t); }
    corners[i * 3 + k] = at;
  }));
  const points = new Float32Array(positions);
  const [kept, error] = MeshoptSimplifier.simplify(corners, points, 3, Math.min(recipe.triangles * 3, corners.length), recipe.maxError, ['ErrorAbsolute']);
  const out = [];
  for (let i = 0; i < kept.length; i += 3) {
    const p = [0, 1, 2].map(k => [0, 1, 2].map(a => points[kept[i + k] * 3 + a]));
    if (areaOf(p) < 1e-6) continue;
    const kind = kinds[kept[i]];
    out.push({ points: p, cls: kind.cls, rgb: kind.rgb });
  }
  return { triangles: out, error };
}

async function build(folder, output, recipe) {
  const { origin, triangles: read_, sources } = read(folder, recipe);
  const triangles = dedupe(read_);
  const source = orientConsistent(triangles, cornerKey);
  // The ground the temple stands on (its lowest solid face) at z 0.
  const ground = recipe.groundZ ?? Math.min(...triangles.filter(t => !t.cutout).flatMap(t => t.points.map(p => p[2])));
  for (const t of triangles) t.points = t.points.map(([x, y, z]) => [x, y, z - ground]);
  const edges = sharedEdges(triangles);
  const classify = classifier(triangles, recipe, flatPieceColours(triangles, edges));
  triangles.forEach((t, i) => { t.cls = classify(t, i); });
  // Upright faces above the eaves with nothing over them are part of the
  // roof, not wall (a wall always stands under its roof): in a material
  // most of whose area facing up or sideways is roof, the upturned tips of
  // the eaves; in a small material (under 40 m², a cut-out's), or no more
  // than 2.5 m tall and standing on a roof, its ornaments (the
  // swallow-tail ends, a dragon's silhouette, a name board).
  const roofShare = new Map();
  for (const t of triangles) {
    if (t.cls === null) continue;
    const [roof, all, every] = roofShare.get(t.material) ?? [0, 0, 0], a = areaOf(t.points), facing = t.cls !== 'soffit';
    roofShare.set(t.material, [roof + (t.cls === 'roof' ? a : 0), all + (facing ? a : 0), every + a]);
  }
  const roofs = coverTest(triangles.filter(t => t.cls === 'roof' || t.cls === 'ridge'));
  for (const t of triangles) {
    const zs = t.points.map(p => p[2]), mid = centre(t.points), tall = Math.max(...zs) - Math.min(...zs);
    if (!upright.has(t.cls) || Math.min(...zs) < recipe.eave || roofs(mid)) continue;
    const [roof, all, every] = roofShare.get(t.material);
    if (roof > all / 2) { if (tall <= 2.5) t.cls = 'roof'; }
    else if (every < 40 || (tall <= 2.5 && roofs([mid[0], mid[1], Math.min(...zs) + 0.1], true))) t.cls = 'ridge';
  }
  const classed = triangles.filter(t => t.cls !== null);
  const colourOf = blockColours(classed, sharedEdges(classed), recipe);
  classed.forEach((t, i) => { t.rgb = colourOf(i); });
  const { triangles: made, error } = await simplify(classed, recipe);
  // The simplifier keeps each face's winding, but can still fold a
  // piece over itself: wound alike again on its output, corner by exact
  // corner as the game reads them (wind.mjs).
  const after = windConsistently(made);
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
  process.stdout.write(`${recipe.id}: ${triangles.length} -> ${made.length} triangles, error ${error.toFixed(3)} m, `
    + `source ${source.pieces} pieces ${source.turned} turned ${source.alike} alike, output ${after.pieces} pieces ${after.flipped} turned ${after.twins} twins, `
    + `${(bounds.east - bounds.west).toFixed(1)} x ${(bounds.north - bounds.south).toFixed(1)} x ${bounds.top.toFixed(1)} m, ${JSON.stringify(counts)}\n`);
  return { id: recipe.id, latitude: origin.latitude, longitude: origin.longitude, triangles: made.length, error_m: Number(error.toFixed(3)),
    bounds: Object.fromEntries(Object.entries(bounds).map(([k, v]) => [k, Number(v.toFixed(2))])) };
}

// Run as a script (the functions above can also be imported).
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [folder, output, ...only] = process.argv.slice(2);
  if (!folder || !output) throw new Error('usage: node tools/tpe-temples/build.mjs <unzipped KMZ folder> <output folder> [id...]');
  mkdirSync(output, { recursive: true });
  const placed = [];
  for (const recipe of recipes) if (!only.length || only.includes(recipe.id)) placed.push(await build(folder, output, recipe));
  writeFileSync(join(output, 'placements.json'), JSON.stringify(placed, null, 1) + '\n');
  process.stdout.write(`palette: ${palette().map(v => '0x' + v.toString(16).toUpperCase().padStart(6, '0')).join(', ')}\n`);
}
