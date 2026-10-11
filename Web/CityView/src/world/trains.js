// Trains running on the railway lines. Each line's OSM ways are chained into paths (way direction =
// running direction); one train per path loops through the area, leaving at one edge and re-entering
// at the other.
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';
import { beamTexture } from './traffic.js';
import { LAMP_LAYER, lampMaterial, lampScene } from './lamplight.js';

// Line name (substring) -> rolling stock. Colours follow the real line colours.
const STOCK = [
  { match: '山手貨物線', stripe: '#00a08e', body: '#c9ccce', cars: 10, length: 20 },  // Saikyo / Shonan-Shinjuku trains use the freight tracks
  { match: '山手線', stripe: '#8fc31f', body: '#c9ccce', cars: 11, length: 20 },
  { match: '埼京', stripe: '#00a08e', body: '#c9ccce', cars: 10, length: 20 },
  { match: '小田急', stripe: '#2a6fc9', body: '#d2d4d6', cars: 10, length: 20 },
  { match: '井の頭', stripe: '#e8709f', body: '#d2d4d6', cars: 5, length: 20 },
  { match: '銀座', stripe: '#8a4a1c', body: '#f2b62a', cars: 6, length: 16 },
];
const DEFAULT_STOCK = { stripe: '#7b8794', body: '#c9ccce', cars: 8, length: 20 };
// Along the Line (ARCHITECTURE decision 161): in a Taiwanese area every heavy-rail line is the TRA's, and its paths
// take turns between a commuter train and an express. Formations as the reference's rail-3d formations.js
// (`commuter` 8 x 20 m as EMU700/800, EMU900 sets are 10; `emu3000` 12 cars of 20.3 m with 21.35 m ends).
// `models` names the Meshy models (tools/meshy) listed in models/trains/index.json; without them the cars
// stay boxes in the stock's livery.
const TRA_STOCK = [
  { stripe: '#f2b400', body: '#c9ccce', cars: 10, length: 20, models: { cab: 'emu900-cab', car: 'emu900-car' } },     // EMU900 區間車
  { stripe: '#e8641c', body: '#eceeee', cars: 12, length: 20.5, models: { cab: 'emu3000-cab', car: 'emu3000-car' } }, // EMU3000 自強號
];
// 台灣高鐵 N700ST: 12 cars of 25 m (Hitachi: a set is about 300 m). Its cab cars have a nose, so they are lofted
// (shellGeometry) rather than boxes. A line is the high speed railway by name, the way the Tokyo stock matches.
const HSR_STOCK = { stripe: '#ea6a1e', body: '#f6f6f4', cars: 12, length: 25, nose: 9, highSpeed: true };
const HSR_NAME = /高鐵|高速鐵/;
const SPEED = 15;        // m/s
const GAP = 350;         // metres of pause before a train re-enters
const MIN_PATH = 260;

// The livery of one car, drawn into one picture (2048 x 512): plain body and underframe swatches in the top
// 16 px, the side of the car below them, the end of the car (cab window, lamps) in the lower left corner.
// The second picture is what shines: saloon windows, lamps and the destination sign.
const TEX_W = 2048, TEX_H = 512, SIDE_Y0 = 16, SIDE_Y1 = 256;
const SWATCH_V = 1 - SIDE_Y0 / 2 / TEX_H;

// One pane of glass: dark with a frame on the side picture, lit on the glow picture.
function glass(g, e, x, y, w, h, lit = true) {
  const k = g.createLinearGradient(0, y, 0, y + h);
  k.addColorStop(0, '#2c3a47'); k.addColorStop(0.5, '#151b21'); k.addColorStop(1, '#0c1014');
  g.fillStyle = '#5c6066'; g.fillRect(x - 3, y - 3, w + 6, h + 6);    // frame
  g.fillStyle = k; g.fillRect(x, y, w, h);
  if (lit) { e.fillStyle = '#fff0d0'; e.fillRect(x, y, w, h); }
}

// Everything that is not the side or the end of a car takes one plain swatch of the livery.
function plainUv(geo, u) {
  const uv = geo.attributes.uv;
  for (let i = 0; i < uv.count; i++) uv.setXY(i, u, SWATCH_V);
  return geo;
}

function carTextures(stock) {
  if (stock.highSpeed) return highSpeedTextures(stock);
  const side = document.createElement('canvas'), glow = document.createElement('canvas');
  side.width = glow.width = TEX_W; side.height = glow.height = TEX_H;
  const g = side.getContext('2d'), e = glow.getContext('2d');
  e.fillStyle = '#000'; e.fillRect(0, 0, TEX_W, TEX_H);
  g.fillStyle = stock.body; g.fillRect(0, 0, TEX_W, TEX_H);
  g.fillStyle = '#26282b'; g.fillRect(TEX_W / 2, 0, TEX_W / 2, SIDE_Y0);  // underframe swatch
  // ---- the side
  const Y = SIDE_Y0, H = SIDE_Y1 - SIDE_Y0;
  const shade = g.createLinearGradient(0, Y, 0, Y + H);                  // a brushed body: lighter above, darker by the sill
  shade.addColorStop(0, 'rgba(255,255,255,0.16)'); shade.addColorStop(0.55, 'rgba(255,255,255,0)'); shade.addColorStop(1, 'rgba(0,0,0,0.24)');
  g.fillStyle = shade; g.fillRect(0, Y, TEX_W, H);
  g.fillStyle = 'rgba(0,0,0,0.1)'; for (let x = 0; x < TEX_W; x += 64) g.fillRect(x, Y, 1, H); // panel seams
  g.fillStyle = stock.stripe; g.fillRect(0, Y + 14, TEX_W, 12); g.fillRect(0, Y + 132, TEX_W, 18);
  g.fillStyle = 'rgba(255,255,255,0.75)'; g.fillRect(0, Y + 150, TEX_W, 3);
  g.fillStyle = '#3a3d41'; g.fillRect(0, Y + H - 22, TEX_W, 22);         // skirt
  const doors = 4, pitch = TEX_W / doors;
  for (let d = 0; d < doors; d++) {
    const x = pitch * (d + 0.5);
    for (const [wx, ww] of [[x - pitch * 0.41, pitch * 0.25], [x + pitch * 0.16, pitch * 0.25]]) glass(g, e, wx, Y + 46, ww, 74); // windows between doors
    g.fillStyle = stock.stripe; g.fillRect(x - 54, Y + 30, 108, H - 52);  // door leaves in the line colour
    g.fillStyle = 'rgba(0,0,0,0.25)'; g.fillRect(x - 56, Y + 30, 2, H - 52); g.fillRect(x + 54, Y + 30, 2, H - 52);
    glass(g, e, x - 42, Y + 48, 34, 82); glass(g, e, x + 8, Y + 48, 34, 82);
    g.fillStyle = '#2a2c2f'; g.fillRect(x - 1, Y + 30, 3, H - 52);
  }
  // destination sign by the first door: amber on black, lit
  g.fillStyle = '#0a0a0a'; g.fillRect(pitch * 0.5 - 150, Y + 30, 70, 12);
  e.fillStyle = '#ffb030'; for (let k = 0; k < 6; k++) e.fillRect(pitch * 0.5 - 146 + k * 11, Y + 33, 8, 6);
  // ---- the end: a wide cab window over the line colour, lamps low down
  const EY = SIDE_Y1, ES = TEX_H - SIDE_Y1;
  g.fillStyle = stock.body; g.fillRect(0, EY, ES, ES);
  g.fillStyle = stock.stripe; g.fillRect(0, EY + ES * 0.52, ES, ES * 0.2);
  g.fillStyle = '#3a3d41'; g.fillRect(0, EY + ES * 0.9, ES, ES * 0.1);
  glass(g, e, ES * 0.1, EY + ES * 0.1, ES * 0.8, ES * 0.36, false);
  g.fillStyle = '#0a0a0a'; g.fillRect(ES * 0.3, EY + ES * 0.03, ES * 0.4, ES * 0.055);
  e.fillStyle = '#ffb030'; e.fillRect(ES * 0.33, EY + ES * 0.04, ES * 0.34, ES * 0.035);
  for (const sx of [0.16, 0.84]) {
    g.fillStyle = '#f6f2e4'; g.beginPath(); g.arc(ES * sx, EY + ES * 0.8, ES * 0.045, 0, Math.PI * 2); g.fill();
    e.fillStyle = '#fff6e0'; e.beginPath(); e.arc(ES * sx, EY + ES * 0.8, ES * 0.045, 0, Math.PI * 2); e.fill();
    g.fillStyle = '#c01818'; g.beginPath(); g.arc(ES * (sx < 0.5 ? sx + 0.1 : sx - 0.1), EY + ES * 0.8, ES * 0.03, 0, Math.PI * 2); g.fill();
    e.fillStyle = '#ff2a1a'; e.beginPath(); e.arc(ES * (sx < 0.5 ? sx + 0.1 : sx - 0.1), EY + ES * 0.8, ES * 0.03, 0, Math.PI * 2); e.fill();
  }
  const tex = (c) => { const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8; return t; };
  return { map: tex(side), emissiveMap: tex(glow) };
}

// Car body (floor 1 m above the rail), underframe, bogies and the boxes on the roof. The long sides show the
// side of the livery, the two ends its end; everything else takes a plain swatch.
function carGeometry(length) {
  const SWATCH = SWATCH_V;
  const plain = plainUv;
  const body = new THREE.BoxGeometry(2.9, 2.75, length - 0.6).translate(0, 1.0 + 1.375, 0);
  const uv = body.attributes.uv, v0 = 1 - SIDE_Y1 / TEX_H, v1 = 1 - SIDE_Y0 / TEX_H, end = (TEX_H - SIDE_Y1) / TEX_W;
  // BoxGeometry faces: +x, -x, +y, -y, +z, -z (4 vertices each)
  for (let i = 0; i < uv.count; i++) {
    if (i < 8) uv.setY(i, v0 + uv.getY(i) * (v1 - v0));                           // the sides
    else if (i >= 16) uv.setXY(i, uv.getX(i) * end, uv.getY(i) * v0);             // the ends
    else uv.setXY(i, 0.25, SWATCH);                                                // roof and floor
  }
  const parts = [body, plain(new THREE.BoxGeometry(2.5, 0.85, length - 2.5).translate(0, 0.575, 0), 0.75)];
  for (const z of [-0.36, 0.36]) parts.push(plain(new THREE.BoxGeometry(2.3, 0.5, 3.2).translate(0, 0.25, z * length), 0.75));   // bogies
  for (const z of [-0.2, 0.2]) parts.push(plain(new THREE.BoxGeometry(1.9, 0.32, 3.6).translate(0, 3.75 + 0.16, z * length), 0.75)); // air conditioning
  const g = new THREE.BufferGeometry(), index = [];
  let count = 0;
  for (const name of ['position', 'normal', 'uv']) {
    const size = parts[0].attributes[name].itemSize, arr = new Float32Array(parts.reduce((s, p) => s + p.attributes[name].array.length, 0));
    let o = 0;
    for (const p of parts) { arr.set(p.attributes[name].array, o); o += p.attributes[name].array.length; }
    g.setAttribute(name, new THREE.BufferAttribute(arr, size));
  }
  for (const p of parts) { index.push(...Array.from(p.index.array, (i) => i + count)); count += p.attributes.position.count; }
  g.setIndex(index);
  return g;
}

// ---- Along the Line (decision 161): high-speed stock. A box cannot carry what makes a Shinkansen one, so these
// cars are lofted instead: rings of a rounded rectangle swept along the car, the cab car's front rings narrowing
// and dropping into the N700S "duck bill". Each ring point keeps how high it sits within its own ring, and that
// is the livery's v, so a band painted straight across the picture follows the nose down and forward the way the
// paint does on the real train. (Meshy's generated meshes were tried first and dropped: blobby at 391k triangles,
// and diffusion texturing cannot put a stripe at a given height.)
const RING = 24, NOSE_RINGS = 18;
const HS_HALF_W = 1.45, HS_FLOOR = 0.62, HS_ROOF = 3.75;       // the body down to the hem of its skirt, in metres above the rail
const SHOULDER = 0.66;                                          // where the crease runs, as a height within the section
const NAVY = '#2b3356', SKIRT = '#8f959b';                      // the band under the windows, and the lower body over the bogies
const ease = (x) => { const t = Math.min(1, Math.max(0, x)); return t * t * (3 - 2 * t); };

function shellRing(z, t) {
  const halfW = HS_HALF_W * (1 - 0.34 * ease((t - 0.45) / 0.55));
  const top = HS_ROOF - 1.78 * ease(t), bottom = HS_FLOOR + 0.1 * ease((t - 0.6) / 0.4);  // a broad blunt bill: 1.9 m across and 1.25 m deep at the tip
  // The last tenth rounds the bill over, so the sweep closes on a small cap instead of showing a
  // flat face with a hard rim. Head-on is the only view that catches this.
  const cap = 1 - 0.56 * ease((t - 0.88) / 0.12);
  const cy = (top + bottom) / 2, hy = ((top - bottom) / 2) * cap;
  // The section is fuller below the crease than above it, the way the body tucks in towards the roof, and it
  // widens by a little at the crease itself: that is the wing line running the length of the nose.
  const low = 2 / (8.5 - 5.6 * ease(t)), up = 2 / (4.6 - 2.3 * ease(t));
  const pts = [];
  for (let k = 0; k < RING; k++) {
    const a = -Math.PI / 2 + (2 * Math.PI * k) / RING, c = Math.cos(a), s = Math.sin(a);
    const y = cy + Math.sign(s) * Math.abs(s) ** (s < 0 ? low : up) * hy;
    const f = (y - bottom) / (top - bottom);
    const wing = 1 + 0.05 * Math.exp(-(((f - SHOULDER) / 0.1) ** 2));
    pts.push([Math.sign(c) * Math.abs(c) ** low * halfW * wing * cap, y, f]);
  }
  return { z, pts };
}

// One high-speed car: the lofted shell (the nose only on a cab car), the underframe and the bogies. The cab car
// takes the left half of the side picture, an intermediate car the right half.
function shellGeometry(stock, cab) {
  const L = stock.length - 0.6, half = L / 2, nose = cab ? stock.nose : 0;
  const rings = [shellRing(-half, 0)];
  if (nose) {
    rings.push(shellRing(half - nose, 0));
    for (let i = 1; i <= NOSE_RINGS; i++) rings.push(shellRing(half - nose + (nose * i) / NOSE_RINGS, i / NOSE_RINGS));
  } else rings.push(shellRing(half, 0));
  const u0 = cab ? 0 : 0.5, v0 = 1 - SIDE_Y1 / TEX_H, v1 = 1 - SIDE_Y0 / TEX_H;
  const pos = [], uv = [], index = [];
  // u is kept just inside this car's half of the picture, so the tip does not sample the other car's
  const uAt = (z) => u0 + 0.004 + ((z + half) / L) * 0.492;
  for (const r of rings) {
    const u = uAt(r.z);
    for (const [x, y, f] of r.pts) { pos.push(x, y, r.z); uv.push(u, v0 + f * (v1 - v0)); }
  }
  for (let i = 0; i + 1 < rings.length; i++) {
    for (let k = 0; k < RING; k++) {
      const a = i * RING + k, b = i * RING + ((k + 1) % RING);
      index.push(a, b, a + RING, b, b + RING, a + RING);
    }
  }
  const cap = (i, front) => {                                   // the flat rear end and the small face at the tip
    const r = rings[i], centre = pos.length / 3;
    let x = 0, y = 0;
    for (const p of r.pts) { x += p[0] / RING; y += p[1] / RING; }
    pos.push(x, y, r.z); uv.push(uAt(r.z), v0 + 0.5 * (v1 - v0));  // the cap takes its own ring's paint, not a swatch from elsewhere
    for (let k = 0; k < RING; k++) {
      const a = i * RING + k, b = i * RING + ((k + 1) % RING);
      if (front) index.push(centre, a, b); else index.push(centre, b, a);
    }
  };
  cap(0, false); cap(rings.length - 1, true);
  const shell = new THREE.BufferGeometry();
  shell.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  shell.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  shell.setIndex(index);
  shell.computeVertexNormals();
  // the underframe and bogies live under the body only: the nose comes down to its own hem and has nothing beneath it
  const back = -half + 1.2, forward = nose ? half - nose + 1.4 : half - 1.2;
  const parts = [shell, plainUv(new THREE.BoxGeometry(2.2, 0.45, forward - back).translate(0, 0.42, (back + forward) / 2), 0.75)];
  for (const z of [back + 2.6, forward - 2.6]) parts.push(plainUv(new THREE.BoxGeometry(2.3, 0.5, 3.2).translate(0, 0.25, z), 0.75));
  return mergeGeometries(parts);
}

// The livery of a high-speed car, in the same picture as the other stock: the plain swatches in the top 16 px,
// then the side — its left half a cab car (whose front is the nose), its right half an intermediate car. The
// N700ST is white with a thin dark line over a wide orange band below the windows, plain white under the band
// and a dark skirt, as the owner's photographs of set TS01 show.
function highSpeedTextures(stock) {
  const side = document.createElement('canvas'), glow = document.createElement('canvas');
  side.width = glow.width = TEX_W; side.height = glow.height = TEX_H;
  const g = side.getContext('2d'), e = glow.getContext('2d');
  e.fillStyle = '#000'; e.fillRect(0, 0, TEX_W, TEX_H);
  g.fillStyle = stock.body; g.fillRect(0, 0, TEX_W, TEX_H);
  g.fillStyle = '#26282b'; g.fillRect(TEX_W / 2, 0, TEX_W / 2, SIDE_Y0);  // underframe swatch
  const Y = SIDE_Y0, H = SIDE_Y1 - SIDE_Y0, HALF = TEX_W / 2, perM = HALF / stock.length;
  const row = (f) => Y + (1 - f) * H;                           // f: how high up the car's section, 0 the floor, 1 the roof
  const shade = g.createLinearGradient(0, Y, 0, Y + H);         // a gloss: lighter over the shoulder, darker by the skirt
  shade.addColorStop(0, 'rgba(255,255,255,0.12)'); shade.addColorStop(0.5, 'rgba(255,255,255,0)'); shade.addColorStop(1, 'rgba(0,0,0,0.16)');
  g.fillStyle = shade; g.fillRect(0, Y, TEX_W, H);
  g.fillStyle = SKIRT; g.fillRect(0, row(0.28), TEX_W, row(0) - row(0.28));   // the grey lower body over the bogies
  // A band of the livery from x0 to x1, between heights f0 and f1, falling by `drop` on the way (0: level). On the
  // cab car the navy and orange bands dive together towards the nose; on an intermediate car they run level.
  const band = (x0, x1, f0, f1, drop, colour) => {
    g.fillStyle = colour;
    g.beginPath();
    const edge = (f, back) => {
      for (let i = 0; i <= 24; i++) {
        const x = x0 + ((x1 - x0) * (back ? 24 - i : i)) / 24;
        g.lineTo(x, row(f - drop * ease((x - x0) / (x1 - x0))));
      }
    };
    edge(f1, false); edge(f0, true);
    g.closePath(); g.fill();
  };
  // One pane of saloon glass: the N700's small upright window with rounded ends, tinted green.
  const pane = (x, y, w, h) => {
    const r = w / 2;
    g.fillStyle = '#d8d9d6'; g.beginPath(); g.roundRect(x - 2, y - 2, w + 4, h + 4, r + 2); g.fill();
    g.fillStyle = '#1d4a44'; g.beginPath(); g.roundRect(x, y, w, h, r); g.fill();
    g.fillStyle = 'rgba(255,255,255,0.16)'; g.beginPath(); g.roundRect(x, y, w, h * 0.42, [r, r, 0, 0]); g.fill();
    e.fillStyle = '#fff0d0'; e.beginPath(); e.roundRect(x, y, w, h, r); e.fill();
  };
  // The side of one car: a door at each end in its dark frame, a row of windows between them. The doors go on
  // before the bands, because the livery runs straight across them, and the windows after.
  const DOOR = 0.85 * perM;
  const doorsOf = (x0, w) => [x0 + 1.3 * perM, x0 + w - 1.3 * perM - DOOR];
  const carDoors = (x0, w) => {
    for (const dx of doorsOf(x0, w)) {
      g.fillStyle = '#22262b'; g.fillRect(dx - 0.13 * perM, row(0.96), DOOR + 0.26 * perM, row(0.22) - row(0.96));
      g.fillStyle = stock.body; g.fillRect(dx, row(0.94), DOOR, row(0.24) - row(0.94));
    }
  };
  const carWindows = (x0, w) => {
    const top = row(0.780), h = row(0.555) - top, pitch = 1.0 * perM, pw = 0.50 * perM;
    const doors = doorsOf(x0, w);
    for (let x = doors[0] + DOOR + pitch * 0.6; x + pw < doors[1] - pitch * 0.3; x += pitch) pane(x, top, pw, h);
    for (const dx of doors) pane(dx + DOOR * 0.26, top, DOOR * 0.48, h * 0.78);
  };
  const L = stock.length - 0.6;
  const noseX = (0.004 + ((L - stock.nose) / L) * 0.492) * TEX_W;   // where the cab car's nose begins, in the same u as the shell
  carDoors(0, noseX); carDoors(HALF, HALF);
  band(HALF, TEX_W, 0.380, 0.500, 0, stock.stripe);             // an intermediate car: a level orange band, edged above
  band(HALF, TEX_W, 0.500, 0.516, 0, '#3a3f49');
  band(0, TEX_W / 2, 0.380, 0.500, 0.20, stock.stripe);         // the cab car: the orange and the navy over it dive towards the nose
  band(0, TEX_W / 2, 0.500, 0.566, 0.20, NAVY);
  carWindows(0, noseX); carWindows(HALF, HALF);
  // the cab: the canopy where the nose starts to fall, and the almond lamp of two lights on each shoulder
  const oval = (c, x, y, w, h, colour) => { c.fillStyle = colour; c.beginPath(); c.ellipse(x, y, w / 2, h / 2, 0, 0, Math.PI * 2); c.fill(); };
  g.fillStyle = 'rgba(0,0,0,0.1)'; g.fillRect(noseX, row(0.645), HALF - noseX, 3);          // the crease along its shoulder
  oval(g, noseX + 0.9 * perM, row(1), 3.4 * perM, (row(0.73) - row(1)) * 2, '#161a20');
  oval(g, noseX + 2.2 * perM, row(1), 2.0 * perM, (row(0.84) - row(1)) * 2, '#161a20');     // and on down the front
  g.fillStyle = stock.body; g.fillRect(0, row(1), noseX, row(0.70) - row(1));  // the canopy stops where the body does
  oval(g, noseX + 5.3 * perM, row(0.52), 2.1 * perM, row(0.472) - row(0.568), '#2b3036');
  for (const k of [-0.42, 0.42]) {
    oval(g, noseX + (5.3 + k) * perM, row(0.52), 0.6 * perM, row(0.482) - row(0.558), '#fbf7ea');
    oval(e, noseX + (5.3 + k) * perM, row(0.52), 0.6 * perM, row(0.482) - row(0.558), '#fff4de');
  }
  const tex = (c) => { const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8; return t; };
  return { map: tex(side), emissiveMap: tex(glow) };
}

// Chains lines of the same name end to start into paths: [{ name, pts: [[x, y, z]], cum: [distance], length }].
function chain(lines) {
  const key = (x, z) => x.toFixed(1) + ',' + z.toFixed(1);
  const items = lines.map((l) => {
    const pts = [];
    for (let i = 0; i < l.pts.length; i += 3) pts.push([l.pts[i], l.pts[i + 1], l.pts[i + 2]]);
    return { name: l.name ?? '', railway: l.railway, pts, start: key(pts[0][0], pts[0][2]), end: key(pts.at(-1)[0], pts.at(-1)[2]), used: false };
  });
  const byStart = new Map();
  for (const it of items) { const k = it.name + '|' + it.start; if (!byStart.has(k)) byStart.set(k, []); byStart.get(k).push(it); }
  const ends = new Set(items.map((it) => it.name + '|' + it.end));
  const paths = [];
  // begin at lines nothing leads into, then sweep up any loops left over
  for (const it of [...items.filter((i) => !ends.has(i.name + '|' + i.start)), ...items]) {
    if (it.used) continue;
    const pts = [];
    for (let cur = it; cur && !cur.used; cur = (byStart.get(cur.name + '|' + cur.end) ?? []).find((n) => !n.used)) {
      cur.used = true;
      pts.push(...(pts.length ? cur.pts.slice(1) : cur.pts));
    }
    const cum = [0];
    for (let i = 1; i < pts.length; i++) cum.push(cum[i - 1] + Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][2] - pts[i - 1][2]));
    if (cum.at(-1) >= MIN_PATH) paths.push({ name: it.name, railway: it.railway, pts, cum, length: cum.at(-1) });
  }
  return paths;
}

function pointAt(path, s, out) {
  const { pts, cum } = path;
  let lo = 0, hi = cum.length - 1;
  while (hi - lo > 1) { const mid = (lo + hi) >> 1; if (cum[mid] <= s) lo = mid; else hi = mid; }
  const t = (s - cum[lo]) / (cum[hi] - cum[lo] || 1), a = pts[lo], b = pts[hi];
  return out.set(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t);
}

// Along the Line (decision 161): a Meshy car (tools/meshy) as one geometry and material for an InstancedMesh, in the frame of carGeometry: the
// cab (`front`, the axis it faces in the model) towards +z, the rail top at y = 0, the body fitted to the stock's
// car length, 2.9 m wide and 3.9 m tall. Null when the model is not there: the cars stay boxes.
const loader = new GLTFLoader();
async function carModel(url, front, length) {
  let gltf;
  try { gltf = await loader.loadAsync(url); } catch { return null; }
  gltf.scene.updateMatrixWorld(true);
  const parts = [];
  let material;
  gltf.scene.traverse((o) => {
    if (!o.isMesh) return;
    const g = o.geometry.clone().applyMatrix4(o.matrixWorld);
    for (const name of Object.keys(g.attributes)) if (!['position', 'normal', 'uv'].includes(name)) g.deleteAttribute(name);
    parts.push(g.index ? g : g.toNonIndexed());
    material ??= Array.isArray(o.material) ? o.material[0] : o.material;
  });
  if (!parts.length) return null;
  const geometry = parts.length === 1 ? parts[0] : mergeGeometries(parts.map((g) => (g.index ? g.toNonIndexed() : g)));
  if (!geometry) return null;
  const turn = { '+z': 0, '-z': Math.PI, '+x': -Math.PI / 2, '-x': Math.PI / 2 }[front] ?? -Math.PI / 2;
  geometry.rotateY(turn);
  geometry.computeBoundingBox();
  const box = geometry.boundingBox, size = box.getSize(new THREE.Vector3()), centre = box.getCenter(new THREE.Vector3());
  geometry.translate(-centre.x, -box.min.y, -centre.z);
  geometry.scale(2.9 / size.x, 3.9 / size.y, (length - 0.6) / size.z);
  if (!geometry.attributes.normal) geometry.computeVertexNormals();
  material.side = THREE.FrontSide;
  return { geometry, material };
}

export class Trains {
  constructor(lines, { taiwan = false } = {}) {
    this.group = new THREE.Group();
    this.group.name = 'trains';
    this.lamps = new THREE.Group(); // the headlamps' light on the track: in the lamp light's scene (lamplight.js)
    lampScene.add(this.lamps);
    this.sets = [];
    const paths = chain(lines);
    this.beam = lampMaterial(beamTexture());
    const stocks = new Map(); // stock -> paths
    let tra = 0;
    for (const p of paths) {
      const stock = taiwan && p.railway === 'rail' ? (HSR_NAME.test(p.name) ? HSR_STOCK : TRA_STOCK[tra++ % TRA_STOCK.length])
        : STOCK.find((s) => p.name.includes(s.match)) ?? DEFAULT_STOCK;
      if (!stocks.has(stock)) stocks.set(stock, []);
      stocks.get(stock).push(p);
    }
    for (const [stock, list] of stocks) {
      const paint = stock.highSpeed ? { roughness: 0.2, metalness: 0.08 } : { roughness: 0.32, metalness: 0.55 }; // painted gloss, not brushed steel
      const material = new THREE.MeshStandardMaterial({ ...carTextures(stock), ...paint, emissive: 0xffffff, emissiveIntensity: 0 });
      const instance = (geometry, count) => {
        const im = new THREE.InstancedMesh(geometry, material, Math.max(1, count));
        im.castShadow = im.receiveShadow = true;
        im.frustumCulled = false; // cars move across the whole area
        this.group.add(im);
        return im;
      };
      // a stock whose cab cars have a nose is lofted, so its two ends and its middle are different geometries
      const model = stock.nose
        ? { cabs: instance(shellGeometry(stock, true), list.length * 2), cars: instance(shellGeometry(stock, false), list.length * (stock.cars - 2)) }
        : null;
      const mesh = model ? null : instance(carGeometry(stock.length), list.length * stock.cars);
      // the light of the leading car's headlamps on the track ahead (one pool per train; see the cars' in traffic.js)
      const pool = new THREE.BufferGeometry(), z0 = stock.length / 2 - 0.5, z1 = stock.length / 2 + 55;
      pool.setAttribute('position', new THREE.Float32BufferAttribute([-4.5, 0.12, z0, 4.5, 0.12, z0, 4.5, 0.12, z1, -4.5, 0.12, z0, 4.5, 0.12, z1, -4.5, 0.12, z1], 3));
      pool.setAttribute('uv', new THREE.Float32BufferAttribute([0, 0, 1, 0, 1, 1, 0, 0, 1, 1, 0, 1], 2));
      const beams = new THREE.InstancedMesh(pool, this.beam, list.length);
      beams.frustumCulled = false;
      beams.layers.set(LAMP_LAYER);
      this.lamps.add(beams);
      this.sets.push({ stock, mesh, model, beams, material, trains: list.map((path, i) => ({ path, s: (i * 613) % (path.length + GAP) })) });
    }
    this.dummy = new THREE.Object3D();
    this.a = new THREE.Vector3(); this.b = new THREE.Vector3();
    this.ready = this.loadModels(); // (the boxes run until the models arrive)
  }

  // Along the Line (decision 161): swaps a stock's boxes for its Meshy models: the cab model at both ends (the rear one turned round), the middle
  // model between them. A stock with only one of the two uses it for every car.
  async loadModels() {
    const wanted = this.sets.filter((set) => set.stock.models);
    if (!wanted.length) return;
    let index;
    try { index = await (await fetch('models/trains/index.json')).json(); } catch { return; }
    await Promise.all(wanted.map(async (set) => {
      const { stock, trains } = set, load = (id) => (index[id] ? carModel(`models/trains/${index[id].file}`, index[id].front, stock.length) : null);
      const [cab, car] = await Promise.all([load(stock.models.cab), load(stock.models.car)]);
      if (!cab && !car) return;
      const mesh = (m, count) => {
        const im = new THREE.InstancedMesh(m.geometry, m.material, Math.max(1, count));
        im.castShadow = im.receiveShadow = true;
        im.frustumCulled = false;
        this.group.add(im);
        return im;
      };
      set.model = { cabs: mesh(cab ?? car, trains.length * 2), cars: mesh(car ?? cab, trains.length * Math.max(0, stock.cars - 2)) };
      this.group.remove(set.mesh);
      set.mesh.geometry.dispose();
    }));
  }

  update(dt, night) {
    const { dummy, a, b } = this;
    this.beam.color.setRGB(2.2 * night, 2.1 * night, 1.8 * night);
    this.beam.visible = night > 0.02;
    for (const { stock, mesh, beams, material, trains, model } of this.sets) {
      material.emissiveIntensity = 0.2 + night * 2.2; // the saloon lights and the lamps are always on
      let n = 0, ends = 0, middles = 0;
      const put = (c, matrix) => {
        if (!model) mesh.setMatrixAt(n, matrix);
        else if (c === 0 || c === stock.cars - 1) model.cabs.setMatrixAt(ends++, matrix);
        else model.cars.setMatrixAt(middles++, matrix);
      };
      trains.forEach((t, ti) => {
        const span = t.path.length + stock.cars * stock.length + GAP;
        t.s = (t.s + SPEED * dt) % span; // distance of the train's nose from the start of the path
        for (let c = 0; c < stock.cars; c++, n++) {
          const centre = t.s - (c + 0.5) * stock.length, half = stock.length * 0.36;
          if (centre - half < 0 || centre + half > t.path.length) { dummy.scale.setScalar(0); dummy.updateMatrix(); put(c, dummy.matrix); if (c === 0) beams.setMatrixAt(ti, dummy.matrix); continue; }
          pointAt(t.path, centre + half, a); pointAt(t.path, centre - half, b); // the two bogies
          dummy.position.copy(a).add(b).multiplyScalar(0.5);
          dummy.position.y += 0.16; // on top of the rails
          dummy.scale.setScalar(1);
          dummy.lookAt(a.x, a.y + 0.16, a.z);
          dummy.updateMatrix();
          if (c === 0) beams.setMatrixAt(ti, dummy.matrix);
          if (model && c > 0 && c === stock.cars - 1) { dummy.rotateY(Math.PI); dummy.updateMatrix(); } // the rear cab faces back
          put(c, dummy.matrix);
        }
      });
      if (mesh) mesh.instanceMatrix.needsUpdate = true;
      if (model) model.cabs.instanceMatrix.needsUpdate = model.cars.instanceMatrix.needsUpdate = true;
      beams.instanceMatrix.needsUpdate = true;
    }
  }
}
