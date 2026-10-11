// Areas the pipeline can build. An area is a block of PLATEAU 3rd-level meshes (~1.1 x 0.9 km each)
// around a centre; the world origin (0, 0, 0) sits on `origin`. `backdrop` (kilometres) adds the land that far
// around the area as coarse terrain under an aerial photo: the mountains on the horizon.
import path from 'node:path';
import { meshBlock, meshBounds3 } from '../../src/shared/geo.js';

export const AREAS = {
  // (in the order of the city switch; the first is the one the site opens with)
  tokyo: {
    name: 'Tokyo',
    origin: [139.76712, 35.68124], // Tokyo Station, between Marunouchi and Yaesu
    radius: 1,
  },
  shiba: {
    name: 'Shiba (Tokyo Tower)',
    origin: [139.74543, 35.65858], // Tokyo Tower
    radius: 1,
  },
  shibuya: {
    name: 'Shibuya',
    origin: [139.70045, 35.65948], // Shibuya Scramble Crossing [lon, lat]
    radius: 1,                     // 3 x 3 meshes, about 3.4 x 2.8 km
  },
  shinjuku: {
    name: 'Shinjuku',
    origin: [139.7005, 35.6896],   // Shinjuku Station: the skyscraper district to the west, Kabukicho to the north
    radius: 1,
  },
  chiyoda: {
    name: 'Chiyoda (Akihabara)',
    origin: [139.7679, 35.7020],   // Kanda Myojin: north of the Tokyo area, without overlapping it
    radius: 1,
    view: '460,400,420,215,32',    // opens over Akihabara Station
  },
  chuo: {
    name: 'Chuo (Tsukiji, Tsukishima)',
    origin: [139.7800, 35.6560],   // Kachidoki: the waterfront south of the Tokyo area (which has Ginza and Nihonbashi)
    radius: 1,
  },
  fujinomiya: {
    name: 'Fujinomiya (Mt Fuji)',
    origin: [138.6100, 35.2275], // Fujisan Hongu Sengen Taisha, the head shrine of Mt Fuji
    radius: 1,
    backdrop: 30,                  // the summit stands 18 km to the north-east
    view: '0,0,700,305,10',        // the opening view (as ?cam=): over the town towards the mountain
  },
  // Along the Line (ARCHITECTURE decision 152): a Taiwanese area. No PLATEAU, no GSI: `source: 'taiwan'` reads
  // Overture's buildings and the OpenStreetMap extract of Taiwan (tools/procedural-city/taiwan_area.py) and
  // lays the ground flat; `half` (metres) sets a square around the origin instead of a block of JIS meshes.
  kaohsiung: {
    name: '高雄車站',
    origin: [120.3024, 22.6394],   // Kaohsiung Station (tools/procedural-city/taiwan_area.py has the same square)
    half: 750,
    source: 'taiwan',
    view: '0,0,420,200,32',
    attribution: [
      'Buildings: Overture Maps Foundation (ODbL 1.0; OpenStreetMap contributors, Shi et al. CC BY 4.0)',
      'Roads, railways, parks and places: © OpenStreetMap contributors (ODbL 1.0)',
    ],
  },
};

export const ROOT = path.resolve(import.meta.dirname, '../..');
export const RAW = path.join(ROOT, 'data/raw');

// DEM tiles (about 125 m a pixel) and the grid made of them (metres); the photo of all of it (15 m a pixel), and a
// sharper one (4 m) of the land within `near` kilometres: what lies just beyond the last houses
export const BACKDROP = { zoom: 10, step: 120, photoZoom: 13, nearZoom: 15, near: 7 };

// The rectangle `backdrop` kilometres around the origin, in degrees.
export function backdropBox({ origin: [lon, lat] }, backdrop) {
  const dLat = backdrop / 110.95, dLon = backdrop / (111.32 * Math.cos((lat * Math.PI) / 180));
  return { south: lat - dLat, north: lat + dLat, west: lon - dLon, east: lon + dLon };
}

// The square `half` metres round an area's origin, in degrees (the metres a degree as makeProjection).
function squareBox({ origin: [lon, lat], half }) {
  const phi = (lat * Math.PI) / 180;
  const mLat = 111132.954 - 559.822 * Math.cos(2 * phi) + 1.175 * Math.cos(4 * phi);
  const mLon = 111412.84 * Math.cos(phi) - 93.5 * Math.cos(3 * phi);
  return { south: lat - half / mLat, north: lat + half / mLat, west: lon - half / mLon, east: lon + half / mLon };
}

export function resolveArea(argv = process.argv) {
  const arg = argv.find((a) => a.startsWith('--area='));
  const id = arg ? arg.split('=')[1] : 'shibuya';
  const area = AREAS[id];
  if (!area) throw new Error(`unknown area "${id}" (known: ${Object.keys(AREAS).join(', ')})`);
  const meshes = area.half ? [] : meshBlock(area.origin[0], area.origin[1], area.radius);
  const b = meshes.map(meshBounds3);
  const bbox = area.half ? squareBox(area) : {
    south: Math.min(...b.map((m) => m.south)), west: Math.min(...b.map((m) => m.west)),
    north: Math.max(...b.map((m) => m.north)), east: Math.max(...b.map((m) => m.east)),
  };
  return { id, ...area, meshes, bbox, backdropBbox: area.backdrop ? backdropBox(area, area.backdrop) : null, rawDir: path.join(RAW, id), outDir: path.join(ROOT, 'public/tiles', id) };
}
