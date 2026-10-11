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
// 臺鐵 EMU900 區間車: still boxes. Its cab is flat-fronted, so it needs no nose, but its band is the
// bright green of its "smile" livery, not the yellow this was: the owner's own tra_special_trains.json
// says 「彎彎的『微笑頭燈』配亮綠色腰帶」, and every public source says silver and green.
const EMU900_STOCK = { stripe: '#7ac143', body: '#c9ccce', cars: 10, length: 20.3, models: { cab: 'emu900-cab', car: 'emu900-car' } };
// A line is the high speed railway by name, the way the Tokyo stock matches. The TRA's own lines
// carry both kinds, and their OSM names say which line they are, not which train runs on them, so
// the paths take turns between the commuter stock and the express, as they did before.
// A lofted stock: its cab cars have a nose, so they are swept (shellGeometry) rather than boxed, and
// everything that differs between two such trains is data. `shell` is the section in metres above the
// rail; `livery` is painted in f, how high up that section a thing sits (0 the skirt hem, 1 the roof).
// Measure a reference with .claude/skills/rolling-stock/measure.cjs before filling either in.
// `models` are the ones tools/trains/build_train.py builds in Blender: the same loft as shellGeometry
// below, plus window units and door leaves standing proud of the body and the occlusion that collects
// around them, baked into a second UV channel. The livery stays this file's: the model's first UV
// channel is written in the very coordinates highSpeedTextures paints in, so the canvas below dresses
// the Blender car as it dresses the lofted one. Until the model arrives the lofted car runs.
const HSR_STOCK = {
  stripe: '#ea6a1e', body: '#f6f6f4', cars: 12, length: 25, nose: 9, highSpeed: true,
  models: { cab: 'n700st-cab', car: 'n700st-car' },
  // 台灣高鐵 N700ST: 12 cars of 25 m (Hitachi: a set is about 300 m). Dimensions are the N700S's,
  // which is all any public source gives; the nose is shaped from the owner's photographs.
  shell: { halfW: 1.45, floor: 0.62, roof: 3.75, drop: 1.78, lift: 0.1, tuck: 0.34, cap: 0.56, wing: 0.05, shoulder: 0.66 },
  livery: {
    body: '#f6f6f4', skirt: '#8f959b', skirtTop: 0.28,
    bands: [{ from: 0.380, to: 0.500, colour: '#ea6a1e', dive: 0.20 },
            { from: 0.500, to: 0.566, colour: '#2b3356', dive: 0.20 }],
    // `lit` is dim because the material keeps a little emissive on by day: left at the default the
    // saloon lights washed this train's dark green glass out to pale grey in full sun.
    window: { from: 0.555, to: 0.780, pitch: 1.0, width: 0.50, tint: '#1d4a44', lit: '#8a7f63' },
    door: { width: 0.85, frame: '#22262b', leaf: '#f6f6f4' },
    // `screen` is the windscreen in the nose's own chart (NOSE): `from`/`to` along the nose, `wide`
    // and `narrow` how far it reaches across at each end. The canopy drawn at a height — what this
    // replaces — came out as a black visor right round the front.
    cab: { crease: 0.645, glass: '#161a20', canopyStops: 0.70,
           screen: { from: 0.10, to: 0.34, wide: 0.52, narrow: 0.30, surround: '#eceded' },
           canopy: [{ at: 0.9, length: 3.4, to: 0.73 }, { at: 2.2, length: 2.0, to: 0.84 }],
           lamp: { at: 5.0, f: 0.50, width: 1.0, tall: 0.024, lens: 0.26, gap: 0.22, housing: '#49505a' } },
  },
};
// 臺鐵 EMU3000 新自強號: 12 cars, cabs at both ends (the owner: 車頭 = 車尾). The dimensions are the
// owner's fleet catalogue, each with its own source, and agree with measure.cjs on his own mesh to the
// centimetre: body 2.91 m wide (half-width 1.455), roof 3.49, pantograph 3.75, floor 1.18. The colours
// are the material names in his EMU3000 model. The nose is the one thing no reference carries — all
// three of his are map-scale and narrow for barely 2 m — so 4 m here is a judgement, not a measurement.
const EMU3000_STOCK = {
  stripe: '#9c385c', body: '#f6f3ee', cars: 12, length: 20.5, nose: 5.4, highSpeed: true,
  shell: { halfW: 1.455, floor: 0.53, roof: 3.49, drop: 1.15, lift: 0.18, tuck: 0.3, cap: 0.46, wing: 0.03, shoulder: 0.72 },
  livery: {
    body: '#f6f3ee', skirt: '#9aa0a4', skirtTop: 0.12,
    // The owner's photographs overrule his own model here. It paints a wide crimson waist band; the
    // real train has none. Its side is plain white with a thin dark line under the windows, and the
    // colour that names the set is only a short accent high up by each car's end.
    bands: [{ from: 0.700, to: 0.726, colour: '#2a3340' }],
    window: { from: 0.470, to: 0.700, pitch: 1.35, width: 0.70, round: 0.18, tint: '#1b2634', frame: '#b7bbbd', lit: '#c8bb94' },
    door: { width: 1.0, frame: '#aeb3b6', leaf: '#f2f1ec' },
    cab: { crease: 0, glass: '#222a38', canopyStops: 0.80,
           mask: { from: 0.86, dive: 0.62 },
           canopy: [{ at: 1.1, length: 3.0, to: 0.80 }],
           lamp: { at: 3.9, f: 0.60, width: 1.5, tall: 0.045, lens: 0.52, gap: 0.36, housing: '#1b2330' } },
  },
};
// Along the Line: the owner's call (2026-10-11): every heavy-rail line of a Taiwanese area runs his N700ST
// (HSR_STOCK, his Meshy model), the TRA's viaduct at Taichung included. The TRA's two stay here for when its
// own trains come back; nothing picks them now.
const TRA_STOCK = [EMU900_STOCK, EMU3000_STOCK];
const HSR_NAME = /高鐵|高速鐵/;
const SPEED = 15;        // m/s
const GAP = 350;         // metres of pause before a train re-enters
const MIN_PATH = 260;

// The livery of one car, drawn into one picture (2048 x 512): plain body and underframe swatches in the top
// 16 px, the side of the car below them, the end of the car (cab window, lamps) in the lower left corner.
// The second picture is what shines: saloon windows, lamps and the destination sign.
const TEX_W = 2048, TEX_H = 512, SIDE_Y0 = 16, SIDE_Y1 = 256;
const SWATCH_V = 1 - SIDE_Y0 / 2 / TEX_H;
// One mapping from a place on a car to a place in the picture, for the painter and the geometry
// alike: a car body is `length - 0.6` m long and its half of the picture runs from u0 + U0 to
// u0 + U0 + USPAN, kept just inside the half so the nose cannot sample the other car's paint.
// tools/trains/build_train.py writes the same one into the models it builds, which is what lets one
// canvas dress a car modelled in Blender. Painting on one scale and modelling on another leaves the
// window glass sitting beside the window.
const U0 = 0.004, USPAN = 0.492;
const uOf = (m, L, u0) => u0 + U0 + (m / L) * USPAN;   // m: metres from the car's rear end
// The top of the nose, as its own little picture, in the lower half no other stock uses.
//
// Everything else on a car is painted in (along, how high up the section): one coordinate says where
// you are along the car and the other how high you sit in its own ring. That is what makes a band
// painted straight across follow the nose down for free — and it is also why anything painted at a
// height goes right around the ring. A windscreen cannot be painted that way: it comes out as a
// visor across the whole front, which is exactly how the first N700ST looked head-on. So the top of
// the nose gets a second chart, laid out along the nose and across it, and the glass is drawn in it
// as the shape it is. Only a stock whose cab has a `screen` uses it; the EMU3000 wears its whole
// nose as one dark mask, which the height mapping does perfectly well.
// `across` is the point's own lateral position, not its place in the ring: the section is a
// superellipse, which keeps the top nearly flat, so three of the six rings either side of the
// centre line sit in the outer fifth of the width. Measuring across in metres makes the chart a
// view from above, which is what a windscreen can be drawn in.
const NOSE = { x0: 16, x1: 1456, y0: 264, y1: 504, rings: 3 };
const noseUv = (along, across) => [(NOSE.x0 + along * (NOSE.x1 - NOSE.x0)) / TEX_W,
                                   1 - (NOSE.y0 + across * (NOSE.y1 - NOSE.y0)) / TEX_H];
const noseAcross = (y, edge) => 0.5 - (0.5 * y) / edge;
const noseChart = (stock, cab) => (cab && stock.nose && stock.livery?.cab?.screen
  ? { k0: RING / 2 - NOSE.rings, k1: RING / 2 + NOSE.rings } : null);

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
const RING = 28, NOSE_RINGS = 22;
const ease = (x) => { const t = Math.min(1, Math.max(0, x)); return t * t * (3 - 2 * t); };

// One ring of a lofted shell at `z`, `t` along the nose (0 at the body, 1 at the tip). `shell` is the
// stock's own section, in metres above the rail. Each point carries how high it sits within its own
// ring, and that is the livery's v, so a band painted straight across the picture follows the nose
// down and forward the way the paint does on the real train.
function shellRing(z, t, shell) {
  const halfW = shell.halfW * (1 - shell.tuck * ease((t - 0.45) / 0.55));
  const top = shell.roof - shell.drop * ease(t), bottom = shell.floor + shell.lift * ease((t - 0.6) / 0.4);
  // The last eighth rounds the end over, so the sweep closes on a small cap instead of showing a flat
  // face with a hard rim. Head-on is the only view that catches this.
  const cap = 1 - shell.cap * ease((t - 0.88) / 0.12);
  const cy = (top + bottom) / 2, hy = ((top - bottom) / 2) * cap;
  // The section is fuller below the crease than above it, the way a body tucks in towards its roof,
  // and it widens by a little at the crease itself: that is the wing line running along the nose.
  const low = 2 / (8.5 - 5.6 * ease(t)), up = 2 / (4.6 - 2.3 * ease(t));
  const pts = [];
  for (let k = 0; k < RING; k++) {
    const a = -Math.PI / 2 + (2 * Math.PI * k) / RING, c = Math.cos(a), s = Math.sin(a);
    const y = cy + Math.sign(s) * Math.abs(s) ** (s < 0 ? low : up) * hy;
    const f = (y - bottom) / (top - bottom);
    const wing = 1 + shell.wing * Math.exp(-(((f - shell.shoulder) / 0.1) ** 2));
    pts.push([Math.sign(c) * Math.abs(c) ** low * halfW * wing * cap, y, f]);
  }
  return { z, pts };
}

// One lofted car: the shell (with the nose only on a cab car), the underframe and the bogies. The cab
// car takes the left half of the side picture, an intermediate car the right half.
function shellGeometry(stock, cab) {
  const L = stock.length - 0.6, half = L / 2, nose = cab ? stock.nose : 0, sh = stock.shell;
  const rings = [shellRing(-half, 0, sh)];
  if (nose) {
    rings.push(shellRing(half - nose, 0, sh));
    for (let i = 1; i <= NOSE_RINGS; i++) rings.push(shellRing(half - nose + (nose * i) / NOSE_RINGS, i / NOSE_RINGS, sh));
  } else rings.push(shellRing(half, 0, sh));
  const u0 = cab ? 0 : 0.5, v0 = 1 - SIDE_Y1 / TEX_H, v1 = 1 - SIDE_Y0 / TEX_H;
  const pos = [], uv = [], index = [];
  // u is kept just inside this car's half of the picture, so the tip does not sample the other car's
  const uAt = (z) => uOf(z + half, L, u0);
  for (const r of rings) {
    const u = uAt(r.z);
    for (const [x, y, f] of r.pts) { pos.push(x, y, r.z); uv.push(u, v0 + f * (v1 - v0)); }
  }
  // The nose's top, when this stock has a windscreen, is left out of the sweep and laid again below
  // with the chart's coordinates: a vertex can carry only one pair, so the band is its own surface.
  const chart = noseChart(stock, cab), noseFrom = 1;
  const inChart = (i, k) => chart && i >= noseFrom && i < noseFrom + NOSE_RINGS && k >= chart.k0 && k < chart.k1;
  for (let i = 0; i + 1 < rings.length; i++) {
    for (let k = 0; k < RING; k++) {
      if (inChart(i, k)) continue;
      const a = i * RING + k, b = i * RING + ((k + 1) % RING);
      index.push(a, b, a + RING, b, b + RING, a + RING);
    }
  }
  if (chart) {
    const base = pos.length / 3, across = chart.k1 - chart.k0;
    for (let i = noseFrom; i <= noseFrom + NOSE_RINGS; i++) {
      const edge = rings[i].pts[chart.k0][0];
      for (let k = chart.k0; k <= chart.k1; k++) {
        const [x, y] = rings[i].pts[k];
        pos.push(x, y, rings[i].z);
        uv.push(...noseUv((i - noseFrom) / NOSE_RINGS, noseAcross(x, edge)));
      }
    }
    const w = across + 1;
    for (let i = 0; i < NOSE_RINGS; i++) {
      for (let k = 0; k < across; k++) {
        const a = base + i * w + k, b = a + 1;
        index.push(a, b, a + w, b, b + w, a + w);
      }
    }
  }
  const cap = (i, front) => {                                   // the flat rear end and the small face at the tip
    const r = rings[i], centre = pos.length / 3;
    let x = 0, y = 0;
    for (const p of r.pts) { x += p[0] / RING; y += p[1] / RING; }
    pos.push(x, y, r.z); uv.push(uAt(r.z), v0 + 0.5 * (v1 - v0));  // the cap takes its own ring's paint
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
  // The underframe and bogies live under the body only: the nose has nothing beneath it. What makes
  // a train read as a train at this distance is not a smoother tube but the kit on it — the boxes
  // along the roof, the wheels under the skirt — so that is where the triangles go.
  const back = -half + 1.2, forward = nose ? half - nose + 1.4 : half - 1.2;
  const parts = [shell, plainUv(new THREE.BoxGeometry(2.2, 0.45, forward - back).translate(0, 0.42, (back + forward) / 2), 0.75)];
  for (const k of [-0.22, 0.22]) parts.push(plainUv(new THREE.BoxGeometry(1.5, 0.5, 2.4).translate(0, 0.62, (back + forward) / 2 + k * (forward - back)), 0.75)); // underfloor equipment
  for (const z of [back + 2.6, forward - 2.6]) {
    parts.push(plainUv(new THREE.BoxGeometry(2.1, 0.42, 2.9).translate(0, 0.62, z), 0.75));       // bogie frame
    for (const wz of [z - 1.15, z + 1.15]) for (const wx of [-1.06, 1.06]) {
      const wheel = new THREE.CylinderGeometry(0.43, 0.43, 0.14, 12).rotateZ(Math.PI / 2).translate(wx, 0.43, wz);
      parts.push(plainUv(wheel, 0.75));
    }
  }
  // Roof: the air-conditioning run and the cable ducts beside it, over the body only.
  const roof = sh.roof, runFrom = back + 0.6, runTo = forward - 0.6, units = Math.max(2, Math.round((runTo - runFrom) / 3.2));
  for (let i = 0; i < units; i++) {
    const z = runFrom + ((runTo - runFrom) * (i + 0.5)) / units;
    parts.push(plainUv(new THREE.BoxGeometry(1.9, 0.26, 2.1).translate(0, roof + 0.08, z), 0.25));
  }
  for (const x of [-0.95, 0.95]) parts.push(plainUv(new THREE.BoxGeometry(0.26, 0.14, runTo - runFrom).translate(x, roof + 0.04, (runFrom + runTo) / 2), 0.75));
  return mergeGeometries(parts);
}

// The windscreen, painted into the nose's own chart (NOSE). `along` runs from the cab roof (0) to
// the tip (1) and `across` from one side of the chart's band to the other, so the glass can be the
// shape it really is: wide where it meets the roof, narrowing forward, with its corners rounded.
function windscreen(g, lv, ws, glass) {
  const W = NOSE.x1 - NOSE.x0, H = NOSE.y1 - NOSE.y0, mid = NOSE.y0 + H / 2;
  g.fillStyle = lv.body; g.fillRect(NOSE.x0 - 12, NOSE.y0 - 12, W + 24, H + 24);
  const at = (a) => NOSE.x0 + a * W, side = (s) => mid + (s * H) / 2;
  // Stroking the path with a round join and then filling is what rounds the corners of a trapezoid;
  // roundRect only does rectangles.
  const panel = (fill, ga, gs, r) => {
    g.fillStyle = fill; g.strokeStyle = typeof fill === 'string' ? fill : '#000';
    g.lineJoin = 'round'; g.lineWidth = r;
    g.beginPath();
    g.moveTo(at(ws.from - ga), side(-ws.wide - gs));
    g.lineTo(at(ws.to + ga), side(-ws.narrow - gs));
    g.lineTo(at(ws.to + ga), side(ws.narrow + gs));
    g.lineTo(at(ws.from - ga), side(ws.wide + gs));
    g.closePath();
    if (typeof fill === 'string') g.stroke();
    g.fill();
  };
  panel(ws.surround, 0.018, 0.20, 34);          // the body the glass is set into
  // The glass takes the sky at the back and darkens where it turns down towards the tip. Painted
  // near-black instead it reads as a hole cut in the nose, not as glass.
  const sky = g.createLinearGradient(at(ws.from), 0, at(ws.to), 0);
  sky.addColorStop(0, '#7f90a8'); sky.addColorStop(0.4, '#44516a'); sky.addColorStop(1, '#232a36');
  g.strokeStyle = '#44516a'; g.lineJoin = 'round'; g.lineWidth = 14;
  g.beginPath();
  g.moveTo(at(ws.from), side(-ws.wide)); g.lineTo(at(ws.to), side(-ws.narrow));
  g.lineTo(at(ws.to), side(ws.narrow)); g.lineTo(at(ws.from), side(ws.wide));
  g.closePath(); g.stroke();
  g.fillStyle = sky; g.fill();
}

// The livery of a lofted car, in the same picture as the other stock: the plain swatches in the top
// 16 px, then the side — its left half a cab car (whose front is the nose), its right half an
// intermediate car. Everything that differs between trains is in the stock's `livery` record.
function highSpeedTextures(stock) {
  const side = document.createElement('canvas'), glow = document.createElement('canvas');
  side.width = glow.width = TEX_W; side.height = glow.height = TEX_H;
  const g = side.getContext('2d'), e = glow.getContext('2d');
  const lv = stock.livery;
  e.fillStyle = '#000'; e.fillRect(0, 0, TEX_W, TEX_H);
  g.fillStyle = lv.body; g.fillRect(0, 0, TEX_W, TEX_H);
  g.fillStyle = '#26282b'; g.fillRect(TEX_W / 2, 0, TEX_W / 2, SIDE_Y0);  // underframe swatch
  const Y = SIDE_Y0, H = SIDE_Y1 - SIDE_Y0, HALF = TEX_W / 2;
  const row = (f) => Y + (1 - f) * H;                           // f: how high up the section, 0 the floor, 1 the roof
  const shade = g.createLinearGradient(0, Y, 0, Y + H);         // a gloss: lighter over the shoulder, darker by the skirt
  shade.addColorStop(0, 'rgba(255,255,255,0.12)'); shade.addColorStop(0.5, 'rgba(255,255,255,0)'); shade.addColorStop(1, 'rgba(0,0,0,0.16)');
  g.fillStyle = shade; g.fillRect(0, Y, TEX_W, H);
  // The picture's scale is the geometry's own (uOf): `perM` pixels to the metre, and a car's rear end
  // at `rearOf(u0)`. A cab car's painted side runs from there to where the nose begins.
  const L = stock.length - 0.6, perM = (USPAN * TEX_W) / L;
  const rearOf = (u0) => (u0 + U0) * TEX_W;
  const CAB = rearOf(0), MID = rearOf(0.5), noseX = CAB + (L - stock.nose) * perM;
  // A band from x0 to x1 between heights f0 and f1, falling by `dive` on the way. The N700ST's cab car
  // dives its bands towards the nose; EMU3000's run level.
  // `dive` is how far the band falls on the way: one number moves both edges together, a pair moves
  // the lower and the upper edge by different amounts, which is how the EMU3000's nose mask keeps its
  // top at the roof while its lower edge sweeps down to the coupler.
  const band = (x0, x1, f0, f1, dive, colour) => {
    const [d0, d1] = Array.isArray(dive) ? dive : [dive, dive];
    g.fillStyle = colour;
    g.beginPath();
    const edge = (f, d, back) => {
      for (let i = 0; i <= 24; i++) {
        const x = x0 + ((x1 - x0) * (back ? 24 - i : i)) / 24;
        g.lineTo(x, row(f - d * ease((x - x0) / (x1 - x0))));
      }
    };
    edge(f1, d1, false); edge(f0, d0, true);
    g.closePath(); g.fill();
  };
  // One pane of saloon glass: an upright window with rounded ends, in the stock's own tint.
  const pane = (x, y, w, h) => {
    // A capsule on the N700ST, a rounded rectangle on the EMU3000: `round` is the corner radius as a
    // fraction of the pane's width, and 0.5 is as round as a pane can be.
    const r = w * (lv.window.round ?? 0.5);
    g.fillStyle = lv.window.frame ?? '#d8d9d6'; g.beginPath(); g.roundRect(x - 2, y - 2, w + 4, h + 4, r + 2); g.fill();
    g.fillStyle = lv.window.tint; g.beginPath(); g.roundRect(x, y, w, h, r); g.fill();
    g.fillStyle = 'rgba(255,255,255,0.16)'; g.beginPath(); g.roundRect(x, y, w, h * 0.42, [r, r, 0, 0]); g.fill();
    // The glow picture is what the saloon lights shine out of at night. A pane painted solid there
    // also lifts the glass by day (the material keeps a little emissive on), which on a train whose
    // windows read dark in daylight is wrong, so each stock says how brightly its glass is lit.
    e.fillStyle = lv.window.lit ?? '#fff0d0'; e.beginPath(); e.roundRect(x, y, w, h, r); e.fill();
  };
  // The side of one car: a door at each end in its frame, a row of windows between them. The doors go
  // on before the bands, because the livery runs straight across them, and the windows after.
  // `span` is how long the painted side of this car is, in metres: a cab car's stops at the nose.
  const DOOR = lv.door.width * perM;
  const doorsOf = (x0, span) => [x0 + 1.3 * perM, x0 + (span - 1.3) * perM - DOOR];
  const carDoors = (x0, span) => {
    for (const dx of doorsOf(x0, span)) {
      g.fillStyle = lv.door.frame; g.fillRect(dx - 0.13 * perM, row(0.96), DOOR + 0.26 * perM, row(0.22) - row(0.96));
      g.fillStyle = lv.door.leaf; g.fillRect(dx, row(0.94), DOOR, row(0.24) - row(0.94));
    }
  };
  const carWindows = (x0, span) => {
    const top = row(lv.window.to), h = row(lv.window.from) - top;
    const pitch = lv.window.pitch * perM, pw = lv.window.width * perM;
    const doors = doorsOf(x0, span);
    for (let x = doors[0] + DOOR + pitch * 0.6; x + pw < doors[1] - pitch * 0.3; x += pitch) pane(x, top, pw, h);
    for (const dx of doors) pane(dx + DOOR * 0.26, top, DOOR * 0.48, h * 0.78);
  };
  carDoors(CAB, L - stock.nose); carDoors(MID, L);
  // The skirt goes on after the doors and before the bands: a door runs down into it on the real
  // train, but it does not take the body's colour down there, and painting it first left a white
  // notch in the grey at every door.
  g.fillStyle = lv.skirt; g.fillRect(0, row(lv.skirtTop), TEX_W, row(0) - row(lv.skirtTop));
  for (const b of lv.bands) {
    band(HALF, TEX_W, b.from, b.to, 0, b.colour);                 // an intermediate car: level
    band(0, HALF, b.from, b.to, b.dive ?? 0, b.colour);           // a cab car: it may dive to the nose
  }
  carWindows(CAB, L - stock.nose); carWindows(MID, L);
  // the cab: the canopy where the nose starts to fall, and the lamps on its shoulders
  const oval = (c, x, y, w, h, colour) => { c.fillStyle = colour; c.beginPath(); c.ellipse(x, y, w / 2, h / 2, 0, 0, Math.PI * 2); c.fill(); };
  const cab = lv.cab;
  if (cab.crease) { g.fillStyle = 'rgba(0,0,0,0.1)'; g.fillRect(noseX, row(cab.crease), HALF - noseX, 3); }
  // The EMU3000 wears its whole nose as one dark mask, windscreen and all, white only along the
  // lower flanks; the N700ST has no mask, just a canopy, so this is absent there.
  if (cab.mask) band(noseX, HALF, cab.mask.from, 1, [cab.mask.dive, 0], cab.glass);
  if (cab.screen) windscreen(g, lv, cab.screen, cab.glass);
  else {
    for (const c of cab.canopy) oval(g, noseX + c.at * perM, row(1), c.length * perM, (row(c.to) - row(1)) * 2, cab.glass);
    g.fillStyle = lv.body; g.fillRect(0, row(1), noseX, row(cab.canopyStops) - row(1));  // it stops where the body does
  }
  const lp = cab.lamp;
  oval(g, noseX + lp.at * perM, row(lp.f), lp.width * perM, row(lp.f - lp.tall) - row(lp.f + lp.tall), lp.housing);
  for (const k of [-lp.gap, lp.gap]) {
    oval(g, noseX + (lp.at + k) * perM, row(lp.f), lp.lens * perM, row(lp.f - lp.tall * 0.55) - row(lp.f + lp.tall * 0.55), '#fbf7ea');
    oval(e, noseX + (lp.at + k) * perM, row(lp.f), lp.lens * perM, row(lp.f - lp.tall * 0.55) - row(lp.f + lp.tall * 0.55), '#fff4de');
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

// Along the Line (decision 161): a car model as one geometry and material for an InstancedMesh, in the frame of
// carGeometry: the cab (`front`, the axis it faces in the model) towards +z and the rail top at y = 0. A Meshy
// model (tools/meshy) is then fitted to the stock's car length, 2.9 m wide and 3.9 m tall, because nothing about
// a generated mesh's scale can be relied on; one from tools/trains/build_train.py says `fit: false` in the index,
// because it was modelled in the game's own metres and squeezing it into a box would only lose them. Null when
// the model is not there: the cars stay as they were.
const loader = new GLTFLoader();
async function carModel(url, { front, fit = true }, length) {
  let gltf;
  try { gltf = await loader.loadAsync(url); } catch { return null; }
  gltf.scene.updateMatrixWorld(true);
  const parts = [];
  let material = null;
  gltf.scene.traverse((o) => {
    if (!o.isMesh) return;
    const g = o.geometry.clone().applyMatrix4(o.matrixWorld);
    // uv1 is kept: it is where the baked occlusion lives (aoMap reads channel 1).
    for (const name of Object.keys(g.attributes)) if (!['position', 'normal', 'uv', 'uv1'].includes(name)) g.deleteAttribute(name);
    parts.push(g.index ? g : g.toNonIndexed());
    material ??= Array.isArray(o.material) ? o.material[0] : o.material;
  });
  if (!parts.length) return null;
  const geometry = parts.length === 1 ? parts[0] : mergeGeometries(parts.map((g) => (g.index ? g.toNonIndexed() : g)));
  if (!geometry) return null;
  const turn = { '+z': 0, '-z': Math.PI, '+x': -Math.PI / 2, '-x': Math.PI / 2 }[front] ?? -Math.PI / 2;
  geometry.rotateY(turn);
  if (fit) {
    geometry.computeBoundingBox();
    const box = geometry.boundingBox, size = box.getSize(new THREE.Vector3()), centre = box.getCenter(new THREE.Vector3());
    geometry.translate(-centre.x, -box.min.y, -centre.z);
    geometry.scale(2.9 / size.x, 3.9 / size.y, (length - 0.6) / size.z);
  }
  if (!geometry.attributes.normal) geometry.computeVertexNormals();
  if (material) material.side = THREE.FrontSide;
  return { geometry, material };
}

// The occlusion baked beside a model (tools/trains/build_train.py) lives in its second UV channel, so
// three.js reads it as what it is — a shadow term on the indirect light — rather than it being burnt
// into the paint, where it would also darken the train in direct sun. Each model carries its own bake,
// which is why this clones: one material cannot hold two.
const textures = new THREE.TextureLoader();

// A model baked down from a dense one (tools/trains/bake_model.py) brings its own colour: the dense
// model's paint, in the coordinates the light one was unwrapped into. Nothing this file paints is
// used for it — which is the point, because what was wanted was that model's look.
async function baked(spec) {
  let map;
  try { map = await textures.loadAsync(`models/trains/${spec.colour}`); } catch { return null; }
  map.flipY = false;                     // the UVs came from a glTF, which measures v from the top
  map.colorSpace = THREE.SRGBColorSpace;
  map.anisotropy = 8;
  return new THREE.MeshStandardMaterial({ map, roughness: 0.34, metalness: 0.04 });
}

async function occluded(material, url, channel) {
  let map;
  try { map = await textures.loadAsync(url); } catch { return material; }
  map.channel = channel;
  map.colorSpace = THREE.NoColorSpace;   // a shadow term, not a colour
  map.flipY = false;                     // the UVs came from a glTF, which measures v from the top
  map.anisotropy = 8;
  const dressed = material.clone();
  dressed.aoMap = map;
  dressed.needsUpdate = true;
  return dressed;
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
    for (const p of paths) {
      const stock = taiwan && p.railway === 'rail' ? HSR_STOCK // (the owner's N700ST on every line, above)
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
      // `materials` is every material the set draws with: the painted one, and later a clone per model
      // carrying that model's baked occlusion. The saloon lights are turned up on all of them together.
      this.sets.push({ stock, mesh, model, beams, materials: [material], material, trains: list.map((path, i) => ({ path, s: (i * 613) % (path.length + GAP) })) });
    }
    this.dummy = new THREE.Object3D();
    this.a = new THREE.Vector3(); this.b = new THREE.Vector3();
    this.ready = this.loadModels(); // (the boxes run until the models arrive)
  }

  // Along the Line (decision 161): swaps what a stock is drawing with for its models: the cab model at both ends
  // (the rear one turned round), the middle model between them. A stock with only one of the two uses it for every
  // car. What it replaces is whatever was running — the boxes, or the shell lofted in code.
  async loadModels() {
    const wanted = this.sets.filter((set) => set.stock.models);
    if (!wanted.length) return;
    let index;
    try { index = await (await fetch('models/trains/index.json')).json(); } catch { return; }
    await Promise.all(wanted.map(async (set) => {
      const { stock, trains } = set;
      const load = async (id) => {
        const spec = index[id];
        if (!spec) return null;
        const model = await carModel(`models/trains/${spec.file}`, spec, stock.length);
        if (!model) return null;
        // Three kinds of model, and the index entry says which: one baked from a dense model brings
        // its own colour; one built to this file's atlas (build_train.py) wears the stock's painted
        // canvas; anything else keeps the material it came with.
        let material = spec.colour ? await baked(spec) : stock.livery ? set.material : model.material;
        if (!material) return null;
        if (spec.ao) material = await occluded(material, `models/trains/${spec.ao}`, spec.aoChannel ?? 1);
        if (material !== set.material) set.materials.push(material);
        return { geometry: model.geometry, material };
      };
      const [cab, car] = await Promise.all([load(stock.models.cab), load(stock.models.car)]);
      if (!cab && !car) return;
      const mesh = (m, count) => {
        const im = new THREE.InstancedMesh(m.geometry, m.material, Math.max(1, count));
        im.castShadow = im.receiveShadow = true;
        im.frustumCulled = false;
        this.group.add(im);
        return im;
      };
      // Nothing may await between taking the old meshes down and putting the new ones up: update()
      // runs every frame and reads `mesh` or `model` depending on which of them is there.
      for (const old of [set.mesh, set.model?.cabs, set.model?.cars]) {
        if (!old) continue;
        this.group.remove(old);
        old.geometry.dispose();
      }
      set.mesh = null;
      set.model = { cabs: mesh(cab ?? car, trains.length * 2), cars: mesh(car ?? cab, trains.length * Math.max(0, stock.cars - 2)) };
    }));
  }

  update(dt, night) {
    const { dummy, a, b } = this;
    this.beam.color.setRGB(2.2 * night, 2.1 * night, 1.8 * night);
    this.beam.visible = night > 0.02;
    for (const { stock, mesh, beams, materials, trains, model } of this.sets) {
      for (const m of materials) m.emissiveIntensity = 0.2 + night * 2.2; // the saloon lights and the lamps are always on
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
