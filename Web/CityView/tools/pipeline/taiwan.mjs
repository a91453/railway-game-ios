// Along the Line: what PLATEAU gives a Japanese area, made for a Taiwanese one (ARCHITECTURE decision 152).
// Buildings come from Overture Maps (tools/procedural-city/taiwan_area.py writes overture_buildings.json),
// road surfaces from the OpenStreetMap centrelines. Everything here is this project's, not Tokyo's.
import fs from 'node:fs';
import polygonClipping from 'polygon-clipping';
import { TILE } from '../../src/shared/geo.js';
import { hash } from './landscape.mjs';

export function readOverture(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8')).buildings;
}

// Overture's subtype and class -> the PLATEAU usage code meshing.js reads (its `category`). A Taiwanese
// street is mostly shophouses (透天厝): a shop on the ground floor, homes above, a flat roof — PLATEAU's
// 413 (店舗等併用住宅), which meshing.js draws with a shopfront and balconies.
export function usageOf(b, area) {
  const k = b.class ?? '', s = b.subtype ?? '';
  if (/^(train_station|transportation|parking|garage|warehouse)$/.test(k) || s === 'transportation') return 431;
  if (/^(school|university|college|kindergarten|hospital|clinic|library|museum)$/.test(k) || s === 'education' || s === 'medical') return 422;
  if (/^(government|civic|public|police|fire_station|post_office)$/.test(k) || s === 'civic') return 421;
  if (/^(temple|church|mosque|shrine|religious)$/.test(k) || s === 'religious') return 454;
  if (/^(industrial|factory|manufacture)$/.test(k) || s === 'industrial') return 441;
  if (/^(office|commercial|retail|supermarket|hotel)$/.test(k) || s === 'commercial') return area > 400 ? 401 : 404;
  if (/^(apartments|residential|dormitory)$/.test(k) || s === 'residential') return area > 300 ? 414 : 413;
  return area > 300 ? 414 : 413;
}

// Storeys of a building Overture knows no height for (about 96% of them round Kaohsiung Station; see
// docs/research/OSM_BUILDING_SURVEY.md). Provisional, by footprint, until the view reads the city's density
// from GameCore: a narrow shophouse 3–5 floors, a block of flats 6–14, a large hall 2–5. A building's own
// hash spreads the floors so a street does not stand at one height.
export function storeysOf(b, area) {
  const r = hash(Math.round(area * 10), b.id.length * 131 + b.id.charCodeAt(b.id.length - 1), 17);
  if (area < 35) return 1 + Math.floor(r * 2);           // sheds, kiosks, rooftop huts mapped as buildings
  if (area < 180) return 3 + Math.floor(r * 3);          // shophouses
  if (area < 700) return 5 + Math.floor(r * 6);          // apartment blocks, small offices
  if (area < 3000) return 7 + Math.floor(r * 8);         // large blocks and towers
  return 2 + Math.floor(r * 4);                          // halls, markets, stations, malls
}
export const LEVEL = 3.2; // metres a storey, as the building surveys

// Road outlines: every surface road's centreline buffered to its carriageway and, on the larger roads, a
// sidewalk on each side, cut at the tile edges so each tile streams its own (Tokyo's road outlines come
// from PLATEAU, which maps the whole right-of-way). The compiler then splits them as it splits PLATEAU's
// outline-only roads (roadsplit.mjs): carriageway from the centrelines, the rest sidewalk.
const LANE = 3.0; // roadsplit.mjs
const SIDEWALK = { trunk: 3, primary: 3, secondary: 3, tertiary: 2 };
const close = (r) => [...r, r[0]];

// Union of many pieces, a few at a time; a piece polygon-clipping cannot merge (it throws on some
// near-degenerate input) is left out rather than losing the tile's roads. `skipped` counts them.
export const unionStats = { skipped: 0 };
function unionOf(pieces) {
  let acc = [];
  for (let i = 0; i < pieces.length; i += 32) {
    const batch = pieces.slice(i, i + 32);
    let part;
    try { part = polygonClipping.union(...batch); } catch {
      part = [];
      for (const p of batch) try { part = polygonClipping.union(part, p); } catch { unionStats.skipped++; }
    }
    try { acc = polygonClipping.union(acc, part); } catch { unionStats.skipped++; }
  }
  return acc;
}

export function roadOutlines(edges, pos, bounds) {
  const byTile = new Map();
  const add = (ring) => {
    let x0 = Infinity, x1 = -Infinity, z0 = Infinity, z1 = -Infinity;
    for (const [x, z] of ring) { x0 = Math.min(x0, x); x1 = Math.max(x1, x); z0 = Math.min(z0, z); z1 = Math.max(z1, z); }
    for (let tx = Math.floor(x0 / TILE); tx <= Math.floor(x1 / TILE); tx++)
      for (let tz = Math.floor(z0 / TILE); tz <= Math.floor(z1 / TILE); tz++) {
        const k = `${tx}_${tz}`;
        if (!byTile.has(k)) byTile.set(k, { tx, tz, pieces: [] });
        // (to the centimetre: polygon-clipping fails on near-coincident edges otherwise)
        byTile.get(k).pieces.push([close(ring.map(([x, z]) => [Math.round(x * 100) / 100, Math.round(z * 100) / 100]))]);
      }
  };
  for (const e of edges) {
    if (e.tunnel || e.flyover || (e.bridge && !e.span)) continue;
    const hw = e.highway.replace('_link', '');
    const carriage = e.lanes >= 2 ? e.lanes * LANE + 1 : e.oneway ? 4 : 4.5;
    const h = carriage / 2 + (SIDEWALK[hw] ?? 0);
    const pts = e.ids.map(pos);
    for (let i = 0; i < pts.length; i++) {
      const [x, z] = pts[i];
      add(Array.from({ length: 8 }, (_, k) => [x + Math.cos((k + 0.5) * Math.PI / 4) * h * 1.08, z + Math.sin((k + 0.5) * Math.PI / 4) * h * 1.08]));
      if (i === 0) continue;
      const [px, pz] = pts[i - 1], len = Math.hypot(x - px, z - pz);
      if (len < 0.01) continue;
      const nx = (-(z - pz) / len) * h, nz = ((x - px) / len) * h;
      add([[px - nx, pz - nz], [x - nx, z - nz], [x + nx, z + nz], [px + nx, pz + nz]]);
    }
  }
  const area = (r) => { let s = 0; for (let i = 0; i < r.length; i++) { const [x1, z1] = r[i], [x2, z2] = r[(i + 1) % r.length]; s += x2 * z1 - x1 * z2; } return s / 2; };
  const out = [];
  for (const { tx, tz, pieces } of byTile.values()) {
    const x0 = Math.max(tx * TILE, bounds.minX), x1 = Math.min((tx + 1) * TILE, bounds.maxX);
    const z0 = Math.max(tz * TILE, bounds.minZ), z1 = Math.min((tz + 1) * TILE, bounds.maxZ);
    if (x1 <= x0 || z1 <= z0) continue;
    const square = [[[x0, z0], [x1, z0], [x1, z1], [x0, z1], [x0, z0]]];
    const merged = polygonClipping.intersection(unionOf(pieces), square);
    for (const poly of merged) {
      const rings = poly.map((r) => r.slice(0, -1).map(([x, z]) => [Math.round(x * 100) / 100, Math.round(z * 100) / 100])).filter((r) => r.length >= 3);
      if (!rings.length || Math.abs(area(rings[0])) < 1) continue;
      out.push(rings.map((r, i) => ((area(r) > 0) === (i === 0) ? r : [...r].reverse())));
    }
  }
  return out;
}
