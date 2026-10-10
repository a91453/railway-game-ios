// Runs jeantimex/tokyo's building mesher and tile format (MIT, Copyright (c) 2026 Yong Su) over the
// footprints extract_patch.py wrote, to size an iOS sample (docs/research/PROCEDURAL_CITY_STUDY.md).
// Nothing of Tokyo is copied here: it is imported from a checkout.
//
//   git clone https://github.com/jeantimex/tokyo /tmp/tokyo && git -C /tmp/tokyo checkout 17c8bbe5a6c57c75fe504a58ac3fb16004a27573
//   npm install --prefix /tmp --no-save --ignore-scripts earcut@3.2.4
//   node tools/procedural-city/measure_patch.mjs /tmp/tokyo patches.json
import fs from 'node:fs';
import zlib from 'node:zlib';
import { pathToFileURL } from 'node:url';

const [tokyo, patches] = process.argv.slice(2);
if (!tokyo || !patches) { console.error('usage: measure_patch.mjs <tokyo checkout> <patches.json>'); process.exit(1); }
const { buildingMesh } = await import(pathToFileURL(`${tokyo}/src/world/meshing.js`).href);
const { encodeTile, decodeTile } = await import(pathToFileURL(`${tokyo}/src/shared/tileformat.js`).href);

const TILE = 256; // Tokyo's streaming tile (src/shared/geo.js)
const LEVEL = 3.2; // metres a storey, as the OSM and Overture surveys
// The mesher's vertex: position, normal, colour, aFacade, aBldg, aPhoto, aMark (float32, not indexed).
const VERTEX_BYTES = (3 + 3 + 3 + 4 + 4 + 2 + 1) * 4;
// PLATEAU usage codes: 461 unknown (a house under 9 m, else an apartment or office block: apartments
// carry balconies on every floor); 401 commercial (no balconies; a glass tower over 45 m).
const USAGE = { 'unknown (461)': 461, 'commercial (401)': 401 };
// Storeys for the buildings with neither floors nor height.
const UNKNOWN = { 'Tokyo fallback, 1': 1, 'D2, 6': 6, 'D3, 18': 18 };

const signedArea = (r) => r.reduce((s, [x0, z0], i) => { const [x1, z1] = r[(i + 1) % r.length]; return s + x1 * z0 - x0 * z1; }, 0) / 2;
// tileformat.js: an outline counter-clockwise seen from above (x east, z south), holes clockwise.
const orient = (ring, outline) => ((signedArea(ring) > 0) === outline ? ring : [...ring].reverse());
const tileOf = (ring) => {
  const x = ring.reduce((s, p) => s + p[0], 0) / ring.length, z = ring.reduce((s, p) => s + p[1], 0) / ring.length;
  return [Math.floor(x / TILE), Math.floor(z / TILE)];
};

for (const [spot, { buildings }] of Object.entries(JSON.parse(fs.readFileSync(patches, 'utf8')))) {
  const tiles = new Map();
  for (const b of buildings) {
    const [tx, tz] = tileOf(b.polygons[0][0]), key = `${tx}_${tz}`;
    if (!tiles.has(key)) tiles.set(key, { tx, tz, list: [] });
    tiles.get(key).list.push(b);
  }
  const known = buildings.filter((b) => b.floors > 0 || b.height > 0).length;
  // the tile files, as Tokyo's compiler would write them (footprints and heights only)
  let raw = 0, gzip = 0;
  for (const { tx, tz, list } of tiles.values()) {
    const bytes = encodeTile({ tx, tz, buildings: list.map((b) => ({ usage: 461, storeys: b.floors || 0, base: 0, height: b.height || 0, polygons: b.polygons })), areas: [] });
    if (decodeTile(bytes.slice().buffer).buildings.length !== list.length) throw new Error('tile round trip');
    raw += bytes.length; gzip += zlib.gzipSync(bytes, { level: 9 }).length;
  }
  console.log(JSON.stringify({ spot, buildings: buildings.length, withFloorsOrHeight: known, tiles: tiles.size, tileKiB: +(raw / 1024).toFixed(1), tileGzipKiB: +(gzip / 1024).toFixed(1) }));
  for (const [usageName, usage] of Object.entries(USAGE))
    for (const [unknownName, unknown] of Object.entries(UNKNOWN)) {
      let triangles = 0, vertices = 0, worst = 0, ms = 0;
      for (const { tx, tz, list } of tiles.values()) {
        const input = list.map((b) => {
          const storeys = b.floors > 0 ? b.floors : b.height > 0 ? Math.max(1, Math.round(b.height / LEVEL)) : unknown;
          return { usage, storeys, flags: 0, base: 0, height: b.height > 0 ? b.height : storeys * LEVEL, hint: 0, surfaces: [],
            polygons: b.polygons.map((p) => p.map((ring, i) => Float32Array.from(orient(ring, i === 0).flat()))) };
        });
        const start = performance.now();
        const mesh = buildingMesh(input, tx, tz);
        ms += performance.now() - start;
        triangles += mesh.triangles; vertices += mesh.position.length / 3; worst = Math.max(worst, mesh.triangles);
      }
      console.log(JSON.stringify({ spot, usage: usageName, unknownStoreys: unknownName, triangles, perBuilding: +(triangles / buildings.length).toFixed(1),
        worstTile: worst, vertexMiB: +((vertices * VERTEX_BYTES) / 1048576).toFixed(1), meshMs: +ms.toFixed(0) }));
    }
}
